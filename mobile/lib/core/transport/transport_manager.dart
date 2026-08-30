import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../ws/state_dto.dart';
import '../ws/state_socket.dart';
import 'access_reset.dart';
import 'ble_session.dart';
import 'control_transport.dart';
import 'wifi_transport.dart';

/// Persisted transport preference (Settings). Defaults to Wi-Fi and
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
    return TransportPreference.wifi;
  }

  Future<void> _restore() => ensureLoaded();

  /// Reads (and applies) the persisted preference, returning it. The
  /// coordinator awaits this before deciding a transport so a fresh
  /// login doesn't race the async restore and read the default.
  ///
  /// A persisted 'auto' from a build that still had automatic mode reads
  /// as Wi-Fi — Bluetooth must only ever be an explicit choice.
  Future<TransportPreference> ensureLoaded() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(key);
    final pref = saved == TransportPreference.bluetooth.name
        ? TransportPreference.bluetooth
        : TransportPreference.wifi;
    if (pref != state) state = pref;
    return pref;
  }

  Future<void> set(TransportPreference pref) async {
    state = pref;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, pref.name);
    // Re-assert: the notifier's initial async restore can land in the
    // middle of the awaits above and clobber a fresh choice with the
    // stale persisted value it read before this write.
    state = pref;
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
    // Rebuild when the session changes (connect / roam / teardown) so
    // the transport always holds the live client. The token isn't
    // passed — it lives inside the client and only derives proofs.
    ref.watch(bleSessionProvider);
    final session = ref.watch(bleSessionProvider.notifier);
    return BleControlTransport(
      session.client,
      onTokenRejected: ref.read(accessResetProvider.notifier).strike,
    );
  }
  return WifiControlTransport(ref);
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
