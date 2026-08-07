// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'firmware_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FirmwareManifest _$FirmwareManifestFromJson(Map<String, dynamic> json) =>
    _FirmwareManifest(
      type: (json['type'] as num).toInt(),
      version: json['version'] as String,
      sec: (json['sec'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
      sig: json['sig'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );

Map<String, dynamic> _$FirmwareManifestToJson(_FirmwareManifest instance) =>
    <String, dynamic>{
      'type': instance.type,
      'version': instance.version,
      'sec': instance.sec,
      'size': instance.size,
      'sig': instance.sig,
      'url': instance.url,
    };

_StoredImage _$StoredImageFromJson(Map<String, dynamic> json) => _StoredImage(
  type: (json['type'] as num?)?.toInt() ?? 0,
  version: json['version'] as String? ?? '',
  size: (json['size'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$StoredImageToJson(_StoredImage instance) =>
    <String, dynamic>{
      'type': instance.type,
      'version': instance.version,
      'size': instance.size,
    };
