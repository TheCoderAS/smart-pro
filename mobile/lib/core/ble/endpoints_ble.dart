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

  /// Reorder switches — `order` is the comma-separated id list, same as
  /// the HTTP endpoint (BLE spec v2 §reorder).
  static Map<String, Object?> reorder({
    required String token,
    required String order,
  }) => {
    't': token,
    'c': 'reorder',
    'order': order,
  };

  /// Firmware images already staged on the master + its own version
  /// (BLE spec v2 §fwlist). Transfer still needs Wi-Fi.
  static Map<String, Object?> fwList(String token) => {
    't': token,
    'c': 'fwlist',
  };

  /// Renames — added over BLE in firmware v11.18.0. All reply
  /// `{"ok":true}` (or `{"err":…}`), persist to NVS, and push state.
  static Map<String, Object?> renameExtension({
    required String token,
    required int slot,
    required String name,
  }) => {
    't': token,
    'c': 'rename_ext',
    'slot': slot,
    'name': name,
  };

  static Map<String, Object?> renameSwitch({
    required String token,
    required String id,
    required String name,
  }) => {
    't': token,
    'c': 'rename_sw',
    'id': id,
    'name': name,
  };

  static Map<String, Object?> renameMaster({
    required String token,
    required String name,
  }) => {
    't': token,
    'c': 'rename_master',
    'name': name,
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
