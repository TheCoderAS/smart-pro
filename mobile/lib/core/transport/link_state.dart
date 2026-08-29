import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../api/endpoints.dart';
import '../logging/log.dart';
import '../storage/master_registry.dart';
import '../storage/secure_store.dart';
import '../wifi/wifi_service.dart';
import 'ble_session.dart';
import 'control_transport.dart';
import 'transport_manager.dart';

/// What the persistent connection indicator shows (story Epic 1,
/// "Connection awareness").
enum LinkState {
  connectedWifi,
  connectedBle,
  reconnecting,
  outOfRange;

  bool get connected =>
      this == LinkState.connectedWifi || this == LinkState.connectedBle;

  /// Controls are live only on a confirmed link. Anything else and switch
  /// states are last-seen values, not truth — so the user must not be able
  /// to tap one and discover the problem that way.
  bool get controlsEnabled => connected;
}

final linkStateProvider =
    NotifierProvider<LinkMonitor, LinkState>(LinkMonitor.new);

/// Drives the connection indicator from events *plus* a heartbeat, because
/// events alone miss the case the story calls out: the link looks alive and
/// the master is gone. Target is ~5 s to reflect a real loss.
///
/// Roaming is the counterweight. A Bluetooth handoff tears the GATT link
/// down and builds a new one, and Wi-Fi roaming drops the socket — flashing
/// "reconnecting" through every one of those would make walking around the
/// house look broken. So a drop has to outlive a short grace window before
/// it surfaces. Silent when the handoff works, honest when it doesn't.
class LinkMonitor extends Notifier<LinkState> {
  /// How long a drop is tolerated before the user hears about it. Covers a
  /// Wi-Fi re-association or a Bluetooth roam; a real loss outlives it.
  static const grace = Duration(seconds: 4);

  /// Past this, it isn't a handoff any more.
  static const outOfRangeAfter = Duration(seconds: 20);

  /// Heartbeat interval. Fast enough for the ~5 s target once the grace
  /// window is added, slow enough to stay far inside the master's 40
  /// requests per 10 seconds.
  static const heartbeatEvery = Duration(seconds: 3);

  Timer? _ticker;
  DateTime? _lastGood;

  /// Single-flight guard. The ticker fires every 3 s but a probe against
  /// a dead route takes the full 5 s connect timeout, so without this
  /// probes overlap — twice the requests, twice the log spam, nothing
  /// learned twice.
  bool _probing = false;

  /// Consecutive misses, for compact logging and the rebind heuristic.
  int _misses = 0;

  @override
  LinkState build() {
    // Rebuilding on transport changes keeps the heartbeat pointed at the
    // right link without the notifier having to watch anything itself.
    ref.watch(currentTransportProvider);
    ref.onDispose(() => _ticker?.cancel());
    _ticker = Timer.periodic(heartbeatEvery, (_) => _tick());
    Future.microtask(_tick);
    return LinkState.reconnecting;
  }

  /// Something proved the link works — a snapshot arrived, a heartbeat came
  /// back, a GATT connection opened.
  void markAlive() {
    _lastGood = DateTime.now();
    final kind = ref.read(currentTransportProvider);
    final next = kind == TransportKind.ble
        ? LinkState.connectedBle
        : LinkState.connectedWifi;
    if (state != next) state = next;
  }

