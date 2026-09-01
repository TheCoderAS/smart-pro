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

  /// Every admin verb below takes the same optional peer uid `relay`
  /// does: in a mesh the master holding the Bluetooth link forwards the
  /// command on, so "which master" is never limited by which one the
  /// radio happens to have found.
  static Map<String, Object?> reorder({
    required BleProof proof,
    required String order,
    String? masterUid,
  }) =>
      _cmd(proof, {
        'c': 'reorder',
        'order': order,
        if (masterUid != null && masterUid.isNotEmpty) 'uid': masterUid,
      });

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
    String? masterUid,
  }) =>
      _cmd(proof, {
        'c': 'rename_sw',
        'id': id,
        'name': name,
        if (masterUid != null && masterUid.isNotEmpty) 'uid': masterUid,
      });

  /// Per-switch power-cut policy. Same shape as `rename_sw`.
  static Map<String, Object?> setRestore({
    required BleProof proof,
    required String id,
    required bool restore,
    String? masterUid,
  }) =>
      _cmd(proof, {
        'c': 'set_restore',
        'id': id,
        'restore': restore,
        if (masterUid != null && masterUid.isNotEmpty) 'uid': masterUid,
      });

  static Map<String, Object?> renameMaster({
    required BleProof proof,
    required String name,
    String? masterUid,
  }) =>
      _cmd(proof, {
        'c': 'rename_master',
        'name': name,
        if (masterUid != null && masterUid.isNotEmpty) 'uid': masterUid,
      });

  /// Forget every extension slot the target master cannot reach. There
  /// is no extension list in the app, so this is how a dead board stops
  /// holding a slot.
  static Map<String, Object?> cleanupExtensions({
    required BleProof proof,
    String? masterUid,
  }) =>
      _cmd(proof, {
        'c': 'cleanup_exts',
        if (masterUid != null && masterUid.isNotEmpty) 'uid': masterUid,
      });

  /// Firmware images staged on the master + its own version. Transfer
  /// still requires Wi-Fi.
  static Map<String, Object?> fwList(BleProof proof) =>
      _cmd(proof, {'c': 'fwlist'});

  static Map<String, Object?> mesh(BleProof proof) =>
      _cmd(proof, {'c': 'mesh'});

  /// Renames the MESH, not this master. Firmware 11.32.0.
  static Map<String, Object?> renameMesh({
    required BleProof proof,
    required String name,
  }) =>
      _cmd(proof, {'c': 'mesh_rename', 'name': name});

  /// This master leaves its mesh. Firmware 11.32.0.
  static Map<String, Object?> leaveMesh(BleProof proof) =>
      _cmd(proof, {'c': 'mesh_leave'});

  /// Removes another master, by uid. Never routed to a peer: the kick is
  /// issued by the master holding the link. Firmware 11.32.0.
  static Map<String, Object?> kickFromMesh({
    required BleProof proof,
    required String uid,
  }) =>
      _cmd(proof, {'c': 'mesh_kick', 'uid': uid});
}
