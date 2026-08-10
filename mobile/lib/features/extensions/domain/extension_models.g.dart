// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'extension_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ExtensionInfo _$ExtensionInfoFromJson(Map<String, dynamic> json) =>
    _ExtensionInfo(
      slot: (json['slot'] as num).toInt(),
      addr: (json['addr'] as num?)?.toInt() ?? 0,
      online: json['online'] as bool? ?? false,
      type: (json['type'] as num?)?.toInt() ?? 0,
      rev: (json['rev'] as num?)?.toInt() ?? 0,
      fw: json['fw'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sw1: json['sw1'] as String? ?? '',
      sw2: json['sw2'] as String? ?? '',
      fails: (json['fails'] as num?)?.toInt() ?? 0,
      stuck: json['stuck'] as bool? ?? false,
      avail: json['avail'] as String?,
      presenceRaw: json['presence'] as String? ?? 'online',
      lastSeen: (json['last_seen'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ExtensionInfoToJson(_ExtensionInfo instance) =>
    <String, dynamic>{
      'slot': instance.slot,
      'addr': instance.addr,
      'online': instance.online,
      'type': instance.type,
      'rev': instance.rev,
      'fw': instance.fw,
      'name': instance.name,
      'sw1': instance.sw1,
      'sw2': instance.sw2,
      'fails': instance.fails,
      'stuck': instance.stuck,
      'avail': instance.avail,
      'presence': instance.presenceRaw,
      'last_seen': instance.lastSeen,
    };
