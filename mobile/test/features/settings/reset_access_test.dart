import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/api/failure.dart';
import 'package:unisync/features/auth/data/auth_repository.dart';

/// Changing the password proves the current one first.
///
/// `/api/password` is token-authenticated and takes no `old`, so the
/// proof is a login with what the user typed — the one endpoint that
/// checks a password against the credential actually in force. The rule
/// that matters is the ORDER: nothing is changed unless that login
/// succeeds, so these assert on what reached the wire.
class _Recorder extends Interceptor {
  final calls = <String>[];
  /// What the real client's error interceptor would have produced for
  /// this login. Set it to reject; null lets the login succeed. Mapping
  /// status codes to failures is that interceptor's job and its own
  /// tests' — this file is about the ORDER of the two calls.
  ApiFailure? loginFails;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls.add(options.path);
    if (options.path.endsWith('/login')) {
      final fail = loginFails;
      if (fail != null) {
        handler.reject(
          DioException(requestOptions: options, error: fail),
        );
        return;
      }
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const {'token': 'tok', 'mesh': false},
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: const {'ok': true},
      ),
    );
  }
}

void main() {
  late Dio dio;
  late _Recorder rec;
  late AuthRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://192.168.4.1'));
    rec = _Recorder();
    dio.interceptors.add(rec);
    repo = AuthRepository(dio);
  });

  test('the wrong current password changes nothing', () async {
    rec.loginFails = const Unauthorized();

    Object? thrown;
    try {
      await repo.changePasswordVerified(
        current: 'wrong',
        fresh: 'brand-new-pass',
      );
    } on Object catch (e) {
      thrown = e;
    }
    expect(thrown, isA<Unauthorized>());

    // The whole point: the credential was never touched.
    expect(rec.calls.where((p) => p.contains('password')), isEmpty);
  });

  test('the right one lets the change through, in that order', () async {
    await repo.changePasswordVerified(
      current: 'the-real-one',
      fresh: 'brand-new-pass',
    );

    expect(rec.calls, hasLength(2));
    expect(rec.calls.first, endsWith('/login'));
    expect(rec.calls.last, endsWith('/password'));
  });

  test('a lockout stops the change too, and says so', () async {
    // Five wrong tries lock new sign-ins for five minutes. It cannot
    // strand anyone — the master's token check never consults that lock —
    // but it must not be mistaken for a wrong password.
    rec.loginFails = const LockedOut();

    Object? thrown;
    try {
      await repo.changePasswordVerified(
        current: 'wrong',
        fresh: 'brand-new-pass',
      );
    } on Object catch (e) {
      thrown = e;
    }
    expect(thrown, isA<LockedOut>());
    expect(rec.calls.where((p) => p.contains('password')), isEmpty);
  });
}
