import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/storage/saved_session.dart';
import 'package:unisync/core/storage/secure_store.dart';

class MockSecureStore extends Mock implements SecureStore {}

String _masters(List<Map<String, Object?>> entries) => jsonEncode(entries);

void main() {
  late MockSecureStore store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    store = MockSecureStore();
    when(() => store.readToken(any())).thenAnswer((_) async => null);
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [secureStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('nothing paired → no saved session', () async {
    SharedPreferences.setMockInitialValues({});
    final c = makeContainer();
    expect(await c.read(savedSessionProvider).read(), isNull);
    expect(await c.read(savedSessionProvider).ensureToken(), isNull);
  });

  test('paired but never signed in → no saved session', () async {
    SharedPreferences.setMockInitialValues({
      'masters': _masters([
        {'uid': 'C5F77720', 'name': 'Hall'},
      ]),
    });
    final c = makeContainer();
    expect(await c.read(savedSessionProvider).read(), isNull);
  });

  test('reads the token and the mesh id of a paired master', () async {
    SharedPreferences.setMockInitialValues({
      'masters': _masters([
        {'uid': 'C5F77720', 'name': 'Hall', 'meshId': 42},
      ]),
    });
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => 'tok');
    final c = makeContainer();

    final saved = await c.read(savedSessionProvider).read();
    expect(saved?.uid, 'C5F77720');
    expect(saved?.token, 'tok');
    expect(saved?.meshId, 42);
  });

  test('prefers the last-used master', () async {
    SharedPreferences.setMockInitialValues({
      'masters': _masters([
        {'uid': 'AAA', 'name': 'Hall'},
        {'uid': 'BBB', 'name': 'Porch'},
      ]),
      'masters.lastUsed': 'BBB',
    });
    when(() => store.readToken(any())).thenAnswer((_) async => 'tok');
    final c = makeContainer();

    expect((await c.read(savedSessionProvider).read())?.uid, 'BBB');
  });

  // The cold-start regression this exists for: the dashboard can be up and
  // deciding a transport before the session bootstrap has restored the
  // token. "Not loaded yet" must not read as "never signed in".
  test('ensureToken restores an unloaded token into tokenProvider', () async {
    SharedPreferences.setMockInitialValues({
      'masters': _masters([
        {'uid': 'C5F77720', 'name': 'Hall'},
      ]),
    });
    when(() => store.readToken('C5F77720')).thenAnswer((_) async => 'tok');
    final c = makeContainer();
    expect(c.read(tokenProvider), isNull);

    expect(await c.read(savedSessionProvider).ensureToken(), 'tok');
    expect(c.read(tokenProvider), 'tok');
  });

  test('ensureToken keeps a live token and never reads the vault', () async {
    SharedPreferences.setMockInitialValues({});
    final c = makeContainer();
    c.read(tokenProvider.notifier).set('live');

    expect(await c.read(savedSessionProvider).ensureToken(), 'live');
    verifyNever(() => store.readToken(any()));
  });
}
