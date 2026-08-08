import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/extensions/data/extension_repository.dart';
import '../../features/extensions/domain/extension_models.dart';
import '../../features/firmware/data/firmware_repository.dart';
import '../../features/firmware/domain/firmware_models.dart';
import '../../features/switches/data/switch_repository.dart';
import '../api/failure.dart';
import 'control_transport.dart';

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

  @override
  Future<void> setRelay({required String id, required bool on, int? ch}) =>
      _switch.setRelay(id: id, on: on, ch: ch);

  @override
  Future<void> killAll() => _switch.killAll();

  @override
  Future<List<ExtensionInfo>> extensions() => _ext.list();

  @override
  Future<void> reorder(List<String> orderedIds) => _switch.reorder(orderedIds);

  @override
  Future<void> renameExtension({required int slot, required String name}) =>
      _ext.rename(slot: slot, name: name);

  @override
  Future<void> renameSwitch({required String id, required String name}) =>
      _switch.rename(id: id, name: name);

  @override
  Future<void> renameMaster(String name) => _auth.renameMaster(name);

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
