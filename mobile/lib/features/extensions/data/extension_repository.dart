import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/endpoints.dart';
import '../domain/extension_models.dart';

final extensionRepositoryProvider = Provider<ExtensionRepository>((ref) {
  return ExtensionRepository(ref.watch(dioProvider));
});

/// Refreshable extension list. Screens watch this; mutations below
/// invalidate it so the list re-fetches.
final extensionsProvider =
    AsyncNotifierProvider<ExtensionsNotifier, List<ExtensionInfo>>(
  ExtensionsNotifier.new,
);

class ExtensionsNotifier extends AsyncNotifier<List<ExtensionInfo>> {
  @override
  Future<List<ExtensionInfo>> build() {
    return ref.watch(extensionRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(extensionRepositoryProvider).list(),
    );
  }
}

class ExtensionRepository {
  const ExtensionRepository(this._dio);

  final Dio _dio;

  Future<List<ExtensionInfo>> list() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Api.extensions);
      final raw = res.data?['extensions'];
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map<String, dynamic>) ExtensionInfo.fromJson(e),
      ];
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Pair a newly advertising extension into the mesh (API §5).
  Future<void> assign({required String uid, required String name}) =>
      _post(Api.assign, {'uid': uid, 'name': name});

  /// Decline a pending extension.
  Future<void> reject({required String uid}) =>
      _post(Api.reject, {'uid': uid});

  /// Swap new hardware into an existing slot, keeping its config.
  Future<void> replace({
    required String uid,
    required int slot,
    required String name,
  }) =>
      _post(Api.replace, {'uid': uid, 'slot': slot, 'name': name});

  Future<void> rename({required int slot, required String name}) =>
      _post(Api.rename, {'slot': slot, 'name': name});

  Future<void> remove({required int slot}) =>
      _post(Api.remove, {'slot': slot});

  Future<void> _post(String path, Map<String, Object?> data) async {
    try {
      await _dio.post<dynamic>(path, data: data);
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }
}
