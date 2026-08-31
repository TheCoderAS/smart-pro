import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/extensions/data/extension_repository.dart';
import '../../features/extensions/domain/extension_models.dart';
import '../../features/firmware/data/firmware_repository.dart';
import '../../features/firmware/domain/firmware_models.dart';
import '../../features/mesh/data/mesh_repository.dart';
import '../../features/switches/data/switch_repository.dart';
import '../api/failure.dart';
import '../logging/log.dart';
import '../ws/state_socket.dart';
import 'control_transport.dart';
import 'link_state.dart';
import 'transport_manager.dart';
import 'wifi_command_gate.dart';

/// Wi-Fi control path — a thin adapter over the existing HTTP
/// repositories. No behaviour change: this is what the app has always
/// done, now reachable through the transport interface.
class WifiControlTransport implements ControlTransport {
  WifiControlTransport(this._ref);

  final Ref _ref;

  SwitchRepository get _switch => _ref.read(switchRepositoryProvider);
  ExtensionRepository get _ext => _ref.read(extensionRepositoryProvider);
  FirmwareRepository get _fw => _ref.read(firmwareRepositoryProvider);
  AuthRepository get _auth => _ref.read(authRepositoryProvider);

  @override
  TransportKind get kind => TransportKind.wifi;

  /// Anything slower than this gets a log line — user-visible lag with a
  /// number attached beats guessing where the time went.
  static const slowCommand = Duration(milliseconds: 500);

  @override
  Future<void> setRelay({
    required String id,
    required bool on,
    int? ch,
    String? masterUid,
  }) async {
    final clock = Stopwatch()..start();
    // Through the gate: one command in flight, repeat taps on one switch
    // coalesced to the final state. The master's server is tiny; offered
    // load has to be bounded on this side.
    await _ref.read(wifiCommandGateProvider).relay(
          id: id,
          on: on,
          ch: ch,
          masterUid: masterUid,
          send: ({required id, required on, ch, masterUid}) => _switch
              .setRelay(id: id, on: on, ch: ch, masterUid: masterUid),
        );
    // Queue wait included on purpose: this is the delay the user feels.
    if (clock.elapsed > slowCommand) {
      log.i('relay $id took ${clock.elapsedMilliseconds}ms');
    }
    // A command that went through is proof the link works — better proof
    // than any probe, and it lets the heartbeat stay quiet while the user
    // is actively driving switches.
    _ref.read(linkStateProvider.notifier).markAlive();
    _expectSnapshot();
  }

  @override
  Future<void> killAll() async {
    await _ref.read(wifiCommandGateProvider).killAll(_switch.killAll);
    _ref.read(linkStateProvider.notifier).markAlive();
    _expectSnapshot();
  }

  /// How long a successful command may go unconfirmed by a snapshot
  /// before the socket is presumed dead and reconnected.
  static const confirmWithin = Duration(seconds: 2);

  /// The master pushes a snapshot on every state change, so a successful
  /// command followed by silence means the state socket is lying: it
  /// looks connected but delivers nothing (the half-open leftover of a
  /// background suspension), or it is sitting out a reconnect backoff.
  /// Meanwhile the tile's optimistic override quietly times out and the
  /// UI snaps back to a stale state — the relay clicked and the app
  /// disagrees. One reconnect fixes every variant: the master pushes the
  /// full document immediately on connect (API §4).
  void _expectSnapshot() {
    final before = _ref.read(lastWsSnapshotAtProvider);
    Future<void>.delayed(confirmWithin, () {
      try {
        if (_ref.read(currentTransportProvider) != TransportKind.wifi) return;
        if (_ref.read(lastWsSnapshotAtProvider) != before) return;
        log.i('no snapshot after a command — reconnecting the state socket');
        _ref.invalidate(stateSocketProvider);
      } on Object {
        // Transport switched and this ref was torn down meanwhile.
      }
    });
  }

  @override
  Future<List<ExtensionInfo>> extensions() => _ext.list();

  /// Admin aimed at another master in the mesh goes through the mesh's
  /// own config channel, which the connected master forwards. A null uid
  /// is the master we are talking to, and takes the direct endpoint.
  MeshRepository get _mesh => _ref.read(meshRepositoryProvider);

  @override
  Future<void> reorder(List<String> orderedIds, {String? masterUid}) {
    if (masterUid == null || masterUid.isEmpty) {
      return _switch.reorder(orderedIds);
    }
    return _mesh.config(
      cmd: 'reorder_switches',
      targetUid: masterUid,
      extra: {'order': orderedIds.join(',')},
    );
  }

  @override
  Future<void> renameExtension({required int slot, required String name}) =>
      _ext.rename(slot: slot, name: name);

  @override
  Future<void> renameSwitch({
    required String id,
    required String name,
    String? masterUid,
  }) {
    if (masterUid == null || masterUid.isEmpty) {
      return _switch.rename(id: id, name: name);
    }
    // `rename_switch` in the mesh protocol renames an extension SLOT;
    // renaming one switch by id is its own command.
    return _mesh.config(
      cmd: 'rename_sw_id',
      targetUid: masterUid,
      extra: {'name': name, 'order': id},
    );
  }

  @override
  Future<void> renameMaster(String name, {String? masterUid}) {
    if (masterUid == null || masterUid.isEmpty) {
      return _auth.renameMaster(name);
    }
    return _mesh.config(
      cmd: 'rename_master',
      targetUid: masterUid,
      extra: {'name': name},
    );
  }

  @override
  Future<void> cleanupExtensions({String? masterUid}) =>
      _ref.read(extensionRepositoryProvider).cleanupDead(targetUid: masterUid);

  @override
  Future<void> setRestore({
    required String id,
    required bool restore,
    String? masterUid,
  }) {
    if (masterUid == null || masterUid.isEmpty) {
      return _switch.setRestore(id: id, restore: restore);
    }
    return _mesh.config(
      cmd: 'set_restore',
      targetUid: masterUid,
      extra: {'name': id, 'slot': restore ? 1 : 0},
    );
  }

  @override
  Future<FwStatus> fwStatus() async {
    final images = await _fw.storedImages();
    // The master's own version isn't in fw/list — /api/info carries it.
    var master = '';
    try {
      master = (await _auth.info()).fw;
    } on ApiFailure {
      // Non-fatal: staged images are still useful without the version.
    }
    return FwStatus(master: master, images: images);
  }
}
