import 'package:freezed_annotation/freezed_annotation.dart';

part 'firmware_models.freezed.dart';
part 'firmware_models.g.dart';

/// One entry of the CDN manifest (API §7). The image itself is signed
/// offline with the firmware key — the app relays `sig` unchanged and
/// the master verifies; the CDN never needs to be trusted.
@freezed
abstract class FirmwareManifest with _$FirmwareManifest {
  const factory FirmwareManifest({
    required int type,
    required String version,
    @Default(0) int sec,
    @Default(0) int size,
    @Default('') String sig,
    @Default('') String url,
  }) = _FirmwareManifest;

  factory FirmwareManifest.fromJson(Map<String, dynamic> json) =>
      _$FirmwareManifestFromJson(json);
}

/// One image already in the master's signed library (GET /api/fw/list).
/// Shape is tolerant — the list endpoint's exact fields are
/// firmware-defined.
@freezed
abstract class StoredImage with _$StoredImage {
  const factory StoredImage({
    @Default(0) int type,
    @Default('') String version,
    @Default(0) int size,
  }) = _StoredImage;

  factory StoredImage.fromJson(Map<String, dynamic> json) =>
      _$StoredImageFromJson(json);
}
