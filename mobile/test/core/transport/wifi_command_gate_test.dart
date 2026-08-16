import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/transport/wifi_command_gate.dart';

/// The Wi-Fi lag: every tap opened its own parallel connection to a
/// master whose web server handles one request at a time and holds about
/// four connections. A burst of taps collapsed it — the app was DDoSing
/// its own master. The gate bounds offered load: one command in flight,
/// repeat taps on one switch coalesced to the final state.
void main() {
  test('one command in flight at a time', () async {
    final gate = WifiCommandGate();
    var inFlight = 0;
    var maxInFlight = 0;
    Future<void> send(
        {required String id, required bool on, int? ch, String? masterUid}) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      inFlight--;
    }

    await Future.wait([
      gate.relay(id: 'a', on: true, send: send),
      gate.relay(id: 'b', on: true, send: send),
      gate.relay(id: 'c', on: true, send: send),
    ]);
    expect(maxInFlight, 1);
  });

  test('mashing one switch sends the final state, once', () async {
    final gate = WifiCommandGate();
    final sent = <bool>[];
    final blocker = Completer<void>();
    Future<void> send(
        {required String id, required bool on, int? ch, String? masterUid}) async {
      if (sent.isEmpty) await blocker.future; // hold the queue busy
      sent.add(on);
    }

    // First command occupies the wire; five furious taps arrive behind it.
    final first = gate.relay(id: 'x', on: true, send: send);
    final futures = [
      gate.relay(id: 'y', on: false, send: send),
      gate.relay(id: 'y', on: true, send: send),
      gate.relay(id: 'y', on: false, send: send),
      gate.relay(id: 'y', on: true, send: send),
      gate.relay(id: 'y', on: false, send: send),
    ];
    blocker.complete();
    await first;
    await Future.wait(futures);

    // x's command, then exactly one for y — its final state.
    expect(sent, [true, false]);
  });

  test('distinct switches keep their order', () async {
    final gate = WifiCommandGate();
    final order = <String>[];
    Future<void> send(
        {required String id, required bool on, int? ch, String? masterUid}) async {
      order.add(id);
    }

    await Future.wait([
      gate.relay(id: 'hall', on: true, send: send),
      gate.relay(id: 'bed', on: true, send: send),
      gate.relay(id: 'shed', on: true, send: send),
    ]);
    expect(order, ['hall', 'bed', 'shed']);
  });

  test('a failed send fails that switch, not the queue', () async {
    final gate = WifiCommandGate();
    final sent = <String>[];
    Future<void> send(
        {required String id, required bool on, int? ch, String? masterUid}) async {
      if (id == 'bad') throw StateError('unreachable');
      sent.add(id);
    }

    final bad = gate.relay(id: 'bad', on: true, send: send);
    final good = gate.relay(id: 'good', on: true, send: send);
    await expectLater(bad, throwsStateError);
    await good;
    expect(sent, ['good']);
  });

  test('killAll clears whatever was pending', () async {
    final gate = WifiCommandGate();
    final sent = <String>[];
    final blocker = Completer<void>();
    Future<void> send(
        {required String id, required bool on, int? ch, String? masterUid}) async {
      if (sent.isEmpty) await blocker.future;
      sent.add(id);
    }

    final first = gate.relay(id: 'a', on: true, send: send);
    final queued = gate.relay(id: 'b', on: true, send: send);
    final kill = gate.killAll(() async => sent.add('KILL'));
    blocker.complete();
    await first;
    await kill;
    await queued; // completed (moot), not errored
    expect(sent.contains('b'), isFalse,
        reason: 'everything-off preempts queued toggles');
    expect(sent.contains('KILL'), isTrue);
  });
}
