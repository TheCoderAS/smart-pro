import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';


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

  Future<void> _connectNearest() async {
    if (!_active) return;
    state = state.copyWith(status: BleSessionStatus.scanning);
    final scanner = ref.read(bleScannerProvider);
    try {
      final beacons = await scanner.collect(meshId: _meshId);
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
    final client = BleControlClient(ref.read(reactiveBleProvider), deviceId);
    await client.connect();
    _client = client;
    _connectedDeviceId = deviceId;
    _stateSub = client.stateStream.listen(_stateController.add);
    state = state.copyWith(
      status: BleSessionStatus.connected,
      masterName: name,
    );

    // Pull an initial full state so the dashboard fills immediately.
    final token = ref.read(tokenProvider);
    if (token != null) {
      try {
        final map = await client.request(BleCommands.state(token));
        _stateController.add(StateSnapshot.fromJson(map));
      } on Exception catch (e) {
        log.w('initial ble state fetch failed: $e');
      }
    }
  }

  void _startRoamLoop() {
    _roamTimer?.cancel();
    _roamTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_active || _meshId == null || _connectedDeviceId == null) return;
      try {
        final beacons =
            await ref.read(bleScannerProvider).collect(meshId: _meshId);
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
/// using the shared token.
class BleControlTransport implements ControlTransport {
  const BleControlTransport(this._client, this._token);

  final BleControlClient? _client;
  final String? _token;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  Future<void> setRelay({required String id, required bool on, int? ch}) async {
    final client = _client;
    final token = _token;
    if (client == null || token == null) {
      throw StateError('BLE not connected');
    }
    // id already carries the channel suffix over BLE; ch is ignored.
    await client.request(BleCommands.relay(token: token, id: id, on: on));
  }

  @override
  Future<void> killAll() async {
    final client = _client;
    final token = _token;
    if (client == null || token == null) {
      throw StateError('BLE not connected');
    }
    await client.request(BleCommands.killAll(token));
  }
}
