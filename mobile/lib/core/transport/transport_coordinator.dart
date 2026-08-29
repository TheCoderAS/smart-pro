import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log.dart';
import '../permissions/scan_permissions.dart';
import '../storage/master_registry.dart';
import '../storage/saved_session.dart';
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

/// Reconciles the transport preference with actual reachability, then
/// drives `currentTransportProvider` and the BLE session. One device per
/// app — standalone or mesh — so there is exactly one preference.
///
/// - **auto:** Wi-Fi when the master answers on the LAN, else BLE.
/// - **wifi:** force Wi-Fi (BLE session torn down).
/// - **bluetooth:** BLE even when Wi-Fi is reachable.
///
/// Because the token is shared, flipping transports needs no re-login.
class TransportCoordinator {
  TransportCoordinator(this._ref);

  final Ref _ref;

  /// Serialises background reconciles. Two can be in flight on a cold
  /// start — one from app start, one when the session resolves — and they
  /// must not race each other into opposite transports.
  Future<void> _queue = Future<void>.value();

  /// Bumped by every explicit user choice. A background pass captures the
  /// epoch when it starts and goes quiet the moment it is stale, so a
  /// slow or wedged pass finishing late can never override what the user
  /// selected after it began. The user's action beats everything.
  int _epoch = 0;

  /// Decide and apply the transport. Call at app start, on dashboard
  /// entry, or when the session settles.
  Future<void> reconcile() {
    final next = _queue.then((_) => _reconcile());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// The transport preference, awaited so a just-logged-in dashboard
  /// doesn't race the async restore and read the default.
  Future<TransportPreference> effectivePreference() =>
      _ref.read(transportPreferenceProvider.notifier).ensureLoaded();

  Future<void> _reconcile() async {
    final epoch = _epoch;
    final pref = await effectivePreference();
    if (epoch != _epoch) return;
    await _apply(pref, epoch);
  }

  Future<void> _apply(TransportPreference pref, int epoch) async {
    final wifi = _ref.read(wifiServiceProvider);
    try {
      switch (pref) {
        case TransportPreference.wifi:
          await _applyWifi(epoch);
        case TransportPreference.bluetooth:
          await _applyBle(epoch);
        case TransportPreference.auto:
          final reachable = await wifi.masterReachable();
          if (epoch != _epoch) return;
          if (reachable) {
            await _applyWifi(epoch);
          } else {
            await _applyBle(epoch);
          }
      }
    } on Object catch (e) {
      log.w('transport apply failed: $e');
    }
  }

  Future<void> _applyWifi(int epoch) async {
    if (epoch != _epoch) return;
    _ref.read(currentTransportProvider.notifier).set(TransportKind.wifi);
    await _ref.read(bleSessionProvider.notifier).deactivate();
    // Pin this app's traffic to the master's network even when the user
    // joined it from the phone's own settings — otherwise Android routes
    // us back to mobile data and every request looks like dead hardware.
    await _ref.read(wifiServiceProvider).bindToWifi();
  }

  Future<void> _applyBle(int epoch) async {
    // Never flip into BLE without a session and permission — the mode
    // must not change unless it can actually work (Epic 5).
    if (await canUseBle() != TransportChoice.ok) {
      // But never tear a live BLE link down as the "fallback": if a link
      // is up, the gates were wrong about it, not the link.
      if (_ref.read(bleSessionProvider.notifier).client?.isConnected ??
          false) {
        _ref.read(currentTransportProvider.notifier).set(TransportKind.ble);
        return;
      }
      await _applyWifi(epoch);
      return;
    }
    if (epoch != _epoch) return;
    _ref.read(currentTransportProvider.notifier).set(TransportKind.ble);
    // Bluetooth doesn't want the phone pinned to a network with no
    // internet; give it its own routing back.
    await _ref.read(wifiServiceProvider).release();
    final target = await _bleTarget();
    if (epoch != _epoch) return;
    await _ref.read(bleSessionProvider.notifier).activate(
          meshId: target?.meshId,
          uid: target?.uid,
        );
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
    // A live BLE link is its own proof: it exists, so it can be used.
    // Without this, a reconcile racing the startup permission dialogs
    // could lose a permission *request* (dialog collision), conclude
    // Bluetooth was unusable, and flip a working BLE session onto Wi-Fi
    // — leaving both stacks running at once.
    if (_ref.read(bleSessionProvider.notifier).client?.isConnected ??
        false) {
      return TransportChoice.ok;
    }
    // The vault, not just the in-memory token. On a cold start the
    // dashboard can be up and reconciling before the session bootstrap has
    // restored the token, and reading that as "never signed in" is what
    // silently dropped a Bluetooth-preferring user onto Wi-Fi — for the
    // whole app lifetime, because nothing reconciled a second time.
    if (await _ref.read(savedSessionProvider).ensureToken() == null) {
      return TransportChoice.needsWifiLogin;
    }
    if (!await ensureBlePermissions()) {
      return TransportChoice.permissionDenied;
    }
    return TransportChoice.ok;
  }

  /// Explicit user choice from Settings.
  ///
  /// For Bluetooth, both gates run **before** the preference is
  /// persisted or the transport flipped — a refusal returns the reason
  /// and leaves the user exactly where they were (Epic 5).
  ///
  /// Applied DIRECTLY, not through the queue: the user's tap must never
  /// wait behind a background pass, and bumping the epoch first makes
  /// every queued or in-flight pass stale, so nothing that started before
  /// the tap can override it afterwards.
  Future<TransportChoice> choose(TransportPreference pref) async {
    if (pref == TransportPreference.bluetooth) {
      final gate = await canUseBle();
      if (gate != TransportChoice.ok) return gate;
    }
    await _ref.read(transportPreferenceProvider.notifier).set(pref);
    _epoch++;
    await _apply(pref, _epoch);
    return TransportChoice.ok;
  }

  /// The paired device: its uid, and its mesh when it is one. Null when
  /// nothing is registered yet.
  ///
  /// A mesh id of 0 or null means standalone, and standalone must not
  /// filter the scan — the uid ranking and the post-connect identity
  /// check are what keep a neighbour's master out.
  Future<({String uid, int? meshId})?> _bleTarget() async {
    try {
      // Awaited, not `.value`: at app start the registry has not loaded.
      final masters = await _ref.read(masterRegistryProvider.future);
      if (masters.isEmpty) return null;
      final m = masters.first;
      final mesh = (m.meshId != null && m.meshId != 0) ? m.meshId : null;
      return (uid: m.uid, meshId: mesh);
    } on Object catch (e) {
      log.w('ble target lookup failed: $e');
      return null;
    }
  }
}
