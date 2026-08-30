import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/transport/access_reset.dart';
import 'package:unisync/core/ws/state_socket.dart';
import 'package:unisync/features/mesh/application/mesh_join_mode.dart';

/// While the app is parked on ANOTHER master's network to hand it a mesh
/// invite, the machinery that guards the home has to stand down — every
/// alarm it would raise is a lie for those two minutes.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer make() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('off by default — a standalone home never enters join mode', () {
    final c = make();
    expect(c.read(meshJoinModeProvider), isFalse);
  });

  // The false alarm this exists to prevent: the new switch has never
  // issued us a token, so it 401s everything. Two of those used to mean
  // "your password was changed" and threw the access-reset screen over a
  // perfectly healthy join.
  test('401s from a foreign master cannot trip the access-reset screen', () {
    final c = make();
    c.read(meshJoinModeProvider.notifier).enter();

    c.read(accessResetProvider.notifier).strike();
    c.read(accessResetProvider.notifier).strike();
    c.read(accessResetProvider.notifier).strike();

    expect(c.read(accessResetProvider), isFalse);
  });

  test('once the flow is over, a real rejection still counts', () {
    final c = make();
    final reset = c.read(accessResetProvider.notifier);
    c.read(meshJoinModeProvider.notifier).enter();
    reset.strike();
    c.read(meshJoinModeProvider.notifier).leave();

    // Back home: the ordinary two-strike rule applies again, and the
    // strike swallowed during the flow left nothing armed behind it.
    reset.strike();
    expect(c.read(accessResetProvider), isFalse,
        reason: 'the first strike after the flow only arms');
    reset.strike();
    expect(c.read(accessResetProvider), isTrue);
  });

  // The new master rejects a socket opened with the home's token and
  // says so on its own console, once per retry: "Client #0 rejected, no
  // session". Six of those turned up in a real bench log during a join.
  test('no socket is opened at a master that never issued our token',
      () async {
    final c = ProviderContainer(overrides: [
      channelFactoryProvider.overrideWithValue((Uri _) {
        fail('the socket must not connect while parked on another master');
      }),
    ]);
    addTearDown(c.dispose);

    c.read(meshJoinModeProvider.notifier).enter();
    c.read(tokenProvider.notifier).set('home-token');
    c.listen(stateSocketProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);

    expect(c.read(socketStatusProvider), SocketStatus.disconnected);
  });
}
