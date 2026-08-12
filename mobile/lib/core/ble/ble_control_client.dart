import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../logging/log.dart';
import '../ws/state_dto.dart';
import 'ble_framing.dart';
import 'ble_proof.dart';
import 'endpoints_ble.dart';

/// A `{"err": ...}` reply from the master (BLE spec §Errors). Note a
/// *malformed/unknown* request gets no reply at all — that surfaces as
/// [BleTimeout], not this.
class BleCommandError implements Exception {
  const BleCommandError(this.message);
  final String message;
  @override
  String toString() => 'BleCommandError($message)';
}

/// No reply within the timeout — the spec's silent-failure signal.
class BleTimeout implements Exception {
  const BleTimeout();
}

/// The master rejected our per-command proof twice, even after a fresh
/// nonce — the token is dead (password changed). The UI must route the
/// user to a Wi-Fi login; there is no login over BLE.
class BleTokenRejected implements Exception {
  const BleTokenRejected();
  @override
  String toString() => 'BleTokenRejected';
}

/// One authenticated BLE session with a single connected master.
///
/// Owns the GATT plumbing: connect, MTU negotiation, framed
/// request/response over `…35`/`…36`, and the state-push stream on
/// `…37`. Requests are serialized (one in flight at a time). Every
/// state push is a full [StateSnapshot], interchangeable with the
/// WebSocket's (BLE spec §State push).
class BleControlClient {
  BleControlClient(this._ble, this.deviceId, this._token, {this.onDisconnected});

  /// Fired when the link drops on its own — the master lost power, went out
  /// of range, or the phone's stack gave up. NOT fired for a teardown we
  /// asked for. Without this the session went on believing it was connected
  /// long after the master was gone.
  final void Function()? onDisconnected;

  final FlutterReactiveBle _ble;
  final String deviceId;

  /// The Wi-Fi-issued token. Never sent over BLE — only used locally to
  /// derive each command's proof.
  final String _token;

  /// 8-byte session nonce from `…38`, re-read on every connection.
  List<int> _nonce = const [];

  /// Per-connection command counter; starts at 1, resets with the nonce.
  int _counter = 0;

  static const _connectTimeout = Duration(seconds: 12);
  static const _requestTimeout = Duration(seconds: 6);

  int _maxPayload = 18; // safe default until MTU negotiated
  StreamSubscription<ConnectionStateUpdate>? _conn;
  StreamSubscription<List<int>>? _respSub;
  StreamSubscription<List<int>>? _stateSub;
  final _respReassembler = ChunkReassembler();
  final _stateReassembler = ChunkReassembler();
  final _stateController = StreamController<StateSnapshot>.broadcast();
  Completer<Map<String, Object?>>? _pending;
  Future<void> _lock = Future.value();
  bool _connected = false;
  bool _disposing = false;

  Stream<StateSnapshot> get stateStream => _stateController.stream;
  bool get isConnected => _connected;

  QualifiedCharacteristic _char(String uuid) => QualifiedCharacteristic(
    serviceId: Uuid.parse(BleControlUuids.service),
    characteristicId: Uuid.parse(uuid),
    deviceId: deviceId,
  );

  /// Connects, negotiates MTU (tolerating refusal), and subscribes to
  /// the response and state-push characteristics.
  Future<void> connect() async {
    final connectedCompleter = Completer<void>();
    _conn = _ble
        .connectToDevice(id: deviceId, connectionTimeout: _connectTimeout)
        .listen(
          (u) {
            if (u.connectionState == DeviceConnectionState.connected) {
              _connected = true;
              if (!connectedCompleter.isCompleted) {
                connectedCompleter.complete();
              }
            } else if (u.connectionState ==
                DeviceConnectionState.disconnected) {
              _connected = false;
              // A drop we did not ask for. Tell the session so the UI can
              // stop claiming the master is there.
              if (!_disposing) onDisconnected?.call();
            }
          },
          onError: (Object e) {
            if (!connectedCompleter.isCompleted) {
              connectedCompleter.completeError(e);
            }
          },
        );
    await connectedCompleter.future.timeout(_connectTimeout);

    // Ask for a big MTU; fall back to the safe default if refused.
    try {
      final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 185);
      _maxPayload = BleFraming.payloadForMtu(mtu);
      log.d('ble mtu=$mtu payload=$_maxPayload');
    } on Exception catch (e) {
      log.w('mtu negotiation failed, using default: $e');
      _maxPayload = BleFraming.payloadForMtu(23);
    }

