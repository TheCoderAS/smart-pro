import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/transport/access_reset.dart';
import 'package:unisync/core/transport/control_transport.dart';
import 'package:unisync/core/transport/transport_coordinator.dart';
import 'package:unisync/core/transport/transport_manager.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  // v5.1 Epic 5: "A user who has never logged in cannot enter Bluetooth
  // mode; the mode toggle explains why rather than failing silently."
  // The gate must run BEFORE anything changes.
  test('choosing Bluetooth with no session is refused, nothing changes',
      () async {
    final c = makeContainer();
    expect(c.read(tokenProvider), isNull);

    final result = await c
        .read(transportCoordinatorProvider)
        .choose(TransportPreference.bluetooth);

    expect(result, TransportChoice.needsWifiLogin);
    // Preference not persisted and transport not flipped — no
    // half-switched state.
    expect(c.read(transportPreferenceProvider), TransportPreference.auto);
    expect(c.read(currentTransportProvider), TransportKind.wifi);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TransportPreferenceNotifier.key), isNull);
  });

  test('canUseBle reports needsWifiLogin without a token', () async {
    final c = makeContainer();
    expect(
      await c.read(transportCoordinatorProvider).canUseBle(),
      TransportChoice.needsWifiLogin,
    );
  });

  test('choosing Wi-Fi is never gated', () async {
    final c = makeContainer();
    final result = await c
        .read(transportCoordinatorProvider)
        .choose(TransportPreference.wifi);

    expect(result, TransportChoice.ok);
    expect(c.read(transportPreferenceProvider), TransportPreference.wifi);
    expect(c.read(currentTransportProvider), TransportKind.wifi);
  });

  group('accessReset', () {
    test('starts clear, flags, and clears again', () {
      final c = makeContainer();
      expect(c.read(accessResetProvider), isFalse);

      c.read(accessResetProvider.notifier).flag();
      expect(c.read(accessResetProvider), isTrue);

      c.read(accessResetProvider.notifier).clear();
      expect(c.read(accessResetProvider), isFalse);
    });
  });
}
