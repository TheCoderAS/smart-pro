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
