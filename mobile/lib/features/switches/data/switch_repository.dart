import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/endpoints.dart';

final switchRepositoryProvider = Provider<SwitchRepository>((ref) {
  return SwitchRepository(ref.watch(dioProvider));
});

/// Transport for the switch endpoints (API §5 "Switches"). Fire the
/// command; the authoritative result arrives as the next WebSocket
/// snapshot — callers do optimistic UI and reconcile from there.
class SwitchRepository {
  const SwitchRepository(this._dio);

  final Dio _dio;

  /// POST /api/relay — `state` is 1/0; `ch` for multi-channel units.
  Future<void> setRelay({
    required String id,
    required bool on,
    int? ch,
  }) async {
    try {
      await _dio.post<dynamic>(
        Api.relay,
        data: {
          'id': id,
          'state': on ? 1 : 0,
          'ch': ?ch,
        },
      );
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// POST /api/relay/killall — everything off, everywhere.
  Future<void> killAll() async {
    try {
      await _dio.post<dynamic>(Api.relayKillAll);
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  Future<void> rename({required String id, required String name}) async {
    try {
      await _dio.post<dynamic>(
        Api.switchRename,
        data: {'id': id, 'name': name},
      );
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// POST /api/switch/reorder — `plain` is the comma-separated id
  /// order.
  Future<void> reorder(List<String> orderedIds) async {
    try {
      await _dio.post<dynamic>(
        Api.switchReorder,
        data: {'plain': orderedIds.join(',')},
      );
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }
}
