import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart'
    show ScanMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unisync/core/ble/advert.dart';
import 'package:unisync/core/ble/ble_scanner.dart';
import 'package:unisync/core/transport/ble_session.dart';

class MockScanner extends Mock implements BleScanner {}

/// The 30-minute "Reconnecting": every scan and reconnect runs through
/// serialising gates, and a single plugin call that never completed —
/// which Android's BLE stack is known to produce right after a
/// supervision-timeout disconnect — wedged the gate forever. The master,
/// back in range and advertising, never saw one connection attempt.
///
/// These tests drive the gates with a scanner that never returns and
/// assert the cap releases them.
void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(ScanMode.balanced);
  });

  test('a scan that never completes releases the gate for the next one',
      () {
    fakeAsync((async) {
      TestWidgetsFlutterBinding.ensureInitialized();
      final scanner = MockScanner();
      var calls = 0;
      when(() => scanner.collect(
            meshId: any(named: 'meshId'),
            window: any(named: 'window'),
            mode: any(named: 'mode'),
          )).thenAnswer((_) {
        calls++;
        if (calls == 1) return Completer<List<MasterBeacon>>().future; // hang
        return Future.value(const <MasterBeacon>[]);
      });
      final c = ProviderContainer(overrides: [
        bleScannerProvider.overrideWithValue(scanner),
      ]);
      addTearDown(c.dispose);
      final session = c.read(bleSessionProvider.notifier);

      bool? first;
      bool? second;
      session.canSee(uid: 'AAAA1111').then((v) => first = v);
      session.canSee(uid: 'BBBB2222').then((v) => second = v);

      // Within the cap: the wedged first probe blocks the second.
      async.elapse(const Duration(seconds: 5));
      expect(second, isNull);

      // Past the cap: the first is abandoned (false, not an error), the
      // gate advances, and the second completes on its own merits.
      async.elapse(const Duration(seconds: 30));
      expect(first, isFalse);
      expect(second, isFalse);
      expect(calls, 2, reason: 'the second scan actually ran');
    });
  });

  test('the link-operation cap is generous enough for a real connect', () {
    // connect timeout (12s) + MTU + nonce read + identity check all have
    // to fit, or healthy attempts get abandoned mid-flight.
    expect(BleSessionController.linkOpCap,
        greaterThanOrEqualTo(const Duration(seconds: 20)));
  });
}
