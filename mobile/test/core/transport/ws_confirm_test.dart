import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/transport/transport_manager.dart';
import 'package:unisync/core/transport/wifi_transport.dart';
import 'package:unisync/core/ws/state_socket.dart';
import 'package:unisync/features/switches/data/switch_repository.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockSwitchRepository extends Mock implements SwitchRepository {}

class FakeChannel implements WebSocketChannel {
  // Closed by the notifier's teardown (sink.close) or test end.
  // ignore: close_sinks
  final incoming = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(incoming);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._in);
  final StreamController<dynamic> _in;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_in.isClosed) await _in.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The stale-tile report: the relay physically clicked, but the UI held
/// the old state. The optimistic override was waiting for a snapshot to
/// confirm it — and the socket, half-open after a background suspension
/// (or sitting out a reconnect backoff), was never going to deliver one.
/// A successful command now demands a snapshot within a couple of
/// seconds, or the socket is torn down and reconnected — and a fresh
/// connect gets the full document immediately.
void main() {
  late MockSwitchRepository repo;
  late List<FakeChannel> channels;

  ProviderContainer makeContainer() {
    repo = MockSwitchRepository();
    when(() => repo.setRelay(
          id: any(named: 'id'),
          on: any(named: 'on'),
          ch: any(named: 'ch'),
          masterUid: any(named: 'masterUid'),
        )).thenAnswer((_) async {});
    channels = [];
    final container = ProviderContainer(
      overrides: [
        switchRepositoryProvider.overrideWithValue(repo),
        channelFactoryProvider.overrideWithValue((uri) {
          final c = FakeChannel();
          channels.add(c);
          return c;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(tokenProvider.notifier).set('cafebabe');
    // Keep the socket alive the way the dashboard does.
    container.listen(stateSocketProvider, (_, _) {});
    return container;
  }

  test('a command with no snapshot behind it reconnects the socket',
      () async {
    final c = makeContainer();
    await Future<void>.delayed(Duration.zero);
    expect(channels, hasLength(1));

    // The socket looks fine but will never deliver anything (half-open).
    await c.read(activeControlProvider).setRelay(id: 'ext0_1', on: true);

    await Future<void>.delayed(
      WifiControlTransport.confirmWithin + const Duration(milliseconds: 300),
    );
    expect(channels, hasLength(2),
        reason: 'silence after a successful command must force a reconnect');
  });

  test('a confirming snapshot keeps the socket untouched', () async {
    final c = makeContainer();
    await Future<void>.delayed(Duration.zero);
    expect(channels, hasLength(1));

    await c.read(activeControlProvider).setRelay(id: 'ext0_1', on: true);
    // The master pushes the changed state well inside the window.
    channels[0].incoming.add(jsonEncode({
      'master_name': 'Living Room',
      'switches': [
        {'id': 'ext0_1', 'name': 'Fan', 'channel': 1, 'state': true},
      ],
    }));

    await Future<void>.delayed(
      WifiControlTransport.confirmWithin + const Duration(milliseconds: 300),
    );
    expect(channels, hasLength(1),
        reason: 'a healthy socket must not be churned');
  });
}
