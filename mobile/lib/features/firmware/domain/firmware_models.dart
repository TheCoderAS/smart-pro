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
    /// Optional release notes from the CDN manifest (BLE spec v2 §7 —
    /// the master stores no changelog). Rendered when present.
    @Default('') String changelog,
  }) = _FirmwareManifest;

  const FirmwareManifest._();

  /// Type 0 is the master's own image. Everything else is an extension
  /// image, matched to boards by type.
  bool get isMaster => type == 0;

  factory FirmwareManifest.fromJson(Map<String, dynamic> json) =>
      _$FirmwareManifestFromJson(json);
}

/// One image already in the master's signed library (GET /api/fw/list or
/// BLE `fwlist`). Shape is tolerant — the list endpoint's exact fields
/// are firmware-defined. Over BLE the version key is `ver`; over HTTP it
/// is `version`, so both are accepted.
@freezed
abstract class StoredImage with _$StoredImage {
  const factory StoredImage({
    @Default(0) int type,
    @JsonKey(name: 'version', readValue: _readVersion)
    @Default('')
    String version,
    @Default(0) int size,
  }) = _StoredImage;

  factory StoredImage.fromJson(Map<String, dynamic> json) =>
      _$StoredImageFromJson(json);
}

Object? _readVersion(Map<dynamic, dynamic> json, String key) =>
    json['version'] ?? json['ver'];

/// The master's firmware picture over one transport: its own running
/// version plus the images already staged in its library (BLE spec v2
/// §fwlist / HTTP GET /api/fw/list + /api/info).
@freezed
abstract class FwStatus with _$FwStatus {
  const factory FwStatus({
    @Default('') String master,
    @Default(<StoredImage>[]) List<StoredImage> images,
  }) = _FwStatus;

  factory FwStatus.fromJson(Map<String, dynamic> json) =>
      _$FwStatusFromJson(json);
}
