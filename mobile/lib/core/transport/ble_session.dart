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
import '../logging/log.dart';
import '../storage/master_registry.dart';
import '../ws/state_dto.dart';
import 'access_reset.dart';
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

/// Owns the live BLE connection: scan for the paired home, connect to
/// the nearest master, hold the client. Activated when the active
/// transport is BLE; torn down when it isn't. Handoff between masters
/// happens through the retry loop when a link drops — never by scanning
/// alongside a live connection.
class BleSessionController extends Notifier<BleSessionState> {
  BleControlClient? _client;
  StreamSubscription<StateSnapshot>? _stateSub;
  final _stateController = StreamController<StateSnapshot>.broadcast();
  int? _meshId;

  /// The mesh id the connected device's own beacon advertised (0 =
  /// standalone/none). Input to the identity check only — never merged
  /// into the scan filter or the registry from here.
  int _connectedBeaconMeshId = 0;

  /// The master the app is pointed at, when it knows. Masters advertise
  /// as `U{UID}`, and that name is the only thing in a beacon that tells
  /// two standalone masters apart — the manufacturer data carries a mesh
  /// id and flags, nothing identifying.
  String? _targetUid;
  bool _active = false;

  // Serialises scans: flutter_reactive_ble allows only one active scan,
  // so a manual reconnect and a background retry must not scan at once.
  Future<void> _scanGate = Future<void>.value();

  // Serialises link changes. A background retry and a reconnect could
  // both call _openClient, leaving two GATT connections open to the same
  // master. The master keys each connection's proof on its own nonce but
  // tracks the request handle globally, so whichever wrote last decided
  // which nonce the other's proof was checked against — and the loser was
  // rejected as an invalid proof.
  Future<void> _linkGate = Future<void>.value();

  /// Hard cap on any one serialised link operation, and on a scan beyond
  /// its own window.
  ///
  /// The gates had no timeout, and one hung plugin call wedged them for
  /// good. Android's BLE stack is known to hang a scan-cancel, a connect
  /// or a dispose right after a supervision-timeout disconnect — exactly
  /// the out-of-range case — and when it did, every retry queued behind
  /// the wedged operation forever. The app sat on "Reconnecting" for half
  /// an hour while the master, back in range and advertising, logged not
  /// one connection attempt.
  static const linkOpCap = Duration(seconds: 30);
  static const scanOpGrace = Duration(seconds: 10);

  /// Bumped when a gated operation is abandoned. An abandoned attempt may
  /// still complete much later; the epoch check stops it installing its
  /// client or its verdict over whatever superseded it.
  int _linkEpoch = 0;

  Future<void> _serialised(Future<void> Function() body) {
    final next = _linkGate.then((_) async {
      try {
        await body().timeout(linkOpCap);
      } on TimeoutException {
        _linkEpoch++;
        log.w('ble link operation exceeded ${linkOpCap.inSeconds}s — '
            'abandoning it and releasing the gate');
      }
    });
    _linkGate = next.then((_) {}, onError: (_) {});
    return next;
  }

