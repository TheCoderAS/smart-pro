// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => _DeviceInfo(
  uptime: (json['uptime'] as num).toInt(),
  freeHeap: (json['free_heap'] as num).toInt(),
  uid: json['uid'] as String,
  fw: json['fw'] as String,
  auth: json['auth'] as bool,
);

Map<String, dynamic> _$DeviceInfoToJson(_DeviceInfo instance) =>
    <String, dynamic>{
      'uptime': instance.uptime,
      'free_heap': instance.freeHeap,
      'uid': instance.uid,
      'fw': instance.fw,
      'auth': instance.auth,
    };

_LoginResult _$LoginResultFromJson(Map<String, dynamic> json) =>
    _LoginResult(token: json['token'] as String, mesh: json['mesh'] as bool);

Map<String, dynamic> _$LoginResultToJson(_LoginResult instance) =>
    <String, dynamic>{'token': instance.token, 'mesh': instance.mesh};
