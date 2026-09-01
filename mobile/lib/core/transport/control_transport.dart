import '../../features/extensions/domain/extension_models.dart';
import '../../features/firmware/domain/firmware_models.dart';

/// Which physical path control commands and state currently flow over.
enum TransportKind { wifi, ble }

/// The user's transport preference (Settings). Exactly two, by decree:
/// `wifi` uses the switch's Wi-Fi; `bluetooth` stays on BLE even when
/// Wi-Fi is reachable, so the phone keeps its own network. There is no
/// automatic mode — a silent fallback was how the app ended up on the
/// wrong transport with no way to see why.
enum TransportPreference { wifi, bluetooth }

/// The control operations the UI issues, independent of transport.
/// Both `WifiControlTransport` (HTTP) and `BleControlTransport` (GATT)
/// implement this. The token is shared across transports, so switching
/// between them never needs a re-login (BLE spec §Roaming).
///
/// Everything here works on either transport (BLE spec v2 §1). The only
/// things BLE genuinely cannot do — firmware *transfer*, mesh admin,
/// password change, provisioning, rename/assign — are not on this
/// interface; the UI guards those to Wi-Fi.
abstract interface class ControlTransport {
  TransportKind get kind;

  /// Toggle a relay. Over Wi-Fi, `ch` is a separate field; over BLE the
  /// channel is already encoded in [id] (`ext<slot>_<ch>`), so `ch` is
  /// ignored there.
  ///
  /// [masterUid] names the master that owns the switch. Null (or this
  /// master's own uid) drives a local relay; any other uid is relayed
  /// across the mesh — which is what makes a mesh dashboard, and Bluetooth
  /// control of the whole mesh, work at all.
  Future<void> setRelay({
    required String id,
    required bool on,
    int? ch,
    String? masterUid,
  });

  /// Turn every switch off (one command, not a per-switch loop).
  Future<void> killAll();

  /// The extensions attached to this master.
  Future<List<ExtensionInfo>> extensions();

  /// Persist a new switch order (comma-joined ids on the wire). The
  /// order belongs to the master that owns the switches and survives its
  /// power cycles, so [masterUid] names which master to store it on —
  /// null for the one the app is connected to.
  Future<void> reorder(List<String> orderedIds, {String? masterUid});

  /// Renames — work on either transport since firmware v11.18.0
  /// (`rename_ext` / `rename_sw` / `rename_master`). Assignment
  /// (assign/reject/replace/remove) is still Wi-Fi-only.
  Future<void> renameExtension({required int slot, required String name});
  Future<void> renameSwitch({
    required String id,
    required String name,
    String? masterUid,
  });
  Future<void> renameMaster(String name, {String? masterUid});

  /// Forget every extension slot [masterUid] cannot reach — "cleanup
  /// dead extension slots". The master decides what unreachable means;
  /// the app never second-guesses its presence tracking.
  Future<void> cleanupExtensions({String? masterUid});

  /// Per-switch power-cut policy: restore the last state, or start off.
  /// The master owns it; the app only asks for a change and waits for the
  /// next snapshot to confirm.
  Future<void> setRestore({
    required String id,
    required bool restore,
    String? masterUid,
  });

  /// The master's running version + the images staged in its library.
  /// Firmware *transfer* still requires Wi-Fi.
  Future<FwStatus> fwStatus();

  /// Rename the mesh. Every member follows, so the whole home changes
  /// name together — which is why this is not [renameMaster].
  Future<void> renameMesh(String name);

  /// Take the master holding this link out of its mesh.
  Future<void> leaveMesh();

  /// Remove another master from the mesh, by uid.
  ///
  /// Getting out of a home must not depend on the transport the home is
  /// built on. These three were Wi-Fi-only, which made Bluetooth a mode
  /// you could drive a mesh from and not undo — the dead end the story
  /// rules out.
  Future<void> kickFromMesh(String uid);
}
