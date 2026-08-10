import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/core/storage/master_registry.dart';
import 'package:unisync/core/storage/secure_store.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';
import 'package:unisync/features/auth/domain/models.dart';
import 'package:unisync/features/settings/application/master_switch.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSecureStore extends Mock implements SecureStore {}

const _target = SavedMaster(
  uid: 'BBBB2222',
  name: 'Garage',
  ssid: 'Unisync-BBBB',
);

void main() {
  late MockAuthRepository repo;
  late MockSecureStore store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    repo = MockAuthRepository();
    store = MockSecureStore();
    // No remembered password ⇒ no Wi-Fi join attempt, which keeps the
    // platform channel out of these tests. The probe is what matters.
    when(() => store.readPassword(any())).thenAnswer((_) async => null);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        secureStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  DeviceInfo info(String uid, {String ssid = ''}) => DeviceInfo(
        uptime: 1,
        freeHeap: 1,
        uid: uid,
        fw: '11.26.0',
        auth: true,
        ssid: ssid,
      );

  test('the target answers with its own uid → arrived', () async {
    when(() => repo.info())
        .thenAnswer((_) async => info('BBBB2222', ssid: 'Unisync-BBBB'));
    final c = makeContainer();

    final outcome = await c.read(masterSwitchProvider).switchTo(_target);

    expect(outcome, isA<SwitchArrived>());
  });

  test('a different uid answers → wrong network, not a login prompt',
      () async {
    // Identity is proven by uid, never by reading the phone's network
    // name — that is what keeps this off the location permission and
    // distinguishes "join the other network" from "out of range".
    when(() => repo.info())
        .thenAnswer((_) async => info('AAAA1111', ssid: 'Unisync-AAAA'));
    final c = makeContainer();

    final outcome = await c.read(masterSwitchProvider).switchTo(_target);

    expect(outcome, isA<SwitchWrongNetwork>());
    expect((outcome as SwitchWrongNetwork).target.uid, 'BBBB2222');
    // Named so the copy can say who did answer.
    expect(outcome.foundName, 'Unisync-AAAA');
  });

  test('nothing answers → unreachable', () async {
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();

    expect(
      await c.read(masterSwitchProvider).switchTo(_target),
      isA<SwitchUnreachable>(),
    );
  });

  test('an authentication error is still a connectivity outcome', () async {
    // The probe endpoint is open, so a failure here is never a verdict on
    // credentials. Showing a login form for it would be the bug the story
    // calls out by name.
    when(() => repo.info()).thenThrow(const LockedOut());
    final c = makeContainer();

    expect(
      await c.read(masterSwitchProvider).switchTo(_target),
      isA<SwitchUnreachable>(),
    );
  });
}