  // There is deliberately NO background roam scanning. While connected,
  // this session never touches the scanner: a scan and a live GATT
  // connection share one radio, and every duty-cycle scheme tried here
  // (3s/3s, then 2s in 20s with quiet windows) ended the same way —
  // writes crawling into seconds whenever a scan overlapped a tap, and a
  // hung scan-cancel leaving the radio scanning forever. Roaming still
  // works: leaving a master's range drops the link, and the retry loop
  // scans and connects to the strongest master of the home — which is
  // what a real-world handoff is.

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
      // The link can have healed while this timer waited (another flow
      // connected first). Running anyway was the two-master flap: the
      // retry's connect pass tears the healthy link down (close before
      // connect), the master logs "remote user terminated", the teardown
      // schedules the next retry, and the cycle feeds itself forever.
      if ((_client?.isConnected ?? false) &&
          state.status == BleSessionStatus.connected) {
        _cancelRetry();
        return;
      }
      try {
        // Balanced, not lowLatency: this can run for a long time when the
        // user is away from the house, and it is a background retry rather
        // than something anyone is waiting on.
        await _serialised(() => _connectNearest(mode: ScanMode.balanced));
      } on Object catch (e) {
        // A thrown attempt must not kill the loop — an uncaught error in
        // a Timer callback would have ended retrying for good, silently.
        log.w('ble retry attempt failed: $e');
      }
      if (!_active) return;
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
    // The timeout is on the gated result, so a collect that never returns
    // still releases the gate for the scans queued behind it.
    final result = _scanGate
        .then((_) => ref
            .read(bleScannerProvider)
            .collect(meshId: _meshId, window: window, mode: mode))
        .timeout(window + scanOpGrace);
    _scanGate = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Pushes a snapshot to consumers.
  void _emit(StateSnapshot snap) {
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
  ///
  /// [uid] is the master the app is actually pointed at. Passing it is
  /// what lets a second master be reached at all: the mesh filter used to
  /// be sticky, so once a meshed master had been seen the scan kept
  /// filtering to that mesh and a standalone master — whose beacon
  /// carries mesh id 0 — was dropped before it could ever be connected.
  Future<void> activate({int? meshId, String? uid}) async {
    // A different master than last time is a retarget, not a no-op: the
    // filter and the live link both have to be rebuilt for it.
    final retarget = uid != null && uid != _targetUid;
    if (retarget) {
      log.d('ble retarget → $uid (mesh ${meshId?.toRadixString(16)})');
      _targetUid = uid;
      _meshId = meshId; // replaces, never merges — this is the fix
      await _closeClient();
      _cancelRetry();
    }

    // Already live. A second reconcile — app start, then the session
    // resolving — must not tear a working link down and scan again; over
    // Bluetooth that costs seconds the user spends looking at a spinner.
    //
    // Gated on the GATT link, not only on the status: the status is a
    // state machine that can lag reality, and trusting it alone would let
    // a dead link block its own replacement.
    if (!retarget &&
        _active &&
        (_client?.isConnected ?? false) &&
        state.status == BleSessionStatus.connected) {
      _meshId ??= meshId;
      return;
    }
    // A switch is added by signing in, and no other way. With nothing
    // added, Bluetooth does not scan, connect, or record. The old
    // "nothing paired yet — adopt whoever we find" shortcut is how a
    // freshly REMOVED master re-added itself while a new sign-in's
    // registration was still in flight.
    try {
      final masters = await ref.read(masterRegistryProvider.future);
      if (masters.isEmpty) {
        await deactivate();
        return;
      }
    } on Object catch (e) {
      log.w('ble activate: registry unreadable, staying down: $e');
      await deactivate();
      return;
    }
    _active = true;
    // Keep a mesh id learned from a previous connect when the caller
    // hasn't got one — it is what filters the scan to the user's own
    // system rather than every Unisync master in earshot.
    _meshId = meshId ?? _meshId;
    try {
      await _serialised(_connectNearest);
    } on Object catch (e) {
      log.w('ble activate attempt failed: $e');
    }
    if (state.status != BleSessionStatus.connected) _scheduleRetry();
  }

  Future<void> deactivate() async {
    _active = false;
    await _teardown();
    if (state.status != BleSessionStatus.idle) {
      state = const BleSessionState(status: BleSessionStatus.idle);
    }
  }

  /// Manual reconnect (the dashboard's refresh action). Re-scans and
  /// re-opens the client — safe to call while connected.
  Future<void> reconnect() async {
    if (!_active) {
      await activate(meshId: _meshId);
      return;
    }
    // An explicit ask, so start the backoff over: the user is standing
    // there waiting, not sitting in a background retry cycle. Forced —
    // this is the one caller allowed to rebuild a live link.
    _cancelRetry();
    try {
      await _serialised(() => _connectNearest(force: true));
    } on Object catch (e) {
      log.w('ble reconnect attempt failed: $e');
    }
    if (state.status != BleSessionStatus.connected) _scheduleRetry();
  }

  Future<void> _connectNearest({
    ScanMode mode = ScanMode.lowLatency,
    bool force = false,
  }) async {
    if (!_active) return;
    // A healthy link makes this a no-op unless the user explicitly asked
    // for a rebuild. Every racing caller — a reconcile queued behind a
    // succeeding connect, a stale retry — used to reach _openClient,
    // whose first act is closing the live client: the self-inflicted
    // "link lost" at the heart of the two-master flap.
    if (!force &&
        (_client?.isConnected ?? false) &&
        state.status == BleSessionStatus.connected) {
      return;
    }
    // If this attempt is abandoned by the gate, its late state writes
    // must not stomp whatever a fresh attempt has since established.
    final epoch = _linkEpoch;
    state = state.copyWith(status: BleSessionStatus.scanning);
    try {
      final beacons = await _scan(mode: mode);
      if (epoch != _linkEpoch) return;
      if (beacons.isEmpty) {
        state = const BleSessionState(
          status: BleSessionStatus.failed,
          error: 'No switch found nearby over Bluetooth.',
        );
        return;
      }
      // The master we are actually pointed at wins outright, however weak
      // it is; a stronger stranger is not a substitute for it. Below that,
      // prefer an unoccupied master, then the strongest.
      final want = _targetUid?.toUpperCase();
      bool isTarget(MasterBeacon b) =>
          want != null && b.name.toUpperCase() == 'U$want';
      beacons.sort((a, b) {
        final targetCmp =
            (isTarget(b) ? 1 : 0).compareTo(isTarget(a) ? 1 : 0);
        if (targetCmp != 0) return targetCmp;
        final busyCmp = (a.advert.clientConnected ? 1 : 0)
            .compareTo(b.advert.clientConnected ? 1 : 0);
        if (busyCmp != 0) return busyCmp;
        return b.rssi.compareTo(a.rssi);
      });
      final target = beacons.first;
      // What THIS device claims to belong to, held for the post-connect
      // identity check. Never merged into the scan filter: the filter
      // describes the user's home (from the registry), and learning it
      // from whatever answered the scan let a stranger redefine the home.
      _connectedBeaconMeshId =
          target.advert.isStandalone ? 0 : target.meshId;

      state = state.copyWith(
        status: BleSessionStatus.connecting,
        masterName: target.name,
      );
      await _openClient(target.deviceId, target.name);
    } on Object catch (e) {
      log.w('ble connect failed: $e');
      if (epoch != _linkEpoch) return;
      state = BleSessionState(
        status: BleSessionStatus.failed,
        error: 'Could not connect over Bluetooth.',
      );
    }
  }

  Future<void> _openClient(String deviceId, String name) async {
    final epoch = _linkEpoch;
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
    try {
      await client.connect();
    } on Object {
      // A failed connect leaves the plugin still trying in the
      // background; dropping the handle without disposing leaked a zombie
      // connection the master could see but the app never used.
      await _disposeQuietly(client);
      rethrow;
    }
    if (epoch != _linkEpoch || !_active) {
      // Abandoned while connecting — a superseded attempt must not
      // install its client over the one that replaced it.
      await _disposeQuietly(client);
      return;
    }
    _client = client;
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
      final snap = StateSnapshot.fromJson(map);
      // Check who actually answered before showing anything.
      //
      // Nothing did. Power one master down, bring a different one up, and
      // the scan would connect to whatever was in range -- a master that
      // had never been set up in this app -- and the dashboard would carry
      // on showing the old master's name over the new one's switches. The
      // Wi-Fi path has guarded this since the beginning; Bluetooth never
      // did.
      if (!await _isKnownMaster(snap.selfUid)) {
        log.w('ble: ${snap.selfUid} is not set up in this app, refusing');
        await _closeClient();
        state = const BleSessionState(
          status: BleSessionStatus.failed,
          error: 'Found a switch that is not set up in this app.',
        );
        return;
      }
      _emit(snap);
      // Only now, from an accepted master, may the home's mesh id be
      // learned — see _rememberMesh.
      await _rememberMesh(snap.selfUid);
    } on BleTokenRejected {
      // Counts toward access-reset (a genuinely changed password rejects
      // here again on the very next reconnect); a single churn blip
      // never shows the screen.
      ref.read(accessResetProvider.notifier).strike();
      log.w('initial ble state fetch rejected');
    } on Exception catch (e) {
      log.w('initial ble state fetch failed: $e');
    }
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

  /// Whether [uid] is a master this app is actually set up with.
  ///
  /// The rule, verbatim from the owner: only what is currently added in
  /// the app counts — removed means removed, never recalled. The one
  /// exception is the mesh feature: a master is family only when the
  /// added master has a valid mesh id AND the answering device's own
  /// broadcast carries that same id. Zero/null is never a valid mesh id
  /// and matches nothing.
  Future<bool> _isKnownMaster(String uid) async {
    try {
      final masters = await ref.read(masterRegistryProvider.future);
      // Nothing added means nothing is trusted. Adding happens by
      // signing in over Wi-Fi, never by Bluetooth discovery — the old
      // "empty list ⇒ adopt" escape re-added a removed master.
      if (masters.isEmpty) return false;
      if (masters.any((m) => m.uid == uid)) return true;
      final advertised = _connectedBeaconMeshId;
      if (advertised != 0 &&
          masters.any((m) => m.meshId != null &&
              m.meshId != 0 &&
              m.meshId == advertised)) {
        return true;
      }
      return false;
    } on Object catch (e) {
      // Registry unreadable: refusing here would strand someone with a
      // working link over a bookkeeping failure.
      log.w('master identity check skipped: $e');
      return true;
    }
  }

  /// Records the home's mesh id — learned ONLY from the master the user
  /// actually added, about itself, after it passed the identity check.
  ///
  /// The old version stamped the answering device's mesh id onto any
  /// saved master that lacked one, before identity was even verified.
  /// That is how a removed master talked its way back in: one connection
  /// to it grafted its mesh id onto the new master's record, and the
  /// next identity check waved it through as family.
  Future<void> _rememberMesh(String uid) async {
    final mesh = _connectedBeaconMeshId;
    if (mesh == 0) return;
    try {
      final notifier = ref.read(masterRegistryProvider.notifier);
      final masters = ref.read(masterRegistryProvider).value ?? const [];
      for (final m in masters) {
        if (m.uid == uid && (m.meshId == null || m.meshId == 0)) {
          await notifier.upsert(
            SavedMaster(
              uid: m.uid,
              name: m.name,
              ssid: m.ssid,
              meshId: mesh,
            ),
          );
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
    try {
      await (_stateSub?.cancel() ?? Future<void>.value())
          .timeout(const Duration(seconds: 2));
    } on Object catch (e) {
      log.w('state subscription cancel hung: $e');
    }
    _stateSub = null;
    final c = _client;
    _client = null;
    if (c != null) await _disposeQuietly(c);
  }

  /// Dispose with a cap: the plugin's teardown can hang right after an
  /// unclean disconnect, and a hung dispose inside the link gate is how
  /// reconnecting wedged for half an hour.
  Future<void> _disposeQuietly(BleControlClient c) async {
    try {
      await c.dispose().timeout(const Duration(seconds: 3));
    } on Object catch (e) {
      log.w('ble client dispose hung/failed: $e');
    }
  }

  Future<void> _teardown() async {
    _cancelRetry();
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
