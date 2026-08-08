/// Which physical path control commands and state currently flow over.
enum TransportKind { wifi, ble }

/// The user's transport preference (Settings). `auto` prefers Wi-Fi
/// when the master is reachable on the LAN (faster, unlocks config-only
/// features), else BLE. `wifi` forces Wi-Fi. `bluetooth` stays on BLE
/// even when Wi-Fi is reachable, so the phone keeps its own network.
enum TransportPreference { auto, wifi, bluetooth }

/// The control operations the UI issues, independent of transport.
/// Both `WifiControlTransport` (HTTP) and `BleControlTransport` (GATT)
/// implement this. The token is shared across transports, so switching
/// between them never needs a re-login (BLE spec §Roaming).
abstract interface class ControlTransport {
  TransportKind get kind;

  /// Toggle a relay. Over Wi-Fi, `ch` is a separate field; over BLE the
  /// channel is already encoded in [id] (`ext<slot>_<ch>`), so `ch` is
  /// ignored there.
  Future<void> setRelay({required String id, required bool on, int? ch});

  /// Turn every switch off.
  Future<void> killAll();
}
