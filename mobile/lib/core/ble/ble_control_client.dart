import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../logging/log.dart';
import '../ws/state_dto.dart';
import 'ble_framing.dart';
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

/// One authenticated BLE session with a single connected master.
///
/// Owns the GATT plumbing: connect, MTU negotiation, framed
/// request/response over `…35`/`…36`, and the state-push stream on
/// `…37`. Requests are serialized (one in flight at a time). Every
/// state push is a full [StateSnapshot], interchangeable with the
/// WebSocket's (BLE spec §State push).
class BleControlClient {
  BleControlClient(this._ble, this.deviceId);

  final FlutterReactiveBle _ble;
  final String deviceId;

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
  }

  /// Sends a command and awaits the reassembled reply. Serialized: a
  /// second call waits for the first. Throws [BleTimeout] on silence
  /// (spec: no reply on a bad request) and [BleCommandError] on
  /// `{"err"}`.
  Future<Map<String, Object?>> request(Map<String, Object?> command) {
    final completer = Completer<Map<String, Object?>>();
    _lock = _lock.then((_) async {
      try {
        final result = await _doRequest(command);
        completer.complete(result);
      } on Object catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

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
    _connected = false;
    await _respSub?.cancel();
    await _stateSub?.cancel();
    await _conn?.cancel(); // cancelling the connection stream disconnects
    await _stateController.close();
  }
}
