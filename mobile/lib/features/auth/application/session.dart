import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/failure.dart';
import '../../../core/logging/log.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/storage/saved_session.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/transport/ble_session.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/transport_manager.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../../core/ws/snapshot_cache.dart';
import '../../onboarding/application/first_run.dart';
import '../data/auth_repository.dart';
import '../domain/models.dart';

/// Where the app stands with the master it is pointed at.
///
/// The lifecycle (bootstrap):
///   probing → needsWelcome           fresh install, nothing set up yet
///           → unreachable            can't open 192.168.4.1
///           → needsCommissioning     info.auth == false (ops guide §A2:
///                                    factory-fresh, API wide open)
///           → needsLogin             no stored token, or token rejected
///           → authenticated          token valid (restored or fresh)
sealed class SessionState {
  const SessionState();
}

final class Probing extends SessionState {
  const Probing();
}

final class MasterUnreachable extends SessionState {
  const MasterUnreachable();
}

/// The session died while the app was on Bluetooth — someone reset access
/// by changing the password.
///
/// Emphatically not a login form: login is Wi-Fi-only by design, so a
/// login screen here would be a dead end. This is an instruction to go and
/// sign in on the master's network.
final class AccessReset extends SessionState {
  const AccessReset({this.network});

  /// The network name to join, when we know it.
  final String? network;
}

/// The phone is on some other master's network. Distinct from unreachable
/// on purpose: "connect to B's network" is an instruction the user can
/// follow, "B is out of range" is not, and neither is a login problem.
final class WrongNetwork extends SessionState {
  const WrongNetwork({required this.wanted, this.found});

  /// The master the user asked for.
  final SavedMaster wanted;

  /// The master that answered instead, when we can name it.
  final String? found;
}

/// Fresh install with nothing configured. The story is explicit that this
/// lands on a branded welcome screen rather than an empty dashboard or a
/// bare login form — and, in practice, rather than "can't reach your
/// switch", which is what a first launch used to show.
final class NeedsWelcome extends SessionState {
  const NeedsWelcome();
}

/// Nothing is paired and no master answers on the LAN: a fresh install
/// (or a reinstall) with setup still to do. Renders the setup screen —
/// never "can't reach your switch", which is an outage screen for a home
/// that exists and offers nothing a first-time user can act on.
final class NeedsSetup extends SessionState {
  const NeedsSetup();
}

final class NeedsCommissioning extends SessionState {
  const NeedsCommissioning(this.info);
  final DeviceInfo info;
}

final class NeedsLogin extends SessionState {
  const NeedsLogin(this.info, {this.failure});
  final DeviceInfo info;

  /// Set when arriving here from a failed login attempt (wrong
  /// password, lockout, rate limit) so the UI can word the error.
  final ApiFailure? failure;
}

final class Authenticated extends SessionState {
  const Authenticated(this.info, {required this.mesh});
  final DeviceInfo info;

  /// True when the accepted password was the mesh password —
  /// UI wording per API §2.
  final bool mesh;
}

