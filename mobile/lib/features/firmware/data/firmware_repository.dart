import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/endpoints.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/firmware_models.dart';

/// Where the app looks for published firmware. // TODO(unisync):
/// confirm the production manifest URL (open question #2 in PLAN.md).
const firmwareManifestUrl = 'https://cdn.unisync.in/firmware/index.json';

/// Separate Dio for the CDN: HTTPS, no X-Auth, no 192.168.4.1 base.
/// NOTE: while the phone is glued to the master's AP there is no
/// internet route — manifest fetch and image download only work when
/// the phone has connectivity elsewhere (cellular or another Wi-Fi).
/// The UI treats CDN unreachability as normal, not an error.
final cdnDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 2),
    ),
  );
});

final firmwareRepositoryProvider = Provider<FirmwareRepository>((ref) {
  return FirmwareRepository(
    ref.watch(dioProvider),
    ref.watch(cdnDioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class FirmwareRepository {
  const FirmwareRepository(this._device, this._cdn, this._auth);

  final Dio _device;
  final Dio _cdn;
  final AuthRepository _auth;

  /// Published images, newest first per type.
  Future<List<FirmwareManifest>> fetchManifests() async {
    final res = await _cdn.get<List<dynamic>>(firmwareManifestUrl);
    return [
      for (final e in res.data ?? const <dynamic>[])
        if (e is Map<String, dynamic>) FirmwareManifest.fromJson(e),
    ];
  }

  /// Downloads an image, reporting progress 0..1.
  Future<Uint8List> download(
    FirmwareManifest manifest, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final res = await _cdn.get<List<int>>(
      manifest.url,
      options: Options(responseType: ResponseType.bytes),
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
    final bytes = Uint8List.fromList(res.data ?? const []);
    if (manifest.size > 0 && bytes.length != manifest.size) {
      throw StateError(
        'size mismatch: manifest ${manifest.size}, got ${bytes.length}',
      );
    }
    return bytes;
  }

  /// Images already stored in the master's signed library.
  Future<List<StoredImage>> storedImages() async {
    try {
      final res = await _device.get<Map<String, dynamic>>(Api.fwList);
      final raw = res.data?['images'] ?? res.data?['list'];
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map<String, dynamic>) StoredImage.fromJson(e),
      ];
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Relays a signed extension image to the master (API §7).
  /// `mesh: true` also offers it to peer masters. After 200 the
  /// rollout is automatic — each master updates matching switches
  /// within ~30 s, one at a time; poll /api/extensions and watch `fw`.
  Future<void> uploadExtensionImage({
    required FirmwareManifest manifest,
    required Uint8List bytes,
    bool mesh = true,
  }) async {
    final form = FormData.fromMap({
      'firmware': MultipartFile.fromBytes(
        bytes,
        filename: 'ext_t${manifest.type}_${manifest.version}.bin',
      ),
      'sig': manifest.sig,
      'sec': manifest.sec,
    });
    try {
      await _device.post<dynamic>(
        '${Api.fwUpload}?mesh=${mesh ? 1 : 0}',
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Master OTA (API §7). Master images are NOT signature-checked in
  /// firmware — secure boot decides at the next boot, so a 200 here
  /// proves nothing. [confirmMasterVersion] is the real verdict.
  Future<void> uploadMasterImage(Uint8List bytes) async {
    final form = FormData.fromMap({
      'firmware': MultipartFile.fromBytes(bytes, filename: 'master.bin'),
    });
    try {
      await _device.post<dynamic>(
        Api.otaMaster,
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    } on DioException catch (e) {
      throw e.apiFailure;
    }
  }

  /// Polls /api/info until the master answers again after its reboot,
  /// then reports the running firmware version. Compare with the
  /// uploaded version: unchanged means secure boot rejected the image
  /// (API §7 "always confirm with /api/info, not the upload
  /// response").
  Future<String> confirmMasterVersion({
    int attempts = 30,
    Duration delay = const Duration(seconds: 2),
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      await Future<void>.delayed(delay);
      try {
        final info = await _auth.info();
        return info.fw;
      } on Exception catch (e) {
        lastError = e;
      }
    }
    throw StateError('master did not come back: $lastError');
  }
}
