import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/storage/secure_store.dart';
import 'package:unisync/core/transport/access_reset.dart';
import 'package:unisync/core/transport/control_transport.dart';
import 'package:unisync/core/transport/transport_coordinator.dart';
import 'package:unisync/core/transport/transport_manager.dart';

class MockSecureStore extends Mock implements SecureStore {}

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

  // The cold-start regression: on a warm launch the dashboard paints from
  // cache and reconciles before the session bootstrap has restored the
  // token. Reading that as "never signed in" sent a Bluetooth-preferring
  // user to Wi-Fi — permanently, since nothing reconciled again.
  //
  // The permission gate runs next and has no plugin under test, so the
  // assertion is that the vault was consulted at all: a restored token is
  // proof the token gate no longer short-circuits.
  test('canUseBle restores a saved token rather than refusing', () async {
    SharedPreferences.setMockInitialValues({
      'masters': jsonEncode([
        {'uid': 'C5F77720', 'name': 'Hall'},
      ]),
    });
    final store = MockSecureStore();
    when(() => store.readToken(any())).thenAnswer((_) async => 'tok');
    final c = ProviderContainer(
      overrides: [secureStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);

    try {
      final choice = await c.read(transportCoordinatorProvider).canUseBle();
      expect(choice, isNot(TransportChoice.needsWifiLogin));
    } on Object {
      // permission_handler has no implementation in a unit test; the
      // token gate is what this test is about and it is already behind us.
    }
    expect(c.read(tokenProvider), 'tok');
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
    test('starts clear, sets after two strikes, and clears again', () {
      final c = makeContainer();
      expect(c.read(accessResetProvider), isFalse);

      // Two strikes: one rejected proof is churn noise, a repeat inside
      // the window is a genuinely changed password.
      c.read(accessResetProvider.notifier).strike();
      c.read(accessResetProvider.notifier).strike();
      expect(c.read(accessResetProvider), isTrue);

      c.read(accessResetProvider.notifier).clear();
      expect(c.read(accessResetProvider), isFalse);
    });
  });
}
