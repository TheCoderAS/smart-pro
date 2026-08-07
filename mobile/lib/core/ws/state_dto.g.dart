// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StateSnapshot _$StateSnapshotFromJson(Map<String, dynamic> json) =>
    _StateSnapshot(
      masterName: json['master_name'] as String? ?? '',
      uptime: (json['uptime'] as num?)?.toInt() ?? 0,
      bootComplete: json['boot_complete'] as bool? ?? true,
      scanActive: json['scan_active'] as bool? ?? false,
      switches:
          (json['switches'] as List<dynamic>?)
              ?.map((e) => SwitchState.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <SwitchState>[],
      peers:
          (json['peers'] as List<dynamic>?)
              ?.map((e) => PeerState.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <PeerState>[],
    );

Map<String, dynamic> _$StateSnapshotToJson(_StateSnapshot instance) =>
    <String, dynamic>{
      'master_name': instance.masterName,
      'uptime': instance.uptime,
      'boot_complete': instance.bootComplete,
      'scan_active': instance.scanActive,
      'switches': instance.switches,
      'peers': instance.peers,
    };

_SwitchState _$SwitchStateFromJson(Map<String, dynamic> json) => _SwitchState(
  id: json['id'] as String? ?? '',
  name: json['name'] as String? ?? '',
  on: json['on'] as bool? ?? false,
  ch: (json['ch'] as num?)?.toInt() ?? 0,
  online: json['online'] as bool? ?? true,
);

Map<String, dynamic> _$SwitchStateToJson(_SwitchState instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'on': instance.on,
      'ch': instance.ch,
      'online': instance.online,
    };

_PeerState _$PeerStateFromJson(Map<String, dynamic> json) => _PeerState(
  uid: json['uid'] as String? ?? '',
  name: json['name'] as String? ?? '',
  fw: json['fw'] as String? ?? '',
  online: json['online'] as bool? ?? true,
);

Map<String, dynamic> _$PeerStateToJson(_PeerState instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'name': instance.name,
      'fw': instance.fw,
      'online': instance.online,
    };
