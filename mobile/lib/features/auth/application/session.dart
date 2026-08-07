import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/failure.dart';
import '../../../core/logging/log.dart';
import '../../../core/storage/secure_store.dart';
import '../data/auth_repository.dart';
import '../domain/models.dart';

/// Where the app stands with the master it is pointed at.
///
/// The lifecycle (bootstrap):
///   probing → unreachable            can't open 192.168.4.1
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
    final DeviceInfo info;
    try {
      info = await _repo.info();
    } on Unreachable {
      return const MasterUnreachable();
    }

    if (!info.auth) {
      // Factory-fresh master: API open until an owner password is set.
      return NeedsCommissioning(info);
    }

    final stored = await _store.readToken(info.uid);
    if (stored == null) return NeedsLogin(info);

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
