import '../../features/switches/data/switch_repository.dart';
import 'control_transport.dart';

/// Wi-Fi control path — a thin adapter over the existing HTTP
/// `SwitchRepository`. No behaviour change: this is what the app has
/// always done, now reachable through the transport interface.
class WifiControlTransport implements ControlTransport {
  const WifiControlTransport(this._repo);

  final SwitchRepository _repo;

  @override
  TransportKind get kind => TransportKind.wifi;

  @override
  Future<void> setRelay({required String id, required bool on, int? ch}) =>
      _repo.setRelay(id: id, on: on, ch: ch);

  @override
  Future<void> killAll() => _repo.killAll();
}
