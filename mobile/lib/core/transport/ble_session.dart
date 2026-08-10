import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' show ScanMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/extensions/domain/extension_models.dart';
import '../../features/firmware/domain/firmware_models.dart';
import '../api/dio_client.dart';
import '../ble/advert.dart';
import '../ble/ble_control_client.dart';
import '../ble/ble_scanner.dart';
import '../ble/endpoints_ble.dart';
import '../ble/recovery_service.dart' show reactiveBleProvider;
import '../ble/roaming.dart';
import '../logging/log.dart';
import '../storage/master_registry.dart';
import '../ws/state_dto.dart';
import 'control_transport.dart';

/// Runtime status of the BLE control session, surfaced to the UI.
enum BleSessionStatus { idle, scanning, connecting, connected, failed }

class BleSessionState {
  const BleSessionState({
    required this.status,
    this.error,
    this.masterName,
  });

  final BleSessionStatus status;
  final String? error;
  final String? masterName;

  BleSessionState copyWith({
    BleSessionStatus? status,
    String? error,
    String? masterName,
  }) => BleSessionState(
    status: status ?? this.status,
    error: error,
    masterName: masterName ?? this.masterName,
  );
}

final bleSessionProvider =
    NotifierProvider<BleSessionController, BleSessionState>(
  BleSessionController.new,
);

/// Owns the live BLE connection: scan for the paired mesh, connect to
/// the nearest master, hold the client, and roam when a stronger master
/// appears. Activated when the active transport is BLE; torn down when
/// it isn't.
class BleSessionController extends Notifier<BleSessionState> {
  BleControlClient? _client;
  StreamSubscription<StateSnapshot>? _stateSub;
  final _stateController = StreamController<StateSnapshot>.broadcast();
  final _roam = RoamPolicy();
  Timer? _roamTimer;
  int? _meshId;
  String? _connectedDeviceId;
  bool _active = false;
  // Whether the connected master reports peers. No peers ⇒ nothing to
  // roam to ⇒ the roam loop skips scanning entirely, so a single-master
  // system never runs the radio-hungry background scan.
  bool _hasPeers = false;

  // Serialises scans: flutter_reactive_ble allows only one active scan,
  // so a manual reconnect and the roam loop must not scan at once.
  Future<void> _scanGate = Future<void>.value();

