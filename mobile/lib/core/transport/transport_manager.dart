import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../../features/switches/data/switch_repository.dart';
import '../api/dio_client.dart';
import '../ws/state_dto.dart';
import '../ws/state_socket.dart';
import 'ble_session.dart';
import 'control_transport.dart';
import 'wifi_transport.dart';

/// Persisted transport preference (Settings). Defaults to auto and
/// loads asynchronously after first frame — reading it synchronously
/// never touches SharedPreferences, so it is safe in tests.
final transportPreferenceProvider =
    NotifierProvider<TransportPreferenceNotifier, TransportPreference>(
  TransportPreferenceNotifier.new,
);

class TransportPreferenceNotifier extends Notifier<TransportPreference> {
  /// SharedPreferences key — public so a cold-start bootstrap can read
  /// the persisted preference before this notifier has restored.
  static const key = 'transport.preference';

  @override
  TransportPreference build() {
    Future.microtask(_restore);
    return TransportPreference.auto;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(key);
    final pref = TransportPreference.values.firstWhere(
      (p) => p.name == saved,
      orElse: () => TransportPreference.auto,
    );
    if (pref != state) state = pref;
  }

  Future<void> set(TransportPreference pref) async {
    state = pref;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, pref.name);
  }
}

/// The transport currently carrying control + state. Defaults to Wi-Fi
/// (so existing behaviour is unchanged until BLE is chosen/needed). The
/// [TransportCoordinator] updates it from preference + reachability.
final currentTransportProvider =
    NotifierProvider<CurrentTransportNotifier, TransportKind>(
  CurrentTransportNotifier.new,
);

class CurrentTransportNotifier extends Notifier<TransportKind> {
  @override
  TransportKind build() => TransportKind.wifi;

  void set(TransportKind kind) {
    if (kind != state) state = kind;
  }
}

/// The active control path — Wi-Fi (HTTP repo) or BLE (GATT client),
/// chosen by [currentTransportProvider]. Callers issue `setRelay` /
/// `killAll` here without knowing the transport.
final activeControlProvider = Provider<ControlTransport>((ref) {
  final kind = ref.watch(currentTransportProvider);
  if (kind == TransportKind.ble) {
    final session = ref.watch(bleSessionProvider.notifier);
    final token = ref.watch(tokenProvider);
    return BleControlTransport(session.client, token);
  }
  return WifiControlTransport(ref.watch(switchRepositoryProvider));
});

/// The active state stream — WebSocket (Wi-Fi) or BLE push. Both deliver
/// full [StateSnapshot]s, so the dashboard is transport-agnostic.
final activeStateProvider = StreamProvider<StateSnapshot>((ref) {
  final kind = ref.watch(currentTransportProvider);
  if (kind == TransportKind.ble) {
    return ref.watch(bleSessionProvider.notifier).stateStream;
  }
  // Bridge the WS StreamNotifier's AsyncValue into a plain stream so the
  // dashboard can watch one provider for either transport.
  final controller = StreamController<StateSnapshot>();
  final sub = ref.listen<AsyncValue<StateSnapshot>>(stateSocketProvider,
      (prev, next) {
    final v = next.value;
    if (v != null && !controller.isClosed) controller.add(v);
  }, fireImmediately: true);
  ref.onDispose(() {
    sub.close();
    controller.close();
  });
  return controller.stream;
});
