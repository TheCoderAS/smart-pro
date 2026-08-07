import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/log.dart';
import 'endpoints.dart';
import 'failure.dart';

/// Supplies the current session token to outgoing requests.
/// The auth feature (block 5) sets this after login / session restore;
/// null means "no token yet" and TOKEN endpoints will 401.
final tokenProvider =
    NotifierProvider<TokenNotifier, String?>(TokenNotifier.new);

class TokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? token) => state = token;
}

/// The one Dio instance for talking to the master.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Api.baseUrl,
      // The master is on the local AP — round trips are milliseconds
      // when reachable; long timeouts only delay the "unreachable"
      // verdict. Firmware uploads override these per-request.
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      // The API uses form-encoded bodies throughout (§5 examples).
      contentType: Headers.formUrlEncodedContentType,
      // Let the failure mapper see every status instead of throwing
      // inside Dio's default validator.
      validateStatus: (_) => true,
    ),
  );

  dio.interceptors.add(_AuthAndFailureInterceptor(ref));
  return dio;
});

class _AuthAndFailureInterceptor extends Interceptor {
  _AuthAndFailureInterceptor(this._ref);

  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _ref.read(tokenProvider);
    if (token != null && !options.headers.containsKey(Api.authHeader)) {
      options.headers[Api.authHeader] = token;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      handler.next(response);
      return;
    }
    // Dio auto-parses JSON bodies into maps/lists; re-encode so
    // ServerFailure always carries the raw JSON text.
    final data = response.data;
    final body = switch (data) {
      null => '',
      final String s => s,
      _ => jsonEncode(data),
    };
    final failure = switch (status) {
      401 => const Unauthorized(),
      423 => const LockedOut(),
      429 => const RateLimited(),
      _ => ServerFailure(status, body),
    };
    log.w('${response.requestOptions.path} -> ${failure.describe()}');
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: failure,
        type: DioExceptionType.badResponse,
      ),
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is ApiFailure) {
      handler.next(err);
      return;
    }
    // Transport-level problem — timeouts, refused connections, no route.
    log.w('${err.requestOptions.path} -> unreachable (${err.type})');
    handler.next(err.copyWith(error: Unreachable(err.error)));
  }
}

/// Unwraps the [ApiFailure] from a Dio call. Usage:
///
/// ```dart
/// try {
///   final res = await dio.post(Api.login, data: {'password': pw});
/// } on DioException catch (e) {
///   throw e.apiFailure; // always an ApiFailure
/// }
/// ```
extension ApiFailureX on DioException {
  ApiFailure get apiFailure =>
      error is ApiFailure ? error! as ApiFailure : Unreachable(error);
}
