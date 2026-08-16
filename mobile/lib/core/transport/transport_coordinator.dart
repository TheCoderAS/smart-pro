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

  /// Serialises reconciles. Two can be in flight on a cold start — one
  /// from app start, one when the session resolves — and they must not
  /// race each other into opposite transports. Each runs in turn and
  /// re-reads the world, so the last one wins on current facts.
  Future<void> _queue = Future<void>.value();

  /// Decide and apply the transport. Call at app start, on dashboard
  /// entry, on a preference change, or when the user taps the switch in
  /// the status pill.
  Future<void> reconcile() {
    final next = _queue.then((_) => _reconcile());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// The preference in force: the active master's own choice when it has
  /// one, else the global setting.
  ///
  /// Each master keeps its own mode — Bluetooth for the box in the shed,
  /// Wi-Fi for the hall — so "the" preference only means anything relative
  /// to which master the app is pointed at. The per-master field existed
  /// in the registry from the start; nothing ever read it, so every master
  /// was driven by whatever mode the last one had been set to.
  Future<TransportPreference> effectivePreference() async {
    // Await the persisted global first so a just-logged-in dashboard
    // doesn't race the async restore and read the default `auto`.
    final global = await _ref.read(transportPreferenceProvider.notifier)
        .ensureLoaded();
    try {
      final masters = await _ref.read(masterRegistryProvider.future);
      if (masters.isEmpty) return global;
      final lastUid =
          await _ref.read(masterRegistryProvider.notifier).lastUsed();
      final m = masters.firstWhere(
        (x) => x.uid == lastUid,
        orElse: () => masters.first,
      );
      return m.preferredTransport ?? global;
    } on Object catch (e) {
      log.w('per-master preference lookup failed: $e');
      return global;
    }
  }

  Future<void> _reconcile() async {
    final pref = await effectivePreference();
    // Keep the Settings radio honest about which master's choice it is
    // showing, without persisting anything.
    _ref.read(transportPreferenceProvider.notifier).reflect(pref);
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
      final target = await _bleTarget();
      await _ref.read(bleSessionProvider.notifier).activate(
            meshId: target?.meshId,
            uid: target?.uid,
          );
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
    // The choice belongs to the master it was made for. Writing it
    // globally meant setting Bluetooth for the shed silently flipped the
    // hall to Bluetooth too. The global setting remains the default for
    // masters with no choice of their own, and the only place to store
    // one before anything is registered.
    final uid = await _activeUid();
    if (uid != null) {
      await _ref
          .read(masterRegistryProvider.notifier)
          .setPreferredMode(uid, pref.name);
      _ref.read(transportPreferenceProvider.notifier).reflect(pref);
    } else {
      await _ref.read(transportPreferenceProvider.notifier).set(pref);
    }
    await reconcile();
    return TransportChoice.ok;
  }

  /// The uid of the master the app is pointed at, or null when nothing
  /// is registered yet.
  Future<String?> _activeUid() async {
    try {
      final masters = await _ref.read(masterRegistryProvider.future);
      if (masters.isEmpty) return null;
      final lastUid =
          await _ref.read(masterRegistryProvider.notifier).lastUsed();
      return masters
          .firstWhere((m) => m.uid == lastUid, orElse: () => masters.first)
          .uid;
    } on Object catch (_) {
      return null;
    }
  }

  /// The master the app is pointed at: uid, and its mesh when it has one.
  ///
  /// This used to return "the mesh id of the first registered master that
  /// has one", which quietly made a second master unreachable. Add a
  /// standalone master alongside a meshed one and the scan stayed filtered
  /// to the mesh — a standalone beacon carries mesh id 0, so it was
  /// discarded before anything tried to connect, and the master never saw
  /// a connection attempt at all. The app just said "Reconnecting" for
  /// ever, whichever of the two was selected.
  Future<({String uid, int? meshId})?> _bleTarget() async {
    try {
      // Awaited, not `.value`: at app start the registry has not loaded.
      final masters = await _ref.read(masterRegistryProvider.future);
      if (masters.isEmpty) return null;
      final lastUid =
          await _ref.read(masterRegistryProvider.notifier).lastUsed();
      final m = masters.firstWhere(
        (x) => x.uid == lastUid,
        orElse: () => masters.first,
      );
      // 0 and null both mean standalone, and standalone must not filter.
      final mesh = (m.meshId != null && m.meshId != 0) ? m.meshId : null;
      return (uid: m.uid, meshId: mesh);
    } on Object catch (e) {
      log.w('ble target lookup failed: $e');
      return null;
    }
  }
}
