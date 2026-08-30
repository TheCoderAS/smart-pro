import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/mesh/application/mesh_join_mode.dart';
import '../api/dio_client.dart';
import '../api/endpoints.dart';
import '../logging/log.dart';
import '../transport/ble_session.dart';
import '../transport/control_transport.dart';
import '../transport/transport_manager.dart';
import 'state_dto.dart';

/// Connection status surfaced to the UI (the "reconnecting…" chip on
/// the dashboard header).
enum SocketStatus { connecting, connected, disconnected }

/// Creates a channel for a URI — injectable so tests can hand back a
/// fake without any network.
typedef ChannelFactory = WebSocketChannel Function(Uri uri);

final channelFactoryProvider = Provider<ChannelFactory>(
  (ref) => WebSocketChannel.connect,
);

/// Latest full snapshot from the master. Every emission is a complete
/// replacement (API §4) — consumers select slices, never merge.
final stateSocketProvider =
    StreamNotifierProvider<StateSocketNotifier, StateSnapshot>(
  StateSocketNotifier.new,
);

/// Live connection status, kept separate from the snapshot stream so
/// the dashboard can keep rendering the last snapshot while showing a
/// reconnect indicator.
final socketStatusProvider =
    NotifierProvider<SocketStatusNotifier, SocketStatus>(
  SocketStatusNotifier.new,
);

class SocketStatusNotifier extends Notifier<SocketStatus> {
  @override
  SocketStatus build() => SocketStatus.disconnected;

  void set(SocketStatus status) => state = status;
}

/// When the last Wi-Fi snapshot arrived. The command path reads this to
/// detect a socket that *looks* connected but delivers nothing — the
/// half-open leftover of a background suspension — and forces a
/// reconnect (see WifiControlTransport).
final lastWsSnapshotAtProvider =
    NotifierProvider<LastWsSnapshotAtNotifier, DateTime?>(
  LastWsSnapshotAtNotifier.new,
);

class LastWsSnapshotAtNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void mark() => state = DateTime.now();
}

class StateSocketNotifier extends StreamNotifier<StateSnapshot> {
  static const _initialBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 10);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Duration _backoff = _initialBackoff;
  StreamController<StateSnapshot>? _out;

  @override
  Stream<StateSnapshot> build() {
    final token = ref.watch(tokenProvider);
    // Only run the Wi-Fi socket when Wi-Fi is the active transport —
    // switching to Bluetooth disconnects it (and back reconnects), so
    // the two transports never run at once (item: auto-switch on login).
    final onWifi = ref.watch(currentTransportProvider) == TransportKind.wifi;
    // And judged by reality, not only the flag: a startup race can leave
    // the flag on Wi-Fi while a BLE session is live. Reconnecting this
    // socket then hammers TCP at the master's single radio and starves
    // the BLE writes the user is waiting on. Any live BLE session means
    // no Wi-Fi socket, full stop.
    final bleLive = ref.watch(bleSessionProvider
        .select((s) => s.status != BleSessionStatus.idle));
    // Parked on another master's network to hand it a mesh invite. The
    // device answering there has never issued our token and refuses the
    // socket — the new master's log filled with "Client #0 rejected, no
    // session" while the app retried, spending its radio during the one
    // flow that needs it.
    final joiningMesh = ref.watch(meshJoinModeProvider);

    // Tear down any previous connection when the token/transport changes
    // or the provider is disposed.
    ref.onDispose(_teardown);

    // Closed in _teardown via _out — the lint can't see through the
    // field assignment.
    // ignore: close_sinks
    final out = StreamController<StateSnapshot>.broadcast();
    _out = out;

    // Deferred: writing other providers (socketStatusProvider) during
    // build() is forbidden in Riverpod 3, so connection starts one
    // microtask later.
    Future.microtask(() {
      if (_out != out) return; // rebuilt/disposed meanwhile
      if (token == null || !onWifi || bleLive || joiningMesh) {
        // Not authenticated, or Bluetooth is the active transport — no
        // Wi-Fi socket until a token appears and Wi-Fi is selected.
        _status(SocketStatus.disconnected);
      } else {
        _connect(token);
      }
    });
    return out.stream;
  }

  void _status(SocketStatus s) {
    ref.read(socketStatusProvider.notifier).set(s);
  }

  void _connect(String token) {
    _status(SocketStatus.connecting);
    final uri = Uri.parse('${Api.wsUrl}?${Api.tokenQueryKey}=$token');
    log.d('ws connecting');

    try {
      _channel = ref.read(channelFactoryProvider)(uri);
    } on Exception catch (e) {
      log.w('ws connect threw: $e');
      _scheduleReconnect(token);
      return;
    }

    _sub = _channel!.stream.listen(
      (dynamic message) {
        // First message doubles as the connected signal — the master
        // pushes a full document immediately on connect (API §4).
        _status(SocketStatus.connected);
        _backoff = _initialBackoff;
        try {
          final map = jsonDecode(message as String) as Map<String, dynamic>;
          _out?.add(StateSnapshot.fromJson(map));
          ref.read(lastWsSnapshotAtProvider.notifier).mark();
        } on FormatException catch (e) {
          log.w('ws message not valid JSON: $e');
        }
      },
      onError: (Object e) {
        log.w('ws error: $e');
        _scheduleReconnect(token);
      },
      onDone: () {
        // Dropped — a roam between masters does this routinely (API §3).
        log.d('ws closed');
        _scheduleReconnect(token);
      },
      cancelOnError: true,
    );
  }

  void _scheduleReconnect(String token) {
    _status(SocketStatus.disconnected);
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _reconnectTimer?.cancel();
    log.d('ws reconnect in $_backoff');
    _reconnectTimer = Timer(_backoff, () {
      final currentToken = ref.read(tokenProvider);
      if (currentToken == null) return; // signed out meanwhile
      _connect(currentToken);
    });
    final doubled = _backoff * 2;
    _backoff = doubled > _maxBackoff ? _maxBackoff : doubled;
  }

  void _teardown() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _out?.close();
    _channel = null;
    _sub = null;
    _out = null;
  }
}
