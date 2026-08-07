import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/core/storage/secure_store.dart';
import 'package:unisync/features/auth/application/session.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';
import 'package:unisync/features/auth/domain/models.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSecureStore extends Mock implements SecureStore {}

const _info = DeviceInfo(
  uptime: 3812,
  freeHeap: 184320,
  uid: 'C5F77720',
  fw: '11.13.2',
  auth: true,
);

void main() {
  late MockAuthRepository repo;
  late MockSecureStore store;

  setUp(() {
    repo = MockAuthRepository();
    store = MockSecureStore();
    when(() => store.writeToken(any(), any())).thenAnswer((_) async {});
    when(() => store.deleteToken(any())).thenAnswer((_) async {});
    when(() => repo.logout()).thenAnswer((_) async {});
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

  Future<SessionState> bootstrap(ProviderContainer c) async {
    return c.read(sessionProvider.future);
  }

  test('unreachable master → MasterUnreachable', () async {
    when(() => repo.info()).thenThrow(const Unreachable());
    final c = makeContainer();

    expect(await bootstrap(c), isA<MasterUnreachable>());
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
}
