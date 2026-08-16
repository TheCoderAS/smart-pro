import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/core/storage/secure_store.dart';
import 'package:unisync/features/auth/application/session.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';
import 'package:unisync/features/auth/domain/models.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSecureStore extends Mock implements SecureStore {}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // The ghost screen: a session carried over Bluetooth has a stand-in
  // identity (fw '—') that no HTTP probe ever confirmed. Signing out of
  // one used to build NeedsLogin from that stand-in — a sign-in form
  // labelled with a master that might be powered off, talking to whoever
  // answers 192.168.4.1, with no way out.
  test('signing out of a Bluetooth session re-probes instead of haunting',
      () async {
    SharedPreferences.setMockInitialValues({
      'firstrun.welcome': true,
      'masters': jsonEncode([
        {'uid': '2CEC97F0', 'name': 'Aalok', 'meshId': 0xC62F},
      ]),
      'masters.lastUsed': '2CEC97F0',
    });
    final repo = MockAuthRepository();
    final store = MockSecureStore();
    when(() => repo.info()).thenThrow(const Unreachable());
    when(() => repo.logout()).thenAnswer((_) async {});
    when(() => store.readToken(any())).thenAnswer((_) async => 'tok');
    when(() => store.deleteToken(any())).thenAnswer((_) async {});

    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      secureStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);

    // Master unreachable over Wi-Fi → the explicit BLE path carries the
    // session with the placeholder identity.
    await c.read(sessionProvider.future);
    expect(
      await c.read(sessionProvider.notifier).connectOverBle(),
      isTrue,
    );
    final authed = c.read(sessionProvider).value;
    expect(authed, isA<Authenticated>());
    expect((authed as Authenticated).info.fw, SessionNotifier.placeholderFw);

    // Token gone after sign-out, master still unreachable.
    when(() => store.readToken(any())).thenAnswer((_) async => null);
    await c.read(sessionProvider.notifier).signOut();

    final after = c.read(sessionProvider).value;
    // Anything but a login form pinned to the placeholder: here, with the
    // master off and the token discarded, the honest answer is
    // unreachable — a screen that carries the switcher and add-a-switch.
    expect(after, isA<MasterUnreachable>());
  });

  test('a real Wi-Fi session still signs out to its login form', () async {
    SharedPreferences.setMockInitialValues({'firstrun.welcome': true});
    final repo = MockAuthRepository();
    final store = MockSecureStore();
    const info = DeviceInfo(
        uptime: 5, freeHeap: 1000, uid: 'C5F77720', fw: '11.29.2', auth: true);
    when(() => repo.info()).thenAnswer((_) async => info);
    when(() => repo.logout()).thenAnswer((_) async {});
    when(() => repo.validateToken()).thenAnswer((_) async => true);
    when(() => store.readToken(any())).thenAnswer((_) async => 'tok');
    when(() => store.deleteToken(any())).thenAnswer((_) async {});

    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      secureStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);

    expect(await c.read(sessionProvider.future), isA<Authenticated>());
    await c.read(sessionProvider.notifier).signOut();

    final after = c.read(sessionProvider).value;
    expect(after, isA<NeedsLogin>());
    // And the form is labelled with the HTTP-confirmed identity.
    expect((after as NeedsLogin).info.fw, '11.29.2');
  });
}
