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

/// The "courting master B forever" loop: with a standalone home, the
/// ranking used to fall through to the strongest STRANGER whenever the
/// added master's beacon was missed in a scan window — connect, get
/// refused, retry, hear the stranger again, repeat, while the added
/// master (quiet because it was busy being the Wi-Fi master) never got
/// a single attempt. A standalone home has exactly one acceptable
/// master; anything else is not even a candidate.
void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(ScanMode.balanced);
  });

  const stranger = MasterBeacon(
    deviceId: 'BB:BB:BB:BB:BB:BB',
    name: 'UBBBB0000',
    rssi: -40, // loud
    advert: MasterAdvert(
      meshId: 0,
      inMesh: false,
      provisioned: true,
      clientConnected: false,
    ),
  );

  test('a standalone home never contacts a non-target beacon', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'masters': '[{"uid":"C5F77720","name":"Hall"}]',
    });
    final scanner = MockScanner();
    when(() => scanner.collect(
          meshId: any(named: 'meshId'),
          window: any(named: 'window'),
          mode: any(named: 'mode'),
        )).thenAnswer((_) async => const [stranger]);
    final c = ProviderContainer(overrides: [
      bleScannerProvider.overrideWithValue(scanner),
    ]);
    addTearDown(c.dispose);

    await c.read(bleSessionProvider.notifier).activate(uid: 'C5F77720');

    final state = c.read(bleSessionProvider);
    // The filter path, not a connect failure: the stranger was heard and
    // deliberately not contacted.
    expect(state.status, BleSessionStatus.failed);
    expect(state.error, contains('not heard'));
    await c.read(bleSessionProvider.notifier).deactivate();
  });
}
