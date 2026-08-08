import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log.dart';
import '../storage/master_registry.dart';
import '../wifi/wifi_service.dart';
import 'ble_session.dart';
import 'control_transport.dart';
import 'transport_manager.dart';

final transportCoordinatorProvider =
    Provider<TransportCoordinator>(TransportCoordinator.new);

/// Reconciles the user's transport preference with actual reachability,
/// then drives `currentTransportProvider` and the BLE session.
///
/// - **auto:** Wi-Fi when the master answers on the LAN, else BLE.
/// - **wifi:** force Wi-Fi (BLE session torn down).
/// - **bluetooth:** BLE even when Wi-Fi is reachable.
///
/// Because the token is shared, flipping transports needs no re-login.
class TransportCoordinator {
  TransportCoordinator(this._ref);

  final Ref _ref;

  /// Decide and apply the transport. Call on dashboard entry, on a
  /// preference change, or when the user taps the switch in the status
  /// pill.
  Future<void> reconcile() async {
    final pref = _ref.read(transportPreferenceProvider);
    final wifi = _ref.read(wifiServiceProvider);

    Future<void> useWifi() async {
      _ref.read(currentTransportProvider.notifier).set(TransportKind.wifi);
      await _ref.read(bleSessionProvider.notifier).deactivate();
    }

    Future<void> useBle() async {
      _ref.read(currentTransportProvider.notifier).set(TransportKind.ble);
      final meshId = await _pairedMeshId();
      await _ref.read(bleSessionProvider.notifier).activate(meshId: meshId);
    }

    try {
      switch (pref) {
        case TransportPreference.wifi:
          await useWifi();
        case TransportPreference.bluetooth:
          await useBle();
        case TransportPreference.auto:
          final reachable = await wifi.masterReachable();
          if (reachable) {
            await useWifi();
          } else {
            await useBle();
          }
      }
    } on Object catch (e) {
      log.w('transport reconcile failed: $e');
    }
  }

  /// Explicit user choice from the status pill — persist and apply.
  Future<void> choose(TransportPreference pref) async {
    await _ref.read(transportPreferenceProvider.notifier).set(pref);
    await reconcile();
  }

  Future<int?> _pairedMeshId() async {
    try {
      final masters = _ref.read(masterRegistryProvider).value ?? const [];
      for (final m in masters) {
        if (m.meshId != null && m.meshId != 0) return m.meshId;
      }
    } on Object catch (_) {
      // registry not ready — scan for any Unisync master
    }
    return null;
  }
}