  Future<List<MasterBeacon>> _scan({
    Duration window = const Duration(seconds: 4),
    ScanMode mode = ScanMode.lowLatency,
  }) {
    final result = _scanGate.then((_) => ref
        .read(bleScannerProvider)
        .collect(meshId: _meshId, window: window, mode: mode));
    _scanGate = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Pushes a snapshot to consumers and tracks whether roaming is even
  /// worth scanning for.
  void _emit(StateSnapshot snap) {
    _hasPeers = snap.peers.isNotEmpty;
    _stateController.add(snap);
  }

  @override
  BleSessionState build() {
    ref.onDispose(_teardown);
    return const BleSessionState(status: BleSessionStatus.idle);
  }

  /// Snapshots pushed by the connected master — interchangeable with
  /// the WebSocket's (BLE spec §State push).
  Stream<StateSnapshot> get stateStream => _stateController.stream;

  BleControlClient? get client => _client;

  /// Starts (or restarts) a BLE session for the paired [meshId]
  /// (null = any Unisync master, used before a mesh is known).
  Future<void> activate({int? meshId}) async {
    _active = true;
    _meshId = meshId;
    await _connectNearest();
    _startRoamLoop();
  }

  Future<void> deactivate() async {
    _active = false;
    await _teardown();
    if (state.status != BleSessionStatus.idle) {
      state = const BleSessionState(status: BleSessionStatus.idle);
    }
  }

  /// Manual reconnect (the dashboard's refresh action). Stops roaming,
  /// re-scans, and re-opens the client — safe to call while connected.
  Future<void> reconnect() async {
    if (!_active) {
      await activate(meshId: _meshId);
      return;
    }
    _roamTimer?.cancel();
    _roam.clear();
    await _connectNearest();
    _startRoamLoop();
  }

  Future<void> _connectNearest() async {
    if (!_active) return;
    state = state.copyWith(status: BleSessionStatus.scanning);
    try {
      final beacons = await _scan();
      if (beacons.isEmpty) {
        state = const BleSessionState(
          status: BleSessionStatus.failed,
          error: 'No switch found nearby over Bluetooth.',
        );
        return;
      }
      // Prefer an unoccupied master, then the strongest.
      beacons.sort((a, b) {
        final busyCmp = (a.advert.clientConnected ? 1 : 0)
            .compareTo(b.advert.clientConnected ? 1 : 0);
        if (busyCmp != 0) return busyCmp;
        return b.rssi.compareTo(a.rssi);
      });
      final target = beacons.first;
      _meshId ??= target.advert.isStandalone ? null : target.meshId;

      state = state.copyWith(
        status: BleSessionStatus.connecting,
        masterName: target.name,
      );
      await _openClient(target.deviceId, target.name);

      // Remember the mesh id against a saved master so future scans
      // filter to this system.
      if (target.meshId != 0) {
        await _rememberMesh(target);
      }
    } on Object catch (e) {
      log.w('ble connect failed: $e');
      state = BleSessionState(
        status: BleSessionStatus.failed,
        error: 'Could not connect over Bluetooth.',
      );
    }
  }

  Future<void> _openClient(String deviceId, String name) async {
    await _closeClient();
    // BLE carries no login (v5.1 Epic 5) — a Wi-Fi-issued token is
    // required before any command can be proved.
    final token = ref.read(tokenProvider);
    if (token == null) {
      state = const BleSessionState(
        status: BleSessionStatus.failed,
        error: 'Sign in over Wi-Fi first.',
      );
      return;
    }
    final client =
        BleControlClient(ref.read(reactiveBleProvider), deviceId, token);
    await client.connect();
    _client = client;
    _connectedDeviceId = deviceId;
    _stateSub = client.stateStream.listen(_emit);
    state = state.copyWith(
      status: BleSessionStatus.connected,
      masterName: name,
    );

    // Pull an initial full state so the dashboard fills immediately.
    try {
      final map = await client.request((p) => BleCommands.state(p));
      _emit(StateSnapshot.fromJson(map));
    } on Exception catch (e) {
      log.w('initial ble state fetch failed: $e');
    }
  }

  void _startRoamLoop() {
    _roamTimer?.cancel();
    _roamTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      // Only scan when roaming is actually possible: an active mesh
      // session with peers to roam to. A single-master system never
      // scans in the background — that was the "app feels slow" cause.
      if (!_active ||
          _meshId == null ||
          _connectedDeviceId == null ||
          !_hasPeers) {
        return;
      }
      try {
        // Balanced (not lowLatency) so background roaming doesn't
        // saturate the radio the live connection is sharing.
        final beacons = await _scan(
          window: const Duration(seconds: 3),
          mode: ScanMode.balanced,
        );
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final b in beacons) {
          _roam.observe(b, now);
        }
        final hop = _roam.chooseHop(
          connectedDeviceId: _connectedDeviceId,
          candidates: beacons,
          nowMillis: now,
        );
        if (hop != null) {
          final target = beacons.firstWhere((b) => b.deviceId == hop);
          log.d('ble roam → ${target.name}');
          await _openClient(target.deviceId, target.name); // token reused
        }
      } on Object catch (e) {
        log.w('roam scan failed: $e');
      }
    });
  }

  /// Re-request a full state snapshot now (pull-to-refresh / after a
  /// reorder) and push it onto the stream.
  Future<void> refreshState() async {
    final client = _client;
    final token = ref.read(tokenProvider);
    if (client == null || token == null) return;
    final map = await client.request((p) => BleCommands.state(p));
    _emit(StateSnapshot.fromJson(map));
  }

  Future<void> _rememberMesh(MasterBeacon beacon) async {
    try {
      final notifier = ref.read(masterRegistryProvider.notifier);
      final masters = ref.read(masterRegistryProvider).value ?? const [];
      // Attach the mesh id to a saved master that lacks one.
      for (final m in masters) {
        if (m.meshId == null) {
          await notifier.upsert(
            SavedMaster(
              uid: m.uid,
              name: m.name,
              ssid: m.ssid,
              meshId: beacon.meshId,
            ),
          );
          break;
        }
      }
    } on Object catch (e) {
      log.w('remember mesh failed: $e');
    }
  }

  Future<void> _closeClient() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _client?.dispose();
    _client = null;
    _connectedDeviceId = null;
  }

  Future<void> _teardown() async {
    _roamTimer?.cancel();
    _roamTimer = null;
    _roam.clear();
    await _closeClient();
  }
}

/// BLE control path — issues commands over the active [BleControlClient]
/// using the shared token. Reads (`exts`, `audit`, `fwlist`) and the
/// `reorder` write all work over BLE per the v2 contract; only firmware
/// transfer stays Wi-Fi.
class BleControlTransport implements ControlTransport {
  const BleControlTransport(this._client);

  final BleControlClient? _client;

  /// The live client. The token lives inside it (used only to derive
  /// per-command proofs) — commands never carry it.
  BleControlClient get _live {
    final client = _client;
    if (client == null) throw StateError('BLE not connected');
    return client;
  }

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  Future<void> setRelay({required String id, required bool on, int? ch}) async {
    final client = _live;
    // id already carries the channel suffix over BLE; ch is ignored.
    await client.request((p) => BleCommands.relay(proof: p, id: id, on: on));
  }

  @override
  Future<void> killAll() async {
    final client = _live;
    await client.request((p) => BleCommands.killAll(p));
  }

  @override
  Future<List<ExtensionInfo>> extensions() async {
    final client = _live;
    final map = await client.request((p) => BleCommands.extensions(p));
    final list = map['extensions'];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) ExtensionInfo.fromJson(e),
    ];
  }

  @override
  Future<void> reorder(List<String> orderedIds) async {
    final client = _live;
    await client.request(
      (p) => BleCommands.reorder(proof: p, order: orderedIds.join(',')),
    );
  }

  @override
  Future<void> renameExtension({required int slot, required String name}) async {
    final client = _live;
    await client
        .request((p) =>
            BleCommands.renameExtension(proof: p, slot: slot, name: name));
  }

  @override
  Future<void> renameSwitch({required String id, required String name}) async {
    final client = _live;
    await client
        .request((p) => BleCommands.renameSwitch(proof: p, id: id, name: name));
  }

  @override
  Future<void> renameMaster(String name) async {
    final client = _live;
    await client.request((p) => BleCommands.renameMaster(proof: p, name: name));
  }

  @override
  Future<FwStatus> fwStatus() async {
    final client = _live;
    final map = await client.request((p) => BleCommands.fwList(p));
    return FwStatus.fromJson(Map<String, dynamic>.from(map));
  }
}
