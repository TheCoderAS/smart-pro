import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' show ScanMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/extensions/domain/extension_models.dart';
import '../../features/firmware/domain/firmware_models.dart';
import '../api/dio_client.dart';
import '../ble/advert.dart';
import '../ble/ble_control_client.dart';
import '../ble/ble_proof.dart';
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

  // Serialises link changes. The roam loop and a reconnect could both
  // call _openClient, leaving two GATT connections open to the same
  // master. The master keys each connection's proof on its own nonce but
  // tracks the request handle globally, so whichever wrote last decided
  // which nonce the other's proof was checked against — and the loser was
  // rejected as an invalid proof.
  Future<void> _linkGate = Future<void>.value();

  Future<void> _serialised(Future<void> Function() body) {
    final next = _linkGate.then((_) => body());
    _linkGate = next.then((_) {}, onError: (_) {});
    return next;
  }

  Timer? _retryTimer;
  int _retryAttempt = 0;

  /// Backoff between reconnect attempts, capped so walking back into
  /// range recovers on its own within about twenty seconds. Uncapped
  /// growth would be cheaper on the radio and useless to someone standing
  /// in their own hallway waiting for a light.
  static const _retryBackoff = <int>[1, 2, 4, 8, 15, 20];

  /// Delay before attempt [attempt] (0-based). Public so the schedule can
  /// be checked without a radio.
  static Duration retryDelay(int attempt) => Duration(
        seconds: _retryBackoff[
            attempt < _retryBackoff.length ? attempt : _retryBackoff.length - 1],
      );

  /// Try again, and keep trying.
  ///
  /// The session used to give up the moment the link dropped: status went
  /// to `failed` and nothing ever retried, so going out of range or power
  /// cycling the master left the app showing "reconnecting" until the user
  /// found the retry button — and once the engine started surviving a
  /// swipe, even reopening the app stopped helping.
  void _scheduleRetry() {
    if (!_active) return;
    _retryTimer?.cancel();
    final delay = retryDelay(_retryAttempt);
    _retryAttempt++;
    log.d('ble retry in ${delay.inSeconds}s (attempt $_retryAttempt)');
    _retryTimer = Timer(delay, () async {
      if (!_active) return;
      // Balanced, not lowLatency: this can run for a long time when the
      // user is away from the house, and it is a background retry rather
      // than something anyone is waiting on.
      await _serialised(() => _connectNearest(mode: ScanMode.balanced));
      if (state.status != BleSessionStatus.connected) _scheduleRetry();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

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
    // Already live. A second reconcile — app start, then the session
    // resolving — must not tear a working link down and scan again; over
    // Bluetooth that costs seconds the user spends looking at a spinner.
    //
    // Gated on the GATT link, not only on the status: the status is a
    // state machine that can lag reality, and trusting it alone would let
    // a dead link block its own replacement.
    if (_active &&
        (_client?.isConnected ?? false) &&
        state.status == BleSessionStatus.connected) {
      _meshId ??= meshId;
      return;
    }
    _active = true;
    // Keep a mesh id learned from a previous connect when the caller
    // hasn't got one — it is what filters the scan to the user's own
    // system rather than every Unisync master in earshot.
    _meshId = meshId ?? _meshId;
    await _serialised(_connectNearest);
    if (state.status != BleSessionStatus.connected) _scheduleRetry();
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
    // An explicit ask, so start the backoff over: the user is standing
    // there waiting, not sitting in a background retry cycle.
    _cancelRetry();
    await _serialised(_connectNearest);
    if (state.status != BleSessionStatus.connected) _scheduleRetry();
    _startRoamLoop();
  }

  Future<void> _connectNearest({
    ScanMode mode = ScanMode.lowLatency,
  }) async {
    if (!_active) return;
    state = state.copyWith(status: BleSessionStatus.scanning);
    try {
      final beacons = await _scan(mode: mode);
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
    final client = BleControlClient(
      ref.read(reactiveBleProvider),
      deviceId,
      token,
      onDisconnected: _onLinkLost,
    );
    await client.connect();
    _client = client;
    _connectedDeviceId = deviceId;
    _stateSub = client.stateStream.listen(_emit);
    state = state.copyWith(
      status: BleSessionStatus.connected,
      masterName: name,
    );
    // Back up and running: forget the backoff so the next drop retries
    // briskly rather than inheriting a long delay from an old outage.
    _cancelRetry();

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
          // Serialised with reconnects: two overlapping opens leave two
          // connections to one master, and the master's proof check then
          // has two nonces to choose between.
          await _serialised(
            () => _openClient(target.deviceId, target.name), // token reused
          );
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

  /// The master went away without being asked to. Reflect that instead of
  /// sitting on a stale "connected", which left the dashboard live and
  /// tappable minutes after the master had been powered off — taps queued,
  /// timed out, and silently reverted.
  void _onLinkLost() {
    if (!_active) return;
    log.w('ble link lost');
    if (state.status == BleSessionStatus.connected) {
      state = state.copyWith(
        status: BleSessionStatus.failed,
        error: 'Lost the connection to your switch.',
      );
    }
    // Drop the corpse. The transport reads `client` straight off this
    // session, so leaving a disconnected client in place means every tap
    // writes to a characteristic that is not there and waits out the
    // timeout instead of failing.
    //
    // Off this callback: we are inside the connection stream's own
    // listener, and disposing cancels that subscription.
    scheduleMicrotask(() async {
      await _closeClient();
      _scheduleRetry();
    });
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
    _cancelRetry();
    _roam.clear();
    await _closeClient();
  }
}

/// BLE control path — issues commands over the active [BleControlClient]
/// using the shared token. Reads (`exts`, `audit`, `fwlist`) and the
/// `reorder` write all work over BLE per the v2 contract; only firmware
/// transfer stays Wi-Fi.
class BleControlTransport implements ControlTransport {
  const BleControlTransport(this._client, {this.onTokenRejected});

  final BleControlClient? _client;

  /// Called when the master rejects our session (password changed).
  /// BLE has no login, so the UI routes to a Wi-Fi sign-in instruction
  /// screen rather than failing silently (v5.1 Epic 5).
  final void Function()? onTokenRejected;

  /// The live client. The token lives inside it (used only to derive
  /// per-command proofs) — commands never carry it.
  BleControlClient get _live {
    final client = _client;
    if (client == null) throw StateError('BLE not connected');
    return client;
  }

  /// Single choke point for every BLE command so a dead session is
  /// always surfaced, never swallowed by a caller's `on Exception`.
  Future<Map<String, Object?>> _send(
    Map<String, Object?> Function(BleProof proof) build,
  ) async {
    try {
      return await _live.request(build);
    } on BleTokenRejected {
      onTokenRejected?.call();
      rethrow;
    }
  }

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  Future<void> setRelay({
    required String id,
    required bool on,
    int? ch,
    String? masterUid,
  }) async {
    // id already carries the channel suffix over BLE; ch is ignored. The
    // uid, when present, tells the connected master to forward over the
    // mesh — Bluetooth controls the whole mesh, not just what's in range.
    await _send(
      (p) => BleCommands.relay(proof: p, id: id, on: on, masterUid: masterUid),
    );
  }

  @override
  Future<void> killAll() async {
    await _send((p) => BleCommands.killAll(p));
  }

  @override
  Future<List<ExtensionInfo>> extensions() async {
    final map = await _send((p) => BleCommands.extensions(p));
    final list = map['extensions'];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) ExtensionInfo.fromJson(e),
    ];
  }

  @override
  Future<void> reorder(List<String> orderedIds) async {
    await _send(
      (p) => BleCommands.reorder(proof: p, order: orderedIds.join(',')),
    );
  }

  @override
  Future<void> renameExtension({required int slot, required String name}) async {
    await _send((p) =>
            BleCommands.renameExtension(proof: p, slot: slot, name: name));
  }

  @override
  Future<void> renameSwitch({required String id, required String name}) async {
    await _send((p) => BleCommands.renameSwitch(proof: p, id: id, name: name));
  }

  @override
  Future<void> renameMaster(String name) async {
    await _send((p) => BleCommands.renameMaster(proof: p, name: name));
  }

  @override
  Future<void> setRestore({required String id, required bool restore}) async {
    await _send(
      (p) => BleCommands.setRestore(proof: p, id: id, restore: restore),
    );
  }

  @override
  Future<FwStatus> fwStatus() async {
    final map = await _send((p) => BleCommands.fwList(p));
    return FwStatus.fromJson(Map<String, dynamic>.from(map));
  }
}
