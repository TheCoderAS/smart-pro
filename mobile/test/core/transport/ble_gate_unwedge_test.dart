import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart'
    show ScanMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/ble/advert.dart';
import 'package:unisync/core/ble/ble_scanner.dart';
import 'package:unisync/core/transport/ble_session.dart';

class MockScanner extends Mock implements BleScanner {}

/// The 30-minute "Reconnecting": every scan and reconnect runs through
/// serialising gates, and a single plugin call that never completed —
/// which Android's BLE stack is known to produce right after a
/// supervision-timeout disconnect — wedged the gate forever. The master,
/// back in range and advertising, never saw one connection attempt.
void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(ScanMode.balanced);
  });

  test('a scan that never completes is abandoned and retried', () {
    fakeAsync((async) {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
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
      var activated = false;
      c
          .read(bleSessionProvider.notifier)
          .activate()
          .then((_) => activated = true);

      // Inside the cap: the hung scan still holds things up.
      async.elapse(const Duration(seconds: 5));
      expect(activated, isFalse);

      // Past the cap (window 4s + 10s grace): abandoned, activate
      // completes, and the retry loop's next scan actually ran — the
      // gate was released, not wedged forever.
      async.elapse(const Duration(seconds: 30));
      expect(activated, isTrue);
      expect(calls, greaterThanOrEqualTo(2),
          reason: 'a later scan ran behind the abandoned one');
      c.dispose();
      async.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('the link-operation cap is generous enough for a real connect', () {
    // connect timeout (12s) + MTU + nonce read + identity check all have
    // to fit, or healthy attempts get abandoned mid-flight.
    expect(BleSessionController.linkOpCap,
        greaterThanOrEqualTo(const Duration(seconds: 20)));
  });
}
