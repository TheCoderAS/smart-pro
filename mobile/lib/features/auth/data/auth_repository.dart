import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/failure.dart';
import '../domain/models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});

/// Thin transport for the auth endpoints. Throws [ApiFailure] (via
/// DioException.apiFailure) — policy lives in the session notifier.
class AuthRepository {
  const AuthRepository(this._dio);

  final Dio _dio;

  /// Open endpoint; also the reachability probe.
  Future<DeviceInfo> info() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Api.info);
      return DeviceInfo.fromJson(res.data!);
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  Future<LoginResult> login(String password) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Api.login,
        data: {'password': password},
      );
      return LoginResult.fromJson(res.data!);
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Server-side no-op (API §2) — fired best-effort so the audit log
  /// records the sign-out; local token disposal is what matters.
  Future<void> logout() async {
    try {
      await _dio.post<dynamic>(Api.logout);
    } on DioException {
      // Ignoring by design: sign-out must succeed even off-network.
    }
  }

  /// Sets the owner password. On a factory-fresh master the API is
  /// open (ops guide §A2/A3), so this needs no token; afterwards every
  /// TOKEN endpoint closes and login() is required. On an owned master
  /// the X-Auth interceptor supplies the token automatically and the
  /// API §6 reconnect dance applies to the caller.
  /// Changes the password, but only once the current one is proven.
  ///
  /// `/api/password` is token-authenticated and takes no `old`, so the
  /// proof is a login with what the user typed — the one endpoint that
  /// checks a password against the credential actually in force (in a
  /// mesh, the mesh's rather than this box's).
  ///
  /// Separate and public so the order is testable on its own: nothing is
  /// changed unless [current] is right. A wrong one throws [Unauthorized]
  /// and [setPassword] is never reached.
  ///
  /// Cost, named because it is real: five wrong entries lock *new*
  /// sign-ins for five minutes (AUTH_MAX_FAILS / AUTH_LOCKOUT_MS in the
  /// firmware). It cannot strand anyone — the master's token check never
  /// consults that lock, so the session in hand keeps working — and a
  /// correct entry resets the counter before anything changes.
  Future<void> changePasswordVerified({
    required String current,
    required String fresh,
  }) async {
    await login(current);
    await setPassword(fresh);
  }

  Future<void> setPassword(String password) async {
    try {
      await _dio.post<dynamic>(
        Api.password,
        data: {'password': password},
      );
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Renames the master (POST /api/master/rename, TOKEN). Wi-Fi-only —
  /// BLE cannot rename (spec v2 §9).
  Future<void> renameMaster(String name) async {
    try {
      await _dio.post<dynamic>(Api.masterRename, data: {'name': name});
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Cheapest TOKEN-authed call — used to validate a restored token.
  /// Returns true when the token is accepted.
  Future<bool> validateToken() async {
    try {
      await _dio.get<dynamic>(Api.extensions);
      return true;
    } on DioException catch (e) {
      final failure = e.apiFailure;
      if (failure is Unauthorized) return false;
      throw failure;
    }
  }
}
