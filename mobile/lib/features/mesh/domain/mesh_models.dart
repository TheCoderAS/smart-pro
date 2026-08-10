import 'package:freezed_annotation/freezed_annotation.dart';

part 'mesh_models.freezed.dart';
part 'mesh_models.g.dart';

/// GET /api/mesh/status (API §5). `credStale: true` on this master
/// means it missed a password change while offline and cannot
/// self-heal — the required action is "remove and re-add this master".
@freezed
abstract class MeshStatus with _$MeshStatus {
  const factory MeshStatus({
    @Default(false) bool active,
    @JsonKey(name: 'mesh_name') @Default('') String meshName,
    @JsonKey(name: 'peer_count') @Default(0) int peerCount,
    @Default('') String fw,
    @Default(false) bool syncing,
    @JsonKey(name: 'cred_stale') @Default(false) bool credStale,
    @Default(<MeshPeer>[]) List<MeshPeer> peers,
  }) = _MeshStatus;

  factory MeshStatus.fromJson(Map<String, dynamic> json) =>
      _$MeshStatusFromJson(json);
}

@freezed
abstract class MeshPeer with _$MeshPeer {
  const factory MeshPeer({
    @Default('') String name,
    @Default('') String fw,
    @JsonKey(name: 'cred_stale') @Default(false) bool credStale,
  }) = _MeshPeer;

  factory MeshPeer.fromJson(Map<String, dynamic> json) =>
      _$MeshPeerFromJson(json);
}

/// POST /api/mesh/invite — the mac/pin pair the joining master needs.
@freezed
abstract class MeshInvite with _$MeshInvite {
  const factory MeshInvite({
    @Default('') String mac,
    @Default('') String pin,
  }) = _MeshInvite;

  factory MeshInvite.fromJson(Map<String, dynamic> json) =>
      _$MeshInviteFromJson(json);
}
