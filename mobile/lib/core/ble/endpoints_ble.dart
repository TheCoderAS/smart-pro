import 'ble_proof.dart';

/// BLE control GATT identifiers and command shapes (firmware v11.24.0 /
/// UX stories v5.1). The service is the same one recovery uses (`…31`).
abstract final class BleControlUuids {
  static const service = '556e6973-796e-6320-5265-636f76657231';

  // Recovery (used by RecoveryService): …32 / …33 / …34
  // Control:
  static const controlRequest = '556e6973-796e-6320-5265-636f76657235';
  static const controlResponse = '556e6973-796e-6320-5265-636f76657236';
  static const statePush = '556e6973-796e-6320-5265-636f76657237';

  /// Session nonce — read after connecting, different every connection.
  /// Feeds the per-command proof.
  static const sessionNonce = '556e6973-796e-6320-5265-636f76657238';
}

/// JSON command builders.
///
/// **There is no login over BLE** — firmware v11.24.0 removed it so the
/// password never crosses an open link (v5.1 Epic 5). BLE works only
/// with a token already obtained from a Wi-Fi login, and the token
/// itself is never sent: every command carries a [BleProof].
///
/// Relay ids carry the channel suffix (`ext<slot>_<ch>` / `master_<ch>`);
/// there is no separate `ch` field over BLE.
abstract final class BleCommands {
  static Map<String, Object?> _cmd(BleProof proof, Map<String, Object?> body) =>
      {...proof.toFields(), ...body};

  /// [masterUid] forwards the command to that master over the mesh. Absent
  /// means the master the phone is connected to.
  static Map<String, Object?> relay({
    required BleProof proof,
    required String id,
    required bool on,
    String? masterUid,
  }) =>
      _cmd(proof, {
        'c': 'relay',
        'id': id,
        's': on,
        if (masterUid != null && masterUid.isNotEmpty) 'uid': masterUid,
      });

  /// One command turns everything off — never loop `relay`.
  static Map<String, Object?> killAll(BleProof proof) =>
      _cmd(proof, {'c': 'killall'});

  static Map<String, Object?> state(BleProof proof) =>
      _cmd(proof, {'c': 'state'});

  static Map<String, Object?> extensions(BleProof proof) =>
      _cmd(proof, {'c': 'exts'});

  static Map<String, Object?> reorder({
    required BleProof proof,
    required String order,
  }) =>
      _cmd(proof, {'c': 'reorder', 'order': order});

  static Map<String, Object?> renameExtension({
    required BleProof proof,
    required int slot,
    required String name,
  }) =>
      _cmd(proof, {'c': 'rename_ext', 'slot': slot, 'name': name});

  static Map<String, Object?> renameSwitch({
    required BleProof proof,
    required String id,
    required String name,
  }) =>
      _cmd(proof, {'c': 'rename_sw', 'id': id, 'name': name});

  /// Per-switch power-cut policy. Same shape as `rename_sw`.
  static Map<String, Object?> setRestore({
    required BleProof proof,
    required String id,
    required bool restore,
  }) =>
      _cmd(proof, {'c': 'set_restore', 'id': id, 'restore': restore});

  static Map<String, Object?> renameMaster({
    required BleProof proof,
    required String name,
  }) =>
      _cmd(proof, {'c': 'rename_master', 'name': name});

  /// Firmware images staged on the master + its own version. Transfer
  /// still requires Wi-Fi.
  static Map<String, Object?> fwList(BleProof proof) =>
      _cmd(proof, {'c': 'fwlist'});

  static Map<String, Object?> mesh(BleProof proof) =>
      _cmd(proof, {'c': 'mesh'});
}
