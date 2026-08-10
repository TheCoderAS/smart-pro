import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unisync/core/api/dio_client.dart';
import 'package:unisync/core/api/endpoints.dart';
import 'package:unisync/core/api/failure.dart';

/// Replays canned responses without a network. Substituted via Dio's
/// httpClientAdapter so the real interceptor chain runs.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final String body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'no route to host',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  Dio dioWith(ProviderContainer c, HttpClientAdapter adapter) {
    final dio = c.read(dioProvider);
    dio.httpClientAdapter = adapter;
    return dio;
  }

  test('2xx passes through untouched', () async {
    final c = makeContainer();
    final dio = dioWith(c, _CannedAdapter(200, '{"ok":true}'));

    final res = await dio.get<dynamic>(Api.info);
    expect(res.statusCode, 200);
  });

  test('X-Auth header is attached when a token is set', () async {
    final c = makeContainer();
    final adapter = _CannedAdapter(200, '{}');
    final dio = dioWith(c, adapter);
    c.read(tokenProvider.notifier).set('deadbeef');

    await dio.get<dynamic>(Api.extensions);
    expect(adapter.lastRequest?.headers[Api.authHeader], 'deadbeef');
  });

  test('no X-Auth header without a token', () async {
    final c = makeContainer();
    final adapter = _CannedAdapter(200, '{}');
    final dio = dioWith(c, adapter);

    await dio.get<dynamic>(Api.info);
    expect(adapter.lastRequest?.headers.containsKey(Api.authHeader), isFalse);
  });

  test('401 maps to Unauthorized', () async {
    final c = makeContainer();
    final dio = dioWith(c, _CannedAdapter(401, '{}'));

    try {
      await dio.get<dynamic>(Api.extensions);
      fail('expected DioException');
    } on DioException catch (e) {
      expect(e.apiFailure, isA<Unauthorized>());
    }
  });

  test('423 maps to LockedOut with ~5 minute retry hint', () async {
    final c = makeContainer();
    final dio = dioWith(c, _CannedAdapter(423, '{}'));

    try {
      await dio.post<dynamic>(Api.login, data: {'password': 'wrong'});
      fail('expected DioException');
    } on DioException catch (e) {
      final failure = e.apiFailure;
      expect(failure, isA<LockedOut>());
      expect((failure as LockedOut).retryAfter, const Duration(minutes: 5));
    }
  });

  test('429 maps to RateLimited', () async {
    final c = makeContainer();
    final dio = dioWith(c, _CannedAdapter(429, '{}'));

    try {
      await dio.get<dynamic>(Api.info);
      fail('expected DioException');
    } on DioException catch (e) {
      expect(e.apiFailure, isA<RateLimited>());
    }
  });

  test('other statuses map to ServerFailure and keep the body', () async {
    final c = makeContainer();
    final dio =
        dioWith(c, _CannedAdapter(500, '{"error":"missing signature"}'));

    try {
      await dio.post<dynamic>(Api.fwUpload);
      fail('expected DioException');
    } on DioException catch (e) {
      final failure = e.apiFailure;
      expect(failure, isA<ServerFailure>());
      failure as ServerFailure;
      expect(failure.status, 500);
      expect(failure.errorMessage, 'missing signature');
    }
  });

  test('transport errors map to Unreachable', () async {
    final c = makeContainer();
    final dio = dioWith(c, _FailingAdapter());

    try {
      await dio.get<dynamic>(Api.info);
      fail('expected DioException');
    } on DioException catch (e) {
      expect(e.apiFailure, isA<Unreachable>());
    }
  });
}
