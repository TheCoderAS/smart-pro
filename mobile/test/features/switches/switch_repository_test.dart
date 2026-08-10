import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:unisync/core/api/endpoints.dart';
import 'package:unisync/features/switches/data/switch_repository.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late SwitchRepository repo;

  setUp(() {
    dio = MockDio();
    repo = SwitchRepository(dio);
    when(() => dio.post<dynamic>(any(), data: any(named: 'data')))
        .thenAnswer((_) async => Response<dynamic>(
              requestOptions: RequestOptions(path: Api.relay),
              statusCode: 200,
            ));
  });

  Map<String, dynamic> capturedRelayBody() {
    final call = verify(
      () => dio.post<dynamic>(Api.relay, data: captureAny(named: 'data')),
    )..called(1);
    return call.captured.single as Map<String, dynamic>;
  }

  // The firmware requires a valid channel (ch==1||ch==2) on /api/relay or
  // it 404s — the channel must come from the id suffix, never default to 0.
  test('derives ch=1 from a _1 id and sends state=1 for on', () async {
    await repo.setRelay(id: 'master_1', on: true);
    final body = capturedRelayBody();
    expect(body['id'], 'master_1');
    expect(body['ch'], 1);
    expect(body['state'], 1);
  });

  test('derives ch=2 from a _2 id and sends state=0 for off', () async {
    await repo.setRelay(id: 'ext0_2', on: false);
    final body = capturedRelayBody();
    expect(body['id'], 'ext0_2');
    expect(body['ch'], 2);
    expect(body['state'], 0);
  });

  test('id suffix wins over a stale ch argument', () async {
    // Even if a caller passes ch:0 (the old bug), the id decides.
    await repo.setRelay(id: 'ext3_2', on: true, ch: 0);
    expect(capturedRelayBody()['ch'], 2);
  });
}
