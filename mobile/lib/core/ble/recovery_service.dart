import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../crypto/recovery_hmac.dart';
import '../logging/log.dart';
import '../permissions/scan_permissions.dart';

/// Thrown when the OS denies the Bluetooth permissions a scan needs, so
/// the UI can tell the user to grant them rather than showing a raw
/// plugin error.
class BlePermissionDenied implements Exception {
  const BlePermissionDenied();
}

final reactiveBleProvider = Provider<FlutterReactiveBle>(
  (ref) => FlutterReactiveBle(),
);

final recoveryServiceProvider = Provider<RecoveryService>(
  (ref) => RecoveryService(ref.watch(reactiveBleProvider)),
);

/// A master advertising its recovery service, found during scan.
class RecoveryDevice {
  const RecoveryDevice({required this.name, required this.id});

  /// Advertised name, `U{UID}` — the model number on the device.
  final String name;

  /// Platform device identifier.
  final String id;
}

/// BLE password recovery (API §8). Runs while LOGGED OUT — the whole
/// point is that the user cannot join the Wi-Fi.
///
/// Flow: scan for `U…` names → connect → read challenge (8 bytes,
/// fresh per connection) → write HMAC-SHA256(key, challenge)[0..8] →
/// read/notify the result = the password as ASCII.
///
/// A wrong key produces NO response at all — silence IS the failure
/// signal, hence the result timeout. Five failures lock the service
/// for 15 minutes (surfaced in UI wording; not detectable here).
class RecoveryService {
  RecoveryService(this._ble);

  final FlutterReactiveBle _ble;

  static const scanWindow = Duration(seconds: 12);
  static const resultTimeout = Duration(seconds: 15);
  static const connectionTimeout = Duration(seconds: 10);

  Uuid get _service => Uuid.parse(RecoveryBle.service);

  /// Scans for advertising Unisync masters for [scanWindow].
  ///
  /// Requests the runtime BLE permissions first — Android 12+ needs
  /// BLUETOOTH_SCAN granted at runtime or the scan fails with a
  /// location-permission error. Throws [BlePermissionDenied] when the
  /// user declines.
  Future<List<RecoveryDevice>> scan() async {
    if (!await ensureBlePermissions()) {
      throw const BlePermissionDenied();
    }
    final found = <String, RecoveryDevice>{};
    final done = Completer<void>();
    late final StreamSubscription<DiscoveredDevice> sub;
    sub = _ble.scanForDevices(
      withServices: [_service],
      scanMode: ScanMode.lowLatency,
    ).listen(
      (device) {
        final name = device.name;
        if (name.startsWith('U') && name.length >= 5) {
          found[device.id] = RecoveryDevice(name: name, id: device.id);
        }
      },
      onError: (Object e) {
        log.w('ble scan error: $e');
        if (!done.isCompleted) done.completeError(e);
      },
    );
    try {
      await done.future.timeout(scanWindow, onTimeout: () {});
    } finally {
      await sub.cancel();
    }
    return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Runs the challenge-response against [target] with the user's
  /// recovery key. Returns the new password.
  ///
  /// Throws [FormatException] for a malformed key,
  /// [TimeoutException] for silence (wrong key or lockout).
  Future<String> recover(RecoveryDevice target, String recoveryKey) async {
    // Validate before any radio traffic.
    final response = <int>[];

    final connection = _ble
        .connectToDevice(
          id: target.id,
          connectionTimeout: connectionTimeout,
        )
        .listen(null);
    try {
      // Wait for the connected state via a fresh subscription that we
      // can await deterministically.
      await _ble.connectedDeviceStream
          .firstWhere(
            (u) =>
                u.deviceId == target.id &&
                u.connectionState == DeviceConnectionState.connected,
          )
          .timeout(connectionTimeout);

      QualifiedCharacteristic char(String uuid) => QualifiedCharacteristic(
            serviceId: _service,
            characteristicId: Uuid.parse(uuid),
            deviceId: target.id,
          );

      // Step 2: fresh 8-byte challenge for this connection.
      final challenge =
          await _ble.readCharacteristic(char(RecoveryBle.challengeChar));
      log.d('recovery challenge: ${challenge.length} bytes');

      // Steps 3-4: derive the truncated HMAC.
      response.addAll(recoveryResponse(recoveryKey, challenge));

      // Subscribe BEFORE writing so a fast notify isn't missed.
      final resultChar = char(RecoveryBle.resultChar);
      final resultFuture = _ble
          .subscribeToCharacteristic(resultChar)
          .where((v) => v.isNotEmpty)
          .first
          .timeout(resultTimeout);

      await _ble.writeCharacteristicWithResponse(
        char(RecoveryBle.responseChar),
        value: response,
      );

      // Step 5: the new password, ASCII. Silence = wrong key.
      List<int> raw;
      try {
        raw = await resultFuture;
      } on TimeoutException {
        // Some stacks drop notifications — one explicit read before
        // giving up.
        raw = await _ble.readCharacteristic(resultChar);
        if (raw.isEmpty) rethrow;
      }
      return ascii.decode(raw, allowInvalid: true).trim();
    } finally {
      await connection.cancel(); // disconnects
    }
  }
}
