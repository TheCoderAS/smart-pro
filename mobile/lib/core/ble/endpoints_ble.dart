/// BLE control GATT identifiers and command shapes
/// (UNISYNC_BLE_CONTROL_v1.md §Protocol). The service is the same one
/// recovery uses (`…31`); control adds three characteristics.
abstract final class BleControlUuids {
  static const service = '556e6973-796e-6320-5265-636f76657231';

  // Recovery (already used by RecoveryService): …32 / …33 / …34
  // Control:
  static const controlRequest = '556e6973-796e-6320-5265-636f76657235';
  static const controlResponse = '556e6973-796e-6320-5265-636f76657236';
  static const statePush = '556e6973-796e-6320-5265-636f76657237';
}

/// JSON command builders (BLE spec §Commands). `id` for a relay carries
/// the channel suffix (`ext<slot>_<ch>` / `master_<ch>`) — there is no
/// separate `ch` field over BLE.
abstract final class BleCommands {
  static Map<String, Object?> login(String password) => {
    'c': 'login',
    'p': password,
  };

  static Map<String, Object?> relay({
    required String token,
    required String id,
    required bool on,
  }) => {
    't': token,
    'c': 'relay',
    'id': id,
    's': on,
  };

  static Map<String, Object?> killAll(String token) => {
    't': token,
    'c': 'killall',
  };

  static Map<String, Object?> extensions(String token) => {
    't': token,
    'c': 'exts',
  };

  static Map<String, Object?> mesh(String token) => {
    't': token,
    'c': 'mesh',
  };

  static Map<String, Object?> state(String token) => {
    't': token,
    'c': 'state',
  };
}
