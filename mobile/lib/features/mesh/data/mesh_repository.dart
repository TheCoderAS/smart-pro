import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/transport/transport_manager.dart';
import '../domain/mesh_models.dart';

final meshRepositoryProvider = Provider<MeshRepository>((ref) {
  return MeshRepository(ref.watch(dioProvider));
});

final meshStatusProvider =
    AsyncNotifierProvider<MeshStatusNotifier, MeshStatus>(
  MeshStatusNotifier.new,
);

/// Read through the active transport, not straight off [MeshRepository].
///
/// The Mesh screen renders nothing until this resolves, so while it went
/// over HTTP the screen could not load at all in Bluetooth mode — and the
/// Leave and Remove buttons it carries never appeared, however well the
/// commands behind them worked. Fitting the doors is not the same as
/// opening the room.
class MeshStatusNotifier extends AsyncNotifier<MeshStatus> {
  @override
  Future<MeshStatus> build() {
    // watch, so flipping transport re-reads from the one now in force.
    return ref.watch(activeControlProvider).meshStatus();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(activeControlProvider).meshStatus(),
    );
  }
}

class MeshRepository {
  const MeshRepository(this._dio);

  final Dio _dio;

  Future<MeshStatus> status() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Api.meshStatus);
      return MeshStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Standalone → mesh; this master becomes the first member.
  ///
  /// The password is the user's choice and becomes both the mesh Wi-Fi
  /// key and the login for the whole home (v5.1 Epic 7). Firmware
  /// requires at least 8 characters.
  Future<void> create({required String name, required String pass}) =>
      _post(Api.meshCreate, {'name': name, 'pass': pass});

  /// Run on a master already in the mesh; yields the mac/pin the
  /// joining master enters.
  Future<MeshInvite> invite() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(Api.meshInvite);
      return MeshInvite.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Run on the joining master with the invite's mac/pin.
  Future<void> join({required String mac, required String pin}) =>
      _post(Api.meshJoin, {'mac': mac, 'pin': pin});

  /// Restores the device password (API §1).
  Future<void> leave() => _post(Api.meshLeave, const {});

  /// Remove another master from the mesh, by uid.
  ///
  /// The master must be reachable: it deletes its own mesh credentials and
  /// acknowledges before this resolves, so a success here means the removal
  /// actually happened. The firmware refuses an offline target (409) rather
  /// than leaving the app to report a removal that didn't occur.
  Future<void> kick({required String uid}) =>
      _post(Api.meshKick, {'uid': uid});

  Future<void> rename({required String name}) =>
      _post(Api.meshRename, {'name': name});

  /// Advanced per-peer admin (API §5).
  Future<void> config({
    required String cmd,
    required String targetUid,
    Map<String, Object?> extra = const {},
  }) =>
      _post(Api.meshConfig, {'cmd': cmd, 'target_uid': targetUid, ...extra});

  Future<void> _post(String path, Map<String, Object?> data) async {
    try {
      await _dio.post<dynamic>(path, data: data);
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }
}
