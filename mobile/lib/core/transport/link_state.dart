import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../api/endpoints.dart';
import '../logging/log.dart';
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

    // Wi-Fi: a genuine round trip, short-fused. /api/info is the lightest
    // authenticated read the master offers.
    try {
      final dio = ref.read(dioProvider);
      await dio.get<dynamic>(
        Api.info,
        options: Options(
          receiveTimeout: const Duration(seconds: 2),
          sendTimeout: const Duration(seconds: 2),
        ),
      );
      markAlive();
    } on Object catch (e) {
      log.d('heartbeat missed: $e');
      _degrade();
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