  Future<void> _tick() async {
    final kind = ref.read(currentTransportProvider);
    if (kind == TransportKind.ble) {
      // Both, deliberately. The session status is a state machine and can
      // go stale — it did: a master powered off for five minutes still read
      // as connected, because nothing moved the status off it. isConnected
      // comes from the GATT link itself, so a drop the session hasn't
      // processed yet still degrades here.
      final session = ref.read(bleSessionProvider).status;
      final live = ref.read(bleSessionProvider.notifier).client?.isConnected;
      if (session == BleSessionStatus.connected && live == true) {
        markAlive();
        return;
      }
      // scanning/connecting during a roam is not a loss yet.
      _degrade();
      return;
    }

    // Recently-proven links are not re-probed. Relay commands and state
    // pushes both call markAlive, so while the user is actively driving
    // switches the heartbeat adds nothing — except load on a one-request-
    // at-a-time server that is already busy with the commands. The probe
    // is for quiet links only.
    final last = _lastGood;
    if (last != null &&
        DateTime.now().difference(last) < heartbeatEvery + grace) {
      return;
    }

    // Wi-Fi: a genuine round trip. /api/info is the lightest
    // authenticated read the master offers. The receive window is
    // generous on purpose: aborting at two seconds threw away work the
    // master was mid-way through — it still wrote the response, into a
    // socket nobody was reading — and then counted the waste as a miss.
    if (_probing) return;
    _probing = true;
    try {
      final dio = ref.read(dioProvider);
      await dio.get<dynamic>(
        Api.info,
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 2),
          // The Dio interceptor warns on every transport failure; the
          // heartbeat reports its own misses in one compact line.
          extra: const {'quietLog': true},
        ),
      );
      if (_misses > 0) log.i('heartbeat back after $_misses missed');
      _misses = 0;
      markAlive();
    } on Object catch (e) {
      _misses++;
      final why = e is DioException ? e.type.name : e.runtimeType.toString();
      // First miss of a streak is the news; the rest are a counter, not
      // three stanzas of the same exception every three seconds.
      if (_misses == 1) {
        log.w('heartbeat missed ($why)');
      } else {
        log.d('heartbeat miss #$_misses ($why)');
      }
      _degrade();
      await _rebindWifi();
      await _rejoinHomeWifi();
    } finally {
      _probing = false;
    }
  }

  /// After this many consecutive misses (~15-20 s down), re-binding is
  /// presumed insufficient: the phone has probably left the network.
  static const rejoinAfterMisses = 3;

  /// At most one rejoin attempt per this window.
  static const rejoinEvery = Duration(seconds: 30);

  DateTime? _lastRejoin;

  /// Actively rejoin the home network instead of waiting for Android.
  ///
  /// The user's report: auto-connect ON, yet coming back into range
  /// sometimes reconnected and sometimes didn't. Android deprioritises
  /// saved networks with no internet — with mobile data available its
  /// scorer often refuses the master's AP no matter what the toggle
  /// says; the times it *did* reconnect were this app's own network
  /// request still being alive. So the app owns the rejoin: SSID from
  /// the registry, password from the vault (stored at login — it is the
  /// Wi-Fi password, API §1), silently re-approved by the OS after the
  /// first join. Throttled, and only after re-binding alone has failed
  /// a few times running.
  Future<void> _rejoinHomeWifi() async {
    if (_misses < rejoinAfterMisses) return;
    final last = _lastRejoin;
    if (last != null && DateTime.now().difference(last) < rejoinEvery) return;
    try {
      final masters =
          await ref.read(masterRegistryProvider.future).timeout(grace);
      final ssid = masters.isEmpty ? null : masters.first.ssid;
      if (ssid == null || ssid.isEmpty) return;
      // Any member's stored password drives the mesh — same fallback the
      // saved-session token uses.
      String? password;
      final store = ref.read(secureStoreProvider);
      for (final m in masters) {
        password = await store.readPassword(m.uid);
        if (password != null) break;
      }
      if (password == null) return; // nothing stored yet (pre-1.1 login)
      _lastRejoin = DateTime.now();
      log.i('link down ${_misses}x — rejoining "$ssid"');
      await ref.read(wifiServiceProvider).join(ssid, password);
    } on Object catch (e) {
      log.d('auto-rejoin skipped: $e');
    }
  }

  /// A connect timeout on a phone that is sitting on the master's Wi-Fi
  /// almost always means Android is routing this process out through
  /// mobile data: the AP has no internet, and the one-shot bind at
  /// reconcile time ran before the Wi-Fi association finished (or the
  /// binding was cleared on a blip). Nothing retried it, so every request
  /// timed out forever on a phone standing next to the master. Re-pin on
  /// every miss; the moment the Wi-Fi is actually there, the next
  /// heartbeat comes back and the link heals itself.
  Future<void> _rebindWifi() async {
    try {
      final ok = await ref.read(wifiServiceProvider).bindToWifi();
      if (ok && _misses == 1) log.i('re-pinned app traffic to Wi-Fi');
    } on Object catch (e) {
      log.d('wifi rebind failed: $e');
    }
  }

  void _degrade() {
    final last = _lastGood;
    if (last == null) {
      // Never been up. Don't claim "out of range" during a cold start.
      if (state != LinkState.reconnecting) state = LinkState.reconnecting;
      return;
    }
    final down = DateTime.now().difference(last);
    if (down < grace) return; // handoff, not a loss
    final next =
        down > outOfRangeAfter ? LinkState.outOfRange : LinkState.reconnecting;
    if (state != next) state = next;
  }
}
