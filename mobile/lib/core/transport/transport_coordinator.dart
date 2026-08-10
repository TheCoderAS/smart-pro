import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../logging/log.dart';
import '../permissions/scan_permissions.dart';
import '../storage/master_registry.dart';
import '../wifi/wifi_service.dart';
import '../ws/state_socket.dart';
import 'ble_session.dart';
import 'control_transport.dart';
import 'transport_manager.dart';

/// Outcome of a transport choice. Epic 5 requires both gates to run
/// *before* the mode changes, so a refusal leaves the user in their
/// current mode with an explanation — never half-switched.
enum TransportChoice {
  ok,

  /// No Wi-Fi-issued session yet. BLE has no login, so the user must
  /// sign in over Wi-Fi first.
  needsWifiLogin,

  /// The OS refused the nearby-devices/Bluetooth permission.
  permissionDenied,
}

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
    // Await the persisted preference so a just-logged-in dashboard
    // doesn't race the async restore and read the default `auto`.
    final pref = await _ref.read(transportPreferenceProvider.notifier)
        .ensureLoaded();
    final wifi = _ref.read(wifiServiceProvider);

    Future<void> useWifi() async {
      _ref.read(currentTransportProvider.notifier).set(TransportKind.wifi);
      await _ref.read(bleSessionProvider.notifier).deactivate();
      // Pin this app's traffic to the master's network even when the user
      // joined it from the phone's own settings — otherwise Android routes
      // us back to mobile data and every request looks like dead hardware.
      await wifi.bindToWifi();
    }

    Future<void> useBle() async {
      // Never flip into BLE without a session and permission — the mode
      // must not change unless it can actually work (Epic 5).
      if (await canUseBle() != TransportChoice.ok) {
        await useWifi();
        return;
      }
      _ref.read(currentTransportProvider.notifier).set(TransportKind.ble);
      // Bluetooth doesn't want the phone pinned to a network with no
      // internet; give it its own routing back.
      await wifi.release();
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

  /// Manual reconnect (the dashboard refresh). Over BLE, re-scan and
  /// re-open the client; over Wi-Fi, re-run reachability + selection.
  Future<void> reconnect() async {
    final kind = _ref.read(currentTransportProvider);
    if (kind == TransportKind.ble) {
      await _ref.read(bleSessionProvider.notifier).reconnect();
    } else {
      await reconcile();
    }
  }

  /// Force a fresh state snapshot now — the dashboard pull-to-refresh
  /// and a post-reorder nudge. Over BLE, re-request `state`; over Wi-Fi,
  /// reconnect the socket so the master re-pushes.
  Future<void> refreshState() async {
    try {
      if (_ref.read(currentTransportProvider) == TransportKind.ble) {
        await _ref.read(bleSessionProvider.notifier).refreshState();
      } else {
        _ref.invalidate(stateSocketProvider);
      }
    } on Object catch (e) {
      log.w('refreshState failed: $e');
    }
  }

  /// Can BLE actually be used right now? Checked *before* any mode
  /// change: a Wi-Fi-issued session must exist (BLE has no login) and
  /// the OS permission must be granted.
  Future<TransportChoice> canUseBle() async {
    if (_ref.read(tokenProvider) == null) {
      return TransportChoice.needsWifiLogin;
    }
    if (!await ensureBlePermissions()) {
      return TransportChoice.permissionDenied;
    }
    return TransportChoice.ok;
  }

  /// Explicit user choice from the status pill or Settings.
  ///
  /// For Bluetooth, both gates run **before** the preference is
  /// persisted or the transport flipped — a refusal returns the reason
  /// and leaves the user exactly where they were (Epic 5).
  Future<TransportChoice> choose(TransportPreference pref) async {
    if (pref == TransportPreference.bluetooth) {
      final gate = await canUseBle();
      if (gate != TransportChoice.ok) return gate;
    }
    await _ref.read(transportPreferenceProvider.notifier).set(pref);
    await reconcile();
    return TransportChoice.ok;
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
