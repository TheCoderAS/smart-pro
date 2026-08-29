import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/core/storage/master_registry.dart';
import 'package:unisync/core/storage/secure_store.dart';
import 'package:unisync/core/transport/control_transport.dart';
import 'package:unisync/core/transport/transport_manager.dart';
import 'package:unisync/core/wifi/wifi_service.dart';
import 'package:unisync/features/auth/application/session.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';
import 'package:unisync/features/auth/domain/models.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSecureStore extends Mock implements SecureStore {}

class MockWifiService extends Mock implements WifiService {}

const _info = DeviceInfo(
  uptime: 3812,
  freeHeap: 184320,
  uid: 'C5F77720',
  fw: '11.13.2',
  auth: true,
);

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));

  late MockAuthRepository repo;
  late MockSecureStore store;
  late MockWifiService wifi;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Default: no persisted prefs (no masters, no transport preference)
    // so the BLE cold-start paths stay dormant unless a test seeds them.
    // The welcome screen is marked seen: these tests exercise bootstrap
    // *after* setup, and a fresh install short-circuits to NeedsWelcome
    // before any network call. The welcome path has its own test below.
    SharedPreferences.setMockInitialValues({'firstrun.welcome': true});
    repo = MockAuthRepository();
    store = MockSecureStore();
    wifi = MockWifiService();
    when(() => store.writeToken(any(), any())).thenAnswer((_) async {});
    when(() => store.writePassword(any(), any())).thenAnswer((_) async {});
    when(() => store.deleteToken(any())).thenAnswer((_) async {});
    when(() => store.readToken(any())).thenAnswer((_) async => null);
    when(() => repo.logout()).thenAnswer((_) async {});
    // The nothing-paired fast probe says "someone is there" by default,
    // so bootstrap proceeds to the mocked HTTP flow under test.
    when(() => wifi.masterReachable(timeout: any(named: 'timeout')))
        .thenAnswer((_) async => true);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        secureStoreProvider.overrideWithValue(store),
        wifiServiceProvider.overrideWithValue(wifi),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<SessionState> bootstrap(ProviderContainer c) async {
    return c.read(sessionProvider.future);
  }

  test('unreachable master with a paired home → MasterUnreachable', () async {
    // A home exists, so this is an outage, not setup.
    SharedPreferences.setMockInitialValues({
      'firstrun.welcome': true,
      'masters': '[{"uid":"C5F77720","name":"Hall"}]',
    });
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();

    expect(await bootstrap(c), isA<MasterUnreachable>());
  });

  test('nothing paired + nobody answering → NeedsSetup, decided by the '
      'cheap probe (no HTTP timeout)', () async {
    // The fresh-install dead end: "can't reach your switch" with no way
    // to set one up, reached after sitting out the full HTTP timeout.
    when(() => wifi.masterReachable(timeout: any(named: 'timeout')))
        .thenAnswer((_) async => false);
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();

    expect(await bootstrap(c), isA<NeedsSetup>());
    verifyNever(() => repo.info());
  });

  test('factory-fresh master (auth=false) → NeedsCommissioning', () async {
    when(() => repo.info())
        .thenAnswer((_) async => _info.copyWith(auth: false));
    final c = makeContainer();

    expect(await bootstrap(c), isA<NeedsCommissioning>());
  });

  test('no stored token → NeedsLogin', () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => null);
    final c = makeContainer();

    expect(await bootstrap(c), isA<NeedsLogin>());
  });

  test('stored valid token → Authenticated, token set for X-Auth', () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720'))
        .thenAnswer((_) async => 'cafebabe');
    when(() => repo.validateToken()).thenAnswer((_) async => true);
    final c = makeContainer();

    expect(await bootstrap(c), isA<Authenticated>());
    expect(c.read(tokenProvider), 'cafebabe');
  });

  test('stored stale token → deleted, NeedsLogin', () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720'))
        .thenAnswer((_) async => 'stale000');
    when(() => repo.validateToken()).thenAnswer((_) async => false);
    final c = makeContainer();

    expect(await bootstrap(c), isA<NeedsLogin>());
    expect(c.read(tokenProvider), isNull);
    verify(() => store.deleteToken('C5F77720')).called(1);
  });

  test('login success → Authenticated with mesh flag, token stored',
      () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => null);
    when(() => repo.login('goodpass')).thenAnswer(
      (_) async => const LoginResult(token: '3f2ac81d', mesh: true),
    );
    final c = makeContainer();
    await bootstrap(c);

    await c.read(sessionProvider.notifier).login('goodpass');

    final state = c.read(sessionProvider).value;
    expect(state, isA<Authenticated>());
    expect((state! as Authenticated).mesh, isTrue);
    expect(c.read(tokenProvider), '3f2ac81d');
    verify(() => store.writeToken('C5F77720', '3f2ac81d')).called(1);
    // The device password is the Wi-Fi password (API §1); stored for the
    // change-password rejoin dance.
    verify(() => store.writePassword('C5F77720', 'goodpass')).called(1);
    // Signing in IS adding the switch: recorded immediately, never left
    // to whenever a Wi-Fi status update arrives. The unrecorded window
    // is what let Bluetooth's old adopt shortcut re-add a removed master.
    final registered = await c.read(masterRegistryProvider.future);
    expect(registered.map((m) => m.uid), contains('C5F77720'));
  });

  test('login failure → NeedsLogin carrying the failure', () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => null);
    when(() => repo.login('wrong')).thenThrow(const Unauthorized());
    final c = makeContainer();
    await bootstrap(c);

    await c.read(sessionProvider.notifier).login('wrong');

    final state = c.read(sessionProvider).value;
    expect(state, isA<NeedsLogin>());
    expect((state! as NeedsLogin).failure, isA<Unauthorized>());
  });

  test('password change dance: retries login until AP returns', () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720'))
        .thenAnswer((_) async => 'cafebabe');
    when(() => repo.validateToken()).thenAnswer((_) async => true);
    final c = makeContainer();
    await bootstrap(c);

    // First two logins fail while the AP restarts; third succeeds.
    var calls = 0;
    when(() => repo.login('newpass123')).thenAnswer((_) async {
      calls++;
      if (calls < 3) throw const Unreachable();
      return const LoginResult(token: 'feedf00d', mesh: true);
    });

    await c.read(sessionProvider.notifier).handlePasswordChanged(
          'newpass123',
          delay: const Duration(milliseconds: 1),
        );

    final state = c.read(sessionProvider).value;
    expect(state, isA<Authenticated>());
    expect(c.read(tokenProvider), 'feedf00d');
    expect(calls, 3);
    verify(() => store.deleteToken('C5F77720')).called(1);
    verify(() => store.writeToken('C5F77720', 'feedf00d')).called(1);
  });

  test('password change dance: wrong new password → bootstrap path',
      () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720'))
        .thenAnswer((_) async => 'cafebabe');
    when(() => repo.validateToken()).thenAnswer((_) async => true);
    final c = makeContainer();
    await bootstrap(c);

    when(() => repo.login('badpass123')).thenThrow(const Unauthorized());
    // Bootstrap after the failed dance: token was deleted.
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => null);

    await c.read(sessionProvider.notifier).handlePasswordChanged(
          'badpass123',
          delay: const Duration(milliseconds: 1),
        );

    expect(c.read(sessionProvider).value, isA<NeedsLogin>());
  });

  test('sign out → token cleared, NeedsLogin', () async {
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => store.readToken('C5F77720'))
        .thenAnswer((_) async => 'cafebabe');
    when(() => repo.validateToken()).thenAnswer((_) async => true);
    final c = makeContainer();
    await bootstrap(c);

    await c.read(sessionProvider.notifier).signOut();

    expect(c.read(sessionProvider).value, isA<NeedsLogin>());
    expect(c.read(tokenProvider), isNull);
    verify(() => store.deleteToken('C5F77720')).called(1);
  });

  // ---- Cold-start over Bluetooth (unreachable-screen entry) ----

  void seedPairedMaster({String? preference}) {
    final values = <String, Object>{
      'masters': jsonEncode([
        {'uid': 'C5F77720', 'name': 'Living Room', 'meshId': 4660},
      ]),
    };
    if (preference != null) values['transport.preference'] = preference;
    SharedPreferences.setMockInitialValues(values);
  }

  test('connectOverBle with a saved token → Authenticated over BLE', () async {
    when(() => repo.info()).thenThrow(const Unreachable());
    seedPairedMaster();
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => 'cafebabe');
    final c = makeContainer();
    expect(await bootstrap(c), isA<MasterUnreachable>());

    final ok = await c.read(sessionProvider.notifier).connectOverBle();

    expect(ok, isTrue);
    expect(c.read(sessionProvider).value, isA<Authenticated>());
    expect(c.read(tokenProvider), 'cafebabe');
  });

  test('connectOverBle without a saved token → false, state unchanged',
      () async {
    when(() => repo.info()).thenThrow(const Unreachable());
    seedPairedMaster();
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => null);
    final c = makeContainer();
    expect(await bootstrap(c), isA<MasterUnreachable>());

    final ok = await c.read(sessionProvider.notifier).connectOverBle();

    expect(ok, isFalse);
    expect(c.read(sessionProvider).value, isA<MasterUnreachable>());
  });

  test('unreachable + bluetooth preference + saved token → auto BLE',
      () async {
    when(() => repo.info()).thenThrow(const Unreachable());
    seedPairedMaster(preference: 'bluetooth');
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => 'cafebabe');
    final c = makeContainer();

    expect(await bootstrap(c), isA<Authenticated>());
    expect(c.read(tokenProvider), 'cafebabe');
  });

  // The preference is a preference, not a fallback. Probing the LAN first
  // cost a timeout when the phone was off the master's network — and when
  // it was *on* it, the probe succeeded and the entire bootstrap ran over
  // Wi-Fi despite the user having asked for Bluetooth.
  test('bluetooth preference skips the Wi-Fi probe entirely', () async {
    seedPairedMaster(preference: 'bluetooth');
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => 'cafebabe');
    // Reachable: the old order would have taken this and never looked at
    // the preference at all.
    when(() => repo.info()).thenAnswer((_) async => _info);
    when(() => repo.validateToken()).thenAnswer((_) async => true);
    final c = makeContainer();

    expect(await bootstrap(c), isA<Authenticated>());
    expect(c.read(tokenProvider), 'cafebabe');
    verifyNever(() => repo.info());
    verifyNever(() => repo.validateToken());
  });

  test('bluetooth preference flips the live transport, not just the pref',
      () async {
    seedPairedMaster(preference: 'bluetooth');
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => 'cafebabe');
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();

    expect(await bootstrap(c), isA<Authenticated>());
    // Otherwise the Wi-Fi socket sees a token appear while the transport
    // still reads as its default, and dials a LAN we are not on.
    expect(c.read(currentTransportProvider), TransportKind.ble);
  });

  test('unreachable + bluetooth preference but no token → MasterUnreachable',
      () async {
    when(() => repo.info()).thenThrow(const Unreachable());
    seedPairedMaster(preference: 'bluetooth');
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => null);
    final c = makeContainer();

    expect(await bootstrap(c), isA<MasterUnreachable>());
  });

  test('fresh install with nothing paired → NeedsWelcome, no probe', () async {
    SharedPreferences.setMockInitialValues({});
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();

    expect(await bootstrap(c), isA<NeedsWelcome>());
    // The point of the screen: a first launch is a setup story, so we
    // never reach the network and never show "can't reach your switch".
    verifyNever(() => repo.info());
  });

  test('welcome seen, nothing paired, nobody answering → NeedsSetup',
      () async {
    // The reported reinstall flow: tap "set up my switch", land on a
    // screen that can actually set one up — never the dead-end
    // unreachable screen.
    SharedPreferences.setMockInitialValues({'firstrun.welcome': true});
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();

    expect(await bootstrap(c), isA<NeedsSetup>());
  });

  test('forgetHome purges the paired home and lands on setup', () async {
    SharedPreferences.setMockInitialValues({
      'firstrun.welcome': true,
      'masters': '[{"uid":"C5F77720","name":"Hall"}]',
    });
    when(() => store.purgeMaster(any())).thenAnswer((_) async {});
    when(() => wifi.masterReachable(timeout: any(named: 'timeout')))
        .thenAnswer((_) async => false);
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();
    expect(await bootstrap(c), isA<MasterUnreachable>());

    await c.read(sessionProvider.notifier).forgetHome();

    expect(c.read(sessionProvider).value, isA<NeedsSetup>());
    expect(await c.read(masterRegistryProvider.future), isEmpty);
    expect(c.read(tokenProvider), isNull);
    verify(() => store.purgeMaster('C5F77720')).called(1);
  });

  test('a stranger answering is a wrong network, not a login form',
      () async {
    // One home per app: the phone joined some other Unisync's network --
    // a neighbour's, or a fresh board. Showing a sign-in form for it is
    // the mix-up the story rules out.
    SharedPreferences.setMockInitialValues({
      'firstrun.welcome': true,
      'masters': '[{"uid":"AAAA1111","name":"Hall","ssid":"Unisync-AAAA"}]',
    });
    when(() => repo.info())
        .thenAnswer((_) async => _info.copyWith(uid: 'FFFF9999'));
    final c = makeContainer();

    final state = await bootstrap(c);
    expect(state, isA<WrongNetwork>());
    expect((state as WrongNetwork).wanted.uid, 'AAAA1111');
  });

  test('one master set up means whoever answers is the one', () async {
    SharedPreferences.setMockInitialValues({
      'firstrun.welcome': true,
      'masters': '[{"uid":"AAAA1111","name":"Hall"}]',
      'masters.lastUsed': 'BBBB2222',
    });
    when(() => repo.info())
        .thenAnswer((_) async => _info.copyWith(uid: 'AAAA1111'));
    final c = makeContainer();

    expect(await bootstrap(c), isNot(isA<WrongNetwork>()));
  });

  test('meshed masters are one home, so any member answering is right',
      () async {
    // The mesh is the switcher entry; which physical master answers is
    // not something the user chose or should be told about.
    SharedPreferences.setMockInitialValues({
      'firstrun.welcome': true,
      'masters': '[{"uid":"AAAA1111","name":"Hall","meshId":7},'
          '{"uid":"BBBB2222","name":"Garage","meshId":7}]',
      'masters.lastUsed': 'BBBB2222',
    });
    when(() => repo.info())
        .thenAnswer((_) async => _info.copyWith(uid: 'AAAA1111'));
    final c = makeContainer();

    expect(await bootstrap(c), isNot(isA<WrongNetwork>()));
  });
}
