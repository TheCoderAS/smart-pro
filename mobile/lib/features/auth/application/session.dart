import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/failure.dart';
import '../../../core/logging/log.dart';
import '../../../core/storage/master_registry.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/transport/control_transport.dart';
import '../../../core/transport/transport_manager.dart';
import '../../onboarding/application/first_run.dart';
import '../../settings/application/master_switch.dart';
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

    final DeviceInfo info;
    try {
      info = await _repo.info();
    } on Unreachable {
      // Off the master's Wi-Fi. If the user prefers Bluetooth and we
      // have a saved token, open the dashboard over BLE instead of
      // dead-ending on the unreachable screen. Guarded so a plain
      // unreachable bootstrap (and the tests) still fall through.
      try {
        if (await _blePreferred()) {
          final ble = await _bleSession();
          if (ble != null) return ble;
        }
      } on Object catch (e) {
        log.w('ble auto-start skipped: $e');
      }
      return const MasterUnreachable();
    }

    if (!info.auth) {
      // Factory-fresh master: API open until an owner password is set.
      return NeedsCommissioning(info);
    }

    // The app opens on the last-used master, subject to the same checks as
    // any switch. Something else answering means the phone is on another
    // master's network — say which one to join rather than quietly opening
    // a dashboard the user didn't ask for.
    //
    // Ahead of the token check on purpose: we have no session for a master
    // we aren't talking to, and showing a login form for that would be the
    // exact mix-up the story calls a bug. Only when more than one master
    // is set up; with one, whoever answers is the one.
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

  /// [WrongNetwork] when a master answered that isn't the one the app was
  /// last on, or null to carry on with whoever did answer.
  Future<WrongNetwork?> _wrongMasterAnswered(String answeredUid) async {
    try {
      final masters = await ref.read(masterRegistryProvider.future);
      if (masters.length < 2) return null;
      final lastUid =
          await ref.read(masterRegistryProvider.notifier).lastUsed();
      if (lastUid == null || lastUid == answeredUid) return null;
      for (final m in masters) {
        if (m.uid != lastUid) continue;
        // Meshed masters are one home: any member answering is the right
        // answer, and the vault keys them on a shared mesh id.
        final answered = masters.where((x) => x.uid == answeredUid);
        if (answered.isNotEmpty &&
            m.meshId != null &&
            m.meshId != 0 &&
            answered.first.meshId == m.meshId) {
          return null;
        }
        final name = answered.isEmpty ? null : answered.first.name;
        return WrongNetwork(wanted: m, found: name);
      }
    } on Object catch (e) {
      log.w('last-used check skipped: $e');
    }
    return null;
  }

  /// Attempts a login. On success persists the token (keyed by master
  /// UID) and flips to [Authenticated]; on failure lands in
  /// [NeedsLogin] with the failure attached.
  Future<void> login(String password) async {
    final current = state.value;
    final info = switch (current) {
      NeedsLogin(:final info) => info,
      Authenticated(:final info) => info,
      NeedsCommissioning(:final info) => info,
      _ => null,
    };
    if (info == null) {
      // No device context — re-bootstrap instead.
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(_bootstrap);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      try {
        final result = await _repo.login(password);
        await _store.writeToken(info.uid, result.token);
        ref.read(tokenProvider.notifier).set(result.token);
        return Authenticated(info, mesh: result.mesh);
      } on ApiFailure catch (e) {
        return NeedsLogin(info, failure: e);
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
    final cand = await _bleCandidate();
    if (cand == null) return null;
    ref.read(tokenProvider.notifier).set(cand.token);
    await ref
        .read(transportPreferenceProvider.notifier)
        .set(TransportPreference.bluetooth);
    // fw is unknown until a BLE state push arrives; uid comes from the
    // saved registry.
    return Authenticated(
      DeviceInfo(uptime: 0, freeHeap: 0, uid: cand.uid, fw: '—', auth: true),
      mesh: false,
    );
  }

  /// A saved master we can drive over Bluetooth — one with a stored
  /// token, preferring the last-used master. Null when nothing is
  /// paired or no token is stored.
  Future<({String uid, int? meshId, String token})?> _bleCandidate() async {
    final masters = await ref.read(masterRegistryProvider.future);
    if (masters.isEmpty) return null;
    final lastUid = await ref.read(masterRegistryProvider.notifier).lastUsed();
    final ordered = [
      ...masters.where((m) => m.uid == lastUid),
      ...masters.where((m) => m.uid != lastUid),
    ];
    for (final m in ordered) {
      final token = await _store.readToken(m.uid);
      if (token != null) {
        return (uid: m.uid, meshId: m.meshId, token: token);
      }
    }
    return null;
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
    state = AsyncValue.data(NeedsLogin(current.info));
  }

  /// Re-probes the master — pull-to-refresh on the unreachable screen,
  /// and the re-entry point after a password-change reconnect.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_bootstrap);
  }

  /// Switches the app to another saved master.
  ///
  /// Identity is settled by a uid probe before anything is shown, so the
  /// user never lands on a dashboard that belongs to a different master,
  /// and never sees a login prompt for what is really a network problem.
  /// Last-used only moves on a successful arrival — a failed switch must
  /// not change where the app opens next time.
  Future<void> switchTo(SavedMaster target) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final outcome = await ref.read(masterSwitchProvider).switchTo(target);
      switch (outcome) {
        case SwitchWrongNetwork(:final target, :final foundName):
          return WrongNetwork(wanted: target, found: foundName);
        case SwitchUnreachable():
          return const MasterUnreachable();
        case SwitchArrived():
          final arrived = await _bootstrap();
          if (arrived is Authenticated) {
            await ref
                .read(masterRegistryProvider.notifier)
                .setLastUsed(target.uid);
          }
          return arrived;
      }
    });
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
