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

  /// POST /api/relay — `state` is 1/0; `ch` is the channel.
  ///
  /// The channel is derived from the id suffix (`master_1`, `ext0_2` →
  /// 1, 2), exactly as the firmware's own web UI does. The firmware
  /// *requires* a valid channel (`ch==1||ch==2`) or it 404s the relay,
  /// and the state document's channel field is named inconsistently
  /// (`channel` for local switches, `ch` for peers) — deriving it from
  /// the id is the one source of truth that always holds.
  Future<void> setRelay({
    required String id,
    required bool on,
    int? ch,
  }) async {
    final channel = _channelFromId(id) ?? ch ?? 1;
    try {
      await _dio.post<dynamic>(
        Api.relay,
        data: {
          'id': id,
          'state': on ? 1 : 0,
          'ch': channel,
        },
      );
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Parse the trailing channel from a switch id (`ext0_1` → 1). Returns
  /// null when the id has no `_<n>` suffix.
  static int? _channelFromId(String id) {
    final us = id.lastIndexOf('_');
    if (us < 0 || us == id.length - 1) return null;
    return int.tryParse(id.substring(us + 1));
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
