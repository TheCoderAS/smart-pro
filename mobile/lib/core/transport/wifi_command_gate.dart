import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log.dart';

/// Flood control for switch commands over Wi-Fi.
///
/// The master's web server handles one request at a time with a
/// connection table of about four. The app imposed no discipline at all:
/// every tap opened its own parallel TCP connection, alongside a
/// heartbeat every three seconds and any WebSocket reconnects. Under a
/// burst of taps the little server collapsed — new connections dropped
/// (connectionTimeout), accepted ones aborted by our own receive timeout
/// mid-processing, and a single switch on Wi-Fi became unusable. The app
/// was DDoSing its own master.
///
/// One command in flight at a time, and taps on the same switch coalesce
/// to the latest desired state — flipping a switch five times while the
/// queue is busy sends one command, the final one, which is all the user
/// meant. Distinct switches keep their order.
final wifiCommandGateProvider = Provider<WifiCommandGate>(
  (ref) => WifiCommandGate(),
);

class WifiCommandGate {
  /// Desired end-state per switch id, latest write wins. Iteration order
  /// is insertion order, so distinct switches fire in the order tapped.
  final LinkedHashMap<String, _Relay> _pending = LinkedHashMap();

  bool _draining = false;

  /// Queues a relay command, coalescing repeated taps on the same switch.
  /// The returned future completes when THIS switch's final state has
  /// been sent (or superseded again).
  Future<void> relay({
    required String id,
    required bool on,
    int? ch,
    String? masterUid,
    required Future<void> Function(
            {required String id,
            required bool on,
            int? ch,
            String? masterUid})
        send,
  }) {
    final superseded = _pending[id];
    if (superseded != null) {
      // The earlier tap no longer matters; its awaiter gets the outcome
      // of the state that replaced it.
      log.d('wifi relay $id coalesced (${superseded.on} -> $on)');
    }
    final entry = _Relay(id: id, on: on, ch: ch, masterUid: masterUid,
        completer: superseded?.completer ?? Completer<void>());
    _pending[id] = entry;
    _drain(send);
    return entry.completer.future;
  }

  /// Everything-off preempts the queue: whatever was pending is moot.
  Future<void> killAll(Future<void> Function() send) {
    for (final e in _pending.values) {
      if (!e.completer.isCompleted) e.completer.complete();
    }
    _pending.clear();
    return send();
  }

  Future<void> _drain(
    Future<void> Function(
            {required String id,
            required bool on,
            int? ch,
            String? masterUid})
        send,
  ) async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final entry = _pending.remove(_pending.keys.first)!;
        try {
          await send(
            id: entry.id,
            on: entry.on,
            ch: entry.ch,
            masterUid: entry.masterUid,
          );
          if (!entry.completer.isCompleted) entry.completer.complete();
        } on Object catch (e, st) {
          if (!entry.completer.isCompleted) {
            entry.completer.completeError(e, st);
          }
        }
      }
    } finally {
      _draining = false;
    }
  }
}

class _Relay {
  _Relay({
    required this.id,
    required this.on,
    required this.ch,
    required this.masterUid,
    required this.completer,
  });

  final String id;
  final bool on;
  final int? ch;
  final String? masterUid;
  final Completer<void> completer;
}
