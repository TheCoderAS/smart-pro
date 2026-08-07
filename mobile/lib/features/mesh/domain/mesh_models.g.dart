// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mesh_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MeshStatus _$MeshStatusFromJson(Map<String, dynamic> json) => _MeshStatus(
  active: json['active'] as bool? ?? false,
  meshName: json['mesh_name'] as String? ?? '',
  peerCount: (json['peer_count'] as num?)?.toInt() ?? 0,
  fw: json['fw'] as String? ?? '',
  syncing: json['syncing'] as bool? ?? false,
  credStale: json['cred_stale'] as bool? ?? false,
  peers:
      (json['peers'] as List<dynamic>?)
          ?.map((e) => MeshPeer.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MeshPeer>[],
);

Map<String, dynamic> _$MeshStatusToJson(_MeshStatus instance) =>
    <String, dynamic>{
      'active': instance.active,
      'mesh_name': instance.meshName,
      'peer_count': instance.peerCount,
      'fw': instance.fw,
      'syncing': instance.syncing,
      'cred_stale': instance.credStale,
      'peers': instance.peers,
    };

_MeshPeer _$MeshPeerFromJson(Map<String, dynamic> json) => _MeshPeer(
  name: json['name'] as String? ?? '',
  fw: json['fw'] as String? ?? '',
  credStale: json['cred_stale'] as bool? ?? false,
);

Map<String, dynamic> _$MeshPeerToJson(_MeshPeer instance) => <String, dynamic>{
  'name': instance.name,
  'fw': instance.fw,
  'cred_stale': instance.credStale,
};

_MeshInvite _$MeshInviteFromJson(Map<String, dynamic> json) => _MeshInvite(
  mac: json['mac'] as String? ?? '',
  pin: json['pin'] as String? ?? '',
);

Map<String, dynamic> _$MeshInviteToJson(_MeshInvite instance) =>
    <String, dynamic>{'mac': instance.mac, 'pin': instance.pin};
