import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log.dart';

final radiosProvider = Provider<Radios>((ref) => Radios());

/// Radio (Wi-Fi / Bluetooth) state and the system prompts to turn them
/// on. Android-only in practice — iOS offers neither a read nor a prompt
/// worth having — and every call degrades to a safe default off-platform,
/// so callers don't need their own guards.
///
/// Shares the `in.unisync.unisync/wifi` channel (MainActivity.kt).
class Radios {
  static const _channel = MethodChannel('in.unisync.unisync/wifi');

  /// Defaults to true on failure: an unknown radio state must not
  /// trigger a "turn it on" prompt.
  Future<bool> isBluetoothOn() => _read('isBluetoothOn');

  Future<bool> isWifiOn() => _read('isWifiOn');

  /// The system "turn on Bluetooth?" dialog. Fire-and-forget — Android
  /// gives no awaitable verdict without a result API, and the caller
  /// re-checks state on the next resume anyway.
  Future<void> requestEnableBluetooth() => _fire('requestEnableBluetooth');

  /// The Wi-Fi settings panel (API 29+); older Android enables Wi-Fi
  /// directly.
  Future<void> requestEnableWifi() => _fire('requestEnableWifi');

  Future<bool> _read(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? true;
    } on PlatformException catch (e) {
      log.w('$method failed: ${e.code}');
      return true;
    } on MissingPluginException {
      return true; // not Android (or headless) — nothing to prompt for
    }
  }

  Future<void> _fire(String method) async {
    try {
      await _channel.invokeMethod<bool>(method);
    } on PlatformException catch (e) {
      log.w('$method failed: ${e.code}');
    } on MissingPluginException {
      // not Android — no prompt exists
    }
  }
}
