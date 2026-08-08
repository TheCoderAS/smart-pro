import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/ws/state_dto.dart';
import 'package:unisync/core/ws/state_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Fake channel driven by two controllers so tests can inject
/// messages and simulate drops.
class FakeChannel implements WebSocketChannel {
  // Closed by the notifier's teardown path (sink.close) or test end.
  // ignore: close_sinks
  final incoming = StreamController<dynamic>();
  // ignore: close_sinks
  final outgoing = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(outgoing, incoming);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._out, this._in);
  final StreamController<dynamic> _out;
  final StreamController<dynamic> _in;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _out.close();
    if (!_in.isClosed) await _in.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('parses full snapshots and treats each as a replacement', () async {
    final channels = <FakeChannel>[];
    final container = ProviderContainer(
      overrides: [
        channelFactoryProvider.overrideWithValue((uri) {
          final c = FakeChannel();
          channels.add(c);
          return c;
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(tokenProvider.notifier).set('cafebabe');
    final snapshots = <StateSnapshot>[];
    container.listen(stateSocketProvider, (prev, next) {
      final v = next.value;
      if (v != null) snapshots.add(v);
    });

    await Future<void>.delayed(Duration.zero);
    expect(channels, hasLength(1));

    channels[0].incoming.add(jsonEncode({
      'master_name': 'Living Room',
      'uptime': 100,
      'switches': [
        {'id': 'ext0_1', 'name': 'Fan', 'on': true},
        {'id': 'ext0_2', 'name': 'Light', 'on': false},
      ],
    }));

    await Future<void>.delayed(Duration.zero);
    expect(snapshots, hasLength(1));
    final first = snapshots[0];
    expect(first.masterName, 'Living Room');
    expect(first.switches, hasLength(2));
    expect(first.switches[0].on, isTrue);
    expect(container.read(socketStatusProvider), SocketStatus.connected);

    // Second push replaces everything — fewer switches, new name
    // (as after a silent roam to a different master).
    channels[0].incoming.add(jsonEncode({
      'master_name': 'Bedroom',
      'switches': [
        {'id': 'ext1_1', 'name': 'Lamp', 'on': false},
      ],
    }));

    await Future<void>.delayed(Duration.zero);
    expect(snapshots, hasLength(2));
    final second = snapshots[1];
    expect(second.masterName, 'Bedroom');
    expect(second.switches, hasLength(1));
  });

  test('reconnects after a drop with a fresh channel', () async {
    final channels = <FakeChannel>[];
    final container = ProviderContainer(
      overrides: [
        channelFactoryProvider.overrideWithValue((uri) {
          final c = FakeChannel();
          channels.add(c);
          return c;
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(tokenProvider.notifier).set('cafebabe');
    final snapshots = <StateSnapshot>[];
    container.listen(stateSocketProvider, (prev, next) {
      final v = next.value;
      if (v != null) snapshots.add(v);
    });

    await Future<void>.delayed(Duration.zero);
    expect(channels, hasLength(1));

    channels[0].incoming.add(jsonEncode({'master_name': 'A'}));
    await Future<void>.delayed(Duration.zero);
    expect(snapshots, hasLength(1));
    expect(snapshots[0].masterName, 'A');

    // Simulate the roam drop.
    await channels[0].incoming.close();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(socketStatusProvider), SocketStatus.disconnected);

    // Backoff starts at 1 s.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(channels, hasLength(2));

    channels[1].incoming.add(jsonEncode({'master_name': 'B'}));
    await Future<void>.delayed(Duration.zero);
    expect(snapshots, hasLength(2));
    expect(snapshots[1].masterName, 'B');
    expect(container.read(socketStatusProvider), SocketStatus.connected);
  });

  test('no token → no connection attempts', () async {
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        channelFactoryProvider.overrideWithValue((uri) {
          attempts++;
          return FakeChannel();
        }),
      ],
    );
    addTearDown(container.dispose);

    // Subscribe without a token.
    container.read(stateSocketProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(attempts, 0);
    expect(container.read(socketStatusProvider), SocketStatus.disconnected);
  });

  test('token carried in the query string, port 81', () async {
    Uri? seen;
    final container = ProviderContainer(
      overrides: [
        channelFactoryProvider.overrideWithValue((uri) {
          seen = uri;
          return FakeChannel();
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(tokenProvider.notifier).set('3f2ac81d');
    container.read(stateSocketProvider);
    await Future<void>.delayed(Duration.zero);

    expect(seen, isNotNull);
    expect(seen!.port, 81);
    expect(seen!.queryParameters['t'], '3f2ac81d');
  });
}