    _respSub = _ble.subscribeToCharacteristic(
      _char(BleControlUuids.controlResponse),
    ).listen((chunk) {
      final map = _respReassembler.addJson(chunk);
      if (map != null) {
        final p = _pending;
        if (p != null && !p.isCompleted) p.complete(map);
      }
    }, onError: (Object e) => log.w('ble response error: $e'));

    _stateSub = _ble.subscribeToCharacteristic(
      _char(BleControlUuids.statePush),
    ).listen((chunk) {
      final map = _stateReassembler.addJson(chunk);
      if (map != null) {
        try {
          _stateController.add(StateSnapshot.fromJson(map));
        } on Exception catch (e) {
          log.w('bad state push: $e');
        }
      }
    }, onError: (Object e) => log.w('ble state error: $e'));

    await _readNonce();
  }

  /// Reads the session nonce and resets the counter. Done on connect and
  /// again whenever the master rejects a proof — and, because every hop
  /// builds a new client, implicitly after every roam.
  Future<void> _readNonce() async {
    _nonce = await _ble.readCharacteristic(
      _char(BleControlUuids.sessionNonce),
    );
    _counter = 0;
    log.d('ble nonce read (${_nonce.length}B), counter reset');
  }

  BleProof _nextProof() {
    _counter += 1;
    return computeBleProof(
      token: _token,
      sessionNonce: _nonce,
      counter: _counter,
    );
  }

  /// Sends a command and awaits the reassembled reply. Serialized: a
  /// second call waits for the first.
  ///
  /// [build] receives a freshly-derived [BleProof] — the proof is
  /// computed at send time so a retry gets a new counter. On
  /// `invalid proof` the nonce is re-read, the counter reset, and the
  /// command retried once; a second rejection means the token is dead
  /// and throws [BleTokenRejected].
  ///
  /// Throws [BleTimeout] on silence (spec: no reply on a bad request)
  /// and [BleCommandError] on any other `{"err"}`.
  Future<Map<String, Object?>> request(
    Map<String, Object?> Function(BleProof proof) build,
  ) {
    final completer = Completer<Map<String, Object?>>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await _requestWithRetry(build));
      } on Object catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Map<String, Object?>> _requestWithRetry(
    Map<String, Object?> Function(BleProof proof) build,
  ) async {
    try {
      return await _doRequest(build(_nextProof()));
    } on BleCommandError catch (e) {
      if (!_isInvalidProof(e.message)) rethrow;
      log.w('ble proof rejected — re-reading nonce and retrying once');
      await _readNonce();
      try {
        return await _doRequest(build(_nextProof()));
      } on BleCommandError catch (e2) {
        if (_isInvalidProof(e2.message)) throw const BleTokenRejected();
        rethrow;
      }
    }
  }

  static bool _isInvalidProof(String message) =>
      message.toLowerCase().contains('proof');

  Future<Map<String, Object?>> _doRequest(Map<String, Object?> command) async {
    final pending = Completer<Map<String, Object?>>();
    _pending = pending;
    final chunks = BleFraming.encodeJson(command, maxPayloadBytes: _maxPayload);
    for (final chunk in chunks) {
      await _ble.writeCharacteristicWithResponse(
        _char(BleControlUuids.controlRequest),
        value: chunk,
      );
    }
    final Map<String, Object?> reply;
    try {
      reply = await pending.future.timeout(_requestTimeout);
    } on TimeoutException {
      throw const BleTimeout();
    } finally {
      _pending = null;
    }
    final err = reply['err'];
    if (err != null) throw BleCommandError(err.toString());
    return reply;
  }

  Future<void> dispose() async {
    _disposing = true;
    _connected = false;
    await _respSub?.cancel();
    await _stateSub?.cancel();
    await _conn?.cancel(); // cancelling the connection stream disconnects
    await _stateController.close();
  }
}