final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<SessionState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  SecureStore get _store => ref.read(secureStoreProvider);

  /// The firmware field of the stand-in identity a Bluetooth-carried
  /// session uses until a real state push arrives.
  static const placeholderFw = '—';

  /// True for an identity that never came from an HTTP probe.
  ///
  /// Such an identity must never reach an HTTP-only state: building
  /// [NeedsLogin] from it produced a sign-in form labelled with a master
  /// the phone had no network contact with — possibly powered off — while
  /// the form itself would talk to whoever answers 192.168.4.1. A ghost
  /// screen with no way out.
  static bool _isPlaceholder(DeviceInfo info) => info.fw == placeholderFw;

  @override
  Future<SessionState> build() => _bootstrap();

  Future<SessionState> _bootstrap() async {
    // Before touching the network at all: a first launch with no master
    // ever paired is a setup story, not a connectivity failure.
    try {
      final flags = await ref.read(firstRunProvider.future);
      if (!flags.welcomeSeen) {
        final masters = await ref.read(masterRegistryProvider.future);
        if (masters.isEmpty) return const NeedsWelcome();
        // Something is already paired (an upgrade from a build without
        // this screen) — don't show a welcome to an existing owner.
        await ref.read(firstRunProvider.notifier).markWelcomeSeen();
      }
    } on Object catch (e) {
      log.w('first-run check skipped: $e');
    }

    // Nothing paired yet means this launch is a setup story, and it is
    // decided with a 2-second TCP probe instead of the full HTTP timeout
    // chain. The welcome button used to sit on a bare spinner for the
    // whole timeout, only to land on a dead-end "can't reach your switch"
    // with no way to set anything up.
    List<SavedMaster> masters = const [];
    try {
      masters = await ref.read(masterRegistryProvider.future);
    } on Object catch (e) {
      log.w('registry read failed: $e');
    }
    if (masters.isEmpty &&
        !await ref
            .read(wifiServiceProvider)
            .masterReachable(timeout: const Duration(milliseconds: 2500))) {
      return const NeedsSetup();
    }

    // The user asked for Bluetooth, so ask Bluetooth first. Probing the
    // LAN ahead of it meant waiting out an HTTP timeout on a network we
    // were never going to use — and when the phone *was* on the master's
    // Wi-Fi, the probe succeeded and the whole bootstrap ran over Wi-Fi
    // despite the preference. Either way the preference lost.
    try {
      if (await _blePreferred()) {
        final ble = await _bleSession();
        if (ble != null) return ble;
      }
    } on Object catch (e) {
      log.w('ble-first bootstrap skipped: $e');
    }

    final DeviceInfo info;
    try {
      info = await _repo.info();
    } on Unreachable {
      // Off the master's Wi-Fi, and Bluetooth was either not preferred or
      // had no saved token to use (handled above). With nothing paired
      // there is nothing to reconnect to — that is setup, not an outage.
      if (masters.isEmpty) return const NeedsSetup();
      return const MasterUnreachable();
    }

    if (!info.auth) {
      // Factory-fresh master: API open until an owner password is set.
      return NeedsCommissioning(info);
    }

    // One home per app: whoever answered must be it. Ahead of the token
    // check on purpose -- we have no session for a stranger, and showing
    // a login form for one would be the exact mix-up the story calls a
    // bug.
    final wrong = await _wrongMasterAnswered(info.uid);
    if (wrong != null) return wrong;

    final stored = await _store.readToken(info.uid);
    if (stored == null) return NeedsLogin(info);

    // Cache the network name the master reports for itself, so the
    // "connect to X" copy is right even after a rename and never comes
    // from the phone's OS.
    await ref.read(masterRegistryProvider.notifier).ensure(
          uid: info.uid,
          ssid: info.ssid,
        );

    ref.read(tokenProvider.notifier).set(stored);
    try {
      final valid = await _repo.validateToken();
      if (valid) {
        // mesh flag is unknown for a restored session until the next
        // login; the WebSocket snapshot (block 6) refines it.
        return Authenticated(info, mesh: false);
      }
    } on ApiFailure catch (e) {
      log.w('token validation interrupted: ${e.describe()}');
      // Unreachable/locked/rate-limited — not a verdict on the token.
      // Keep it and treat the session as authenticated; any later 401
      // routes back through NeedsLogin.
      return Authenticated(info, mesh: false);
    }

    // Token rejected — stale after a password change (API §2).
    ref.read(tokenProvider.notifier).set(null);
    await _store.deleteToken(info.uid);
    return NeedsLogin(info);
  }

  /// [WrongNetwork] when whoever answered 192.168.4.1 is not the home
  /// this app is paired with, or null to carry on.
  ///
  /// One home per app. An unknown master answering means the phone joined
  /// a different Unisync network -- a neighbour's, or a fresh board.
  /// "Join your own network" is actionable; a login form for a stranger's
  /// switch is the mix-up the story calls a bug. Mesh members are the
  /// same home and are all registered, so uid membership is the test.
  Future<WrongNetwork?> _wrongMasterAnswered(String answeredUid) async {
    try {
      final masters = await ref.read(masterRegistryProvider.future);
      if (masters.isEmpty) return null; // nothing paired yet: adopt
      if (masters.any((m) => m.uid == answeredUid)) return null;
      return WrongNetwork(wanted: masters.first);
    } on Object catch (e) {
      log.w('home check skipped: $e');
    }
    return null;
  }

  /// Attempts a login. On success persists the token (keyed by master
  /// UID) and flips to [Authenticated]; on failure lands in
  /// [NeedsLogin] with the failure attached.
  Future<void> login(String password) async {
    final current = state.value;
    var info = switch (current) {
      NeedsLogin(:final info) => info,
      Authenticated(:final info) => info,
      NeedsCommissioning(:final info) => info,
      _ => null,
    };
    // A Bluetooth placeholder is not a device context — login is HTTP,
    // and this identity has never been confirmed over HTTP. Re-bootstrap
    // and let the probe decide who we are actually talking to.
    if (info != null && _isPlaceholder(info)) info = null;
    final ctx = info;
    if (ctx == null) {
      // No device context — re-bootstrap instead.
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(_bootstrap);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      try {
        final result = await _repo.login(password);
        await _store.writeToken(ctx.uid, result.token);
        // The device password doubles as the Wi-Fi password (API §1);
        // stored for the change-password rejoin dance.
        await _store.writePassword(ctx.uid, password);
        // Signing in IS adding the switch — record it now, not whenever
        // the first status update happens to arrive over Wi-Fi. The
        // unrecorded window between login and that update is what let
        // Bluetooth's adopt shortcut re-add a freshly removed master.
        await ref.read(masterRegistryProvider.notifier).ensure(
              uid: ctx.uid,
              ssid: ctx.ssid,
            );
        ref.read(tokenProvider.notifier).set(result.token);
        return Authenticated(ctx, mesh: result.mesh);
      } on ApiFailure catch (e) {
        return NeedsLogin(ctx, failure: e);
      }
    });
  }

  /// Explicit "Control over Bluetooth" from the unreachable screen.
  /// Enters the dashboard over BLE using a saved token. Returns false
  /// (leaving the current state untouched) when no saved token exists —
  /// the UI then tells the user to pair over Wi-Fi once.
  Future<bool> connectOverBle() async {
    try {
      final ble = await _bleSession();
      if (ble == null) return false;
      state = AsyncValue.data(ble);
      return true;
    } on Object catch (e) {
      log.w('connectOverBle failed: $e');
      return false;
    }
  }

  /// Sets up a Bluetooth-carried session from a saved token and forces
  /// the transport preference to Bluetooth, so the dashboard's reconcile
  /// activates BLE. The token is valid on any master in the mesh with no
  /// re-login (BLE spec §Auth). Returns null when there is no saved
  /// token to use.
  Future<Authenticated?> _bleSession() async {
    final cand = await ref.read(savedSessionProvider).read();
    if (cand == null) return null;
    ref.read(tokenProvider.notifier).set(cand.token);
    // One device per app, one preference: driving it over Bluetooth is
    // the preference from here on.
    await ref
        .read(transportPreferenceProvider.notifier)
        .set(TransportPreference.bluetooth);
    // The live transport too, not only the preference. Otherwise the
    // Wi-Fi socket sees a token appear while the transport still reads as
    // its default and opens a connection to a LAN we are not on.
    ref.read(currentTransportProvider.notifier).set(TransportKind.ble);
    // fw is unknown until a BLE state push arrives; uid comes from the
    // saved registry.
    return Authenticated(
      DeviceInfo(uptime: 0, freeHeap: 0, uid: cand.uid, fw: placeholderFw, auth: true),
      mesh: false,
    );
  }

  Future<bool> _blePreferred() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(TransportPreferenceNotifier.key) ==
        TransportPreference.bluetooth.name;
  }

  /// The master rejected our proof over Bluetooth: the password changed,
  /// so every token everywhere died. Route to the instruction screen
  /// rather than a login form Bluetooth cannot serve.
  Future<void> handleAccessReset() async {
    if (state.value is AccessReset) return;
    final info = switch (state.value) {
      Authenticated(:final info) => info,
      _ => null,
    };
    ref.read(tokenProvider.notifier).set(null);
    if (info != null) await _store.deleteToken(info.uid);
    final masters = ref.read(masterRegistryProvider).value ?? const [];
    String? network;
    for (final m in masters) {
      if (info != null && m.uid == info.uid) network = m.ssid;
    }
    network ??= masters.isNotEmpty ? masters.first.ssid : null;
    state = AsyncValue.data(AccessReset(network: network));
  }

  /// Local sign-out (API §2: "does nothing server side; discard the
  /// token locally").
  Future<void> signOut() async {
    final current = state.value;
    if (current is! Authenticated) return;
    await _repo.logout();
    await _store.deleteToken(current.info.uid);
    ref.read(tokenProvider.notifier).set(null);
    // A session carried over Bluetooth has no HTTP-confirmed identity to
    // hang a login form on — signing out of one used to conjure a sign-in
    // screen for a master that might not even be powered. Re-bootstrap
    // and land wherever the probe says we are: a real login form if its
    // network answers, the unreachable screen if not.
    if (_isPlaceholder(current.info)) {
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(_bootstrap);
      return;
    }
    state = AsyncValue.data(NeedsLogin(current.info));
  }

  /// Re-probes the master — pull-to-refresh on the unreachable screen,
  /// and the re-entry point after a password-change reconnect.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_bootstrap);
  }

  /// "Set up a different switch": forgets the paired home entirely —
  /// secrets, snapshot cache, registry — and re-probes, landing on the
  /// setup screen. The switch itself is untouched. Without this, a home
  /// whose master died for good could never be replaced: Settings lives
  /// behind the dashboard, and the dashboard needs the master.
  Future<void> forgetHome() async {
    try {
      final masters = await ref.read(masterRegistryProvider.future);
      for (final m in masters) {
        await _store.purgeMaster(m.uid);
      }
    } on Object catch (e) {
      log.w('forgetHome purge skipped: $e');
    }
    ref.read(tokenProvider.notifier).set(null);
    await ref.read(snapshotCacheProvider.notifier).clear();
    await ref.read(masterRegistryProvider.notifier).clear();
    // The connection-mode choice belonged to the removed switch's era.
    // Left standing, a stale "bluetooth" raced ahead of the next
    // sign-in's registration and handed the link to whatever Bluetooth
    // found. A fresh home starts on automatic.
    await ref
        .read(transportPreferenceProvider.notifier)
        .set(TransportPreference.auto);
    ref.read(currentTransportProvider.notifier).set(TransportKind.wifi);
    await ref.read(bleSessionProvider.notifier).deactivate();
    await refresh();
  }

  /// The reconnect dance after any password change (API §6): the
  /// master replied 200 FIRST, then restarts its Wi-Fi ~400 ms later.
  /// The old token is dead everywhere. So: drop the token, give the
  /// AP time to come back, then retry a fresh login with the new
  /// password. The phone may need to rejoin the Wi-Fi in between —
  /// callers fire WifiService.join independently when the SSID is
  /// known.
  Future<void> handlePasswordChanged(
    String newPassword, {
    int attempts = 5,
    Duration delay = const Duration(seconds: 2),
  }) async {
    final current = state.value;
    final info = switch (current) {
      Authenticated(:final info) => info,
      NeedsLogin(:final info) => info,
      NeedsCommissioning(:final info) => info,
      _ => null,
    };
    ref.read(tokenProvider.notifier).set(null);
    if (info != null) await _store.deleteToken(info.uid);

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      for (var i = 0; i < attempts; i++) {
        await Future<void>.delayed(delay);
        try {
          final result = await _repo.login(newPassword);
          final freshInfo = info ?? await _repo.info();
          await _store.writeToken(freshInfo.uid, result.token);
          // Keep the stored rejoin password in step with the change.
          await _store.writePassword(freshInfo.uid, newPassword);
          ref.read(tokenProvider.notifier).set(result.token);
          return Authenticated(freshInfo, mesh: result.mesh);
        } on Unreachable {
          continue; // AP still restarting or phone still rejoining
        } on ApiFailure {
          break; // a real verdict — fall through to bootstrap
        }
      }
      return _bootstrap();
    });
  }
}
