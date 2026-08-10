import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/ws/state_dto.dart' show Presence;

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
    /// Stable identity. The mesh screen keys removal on this, never on the
    /// name — names are user-changeable.
    @Default('') String uid,
    @Default('') String name,
    @Default('') String fw,
    @Default(true) bool online,

    /// Debounced presence from the master, same rule as extensions.
    @JsonKey(name: 'presence') @Default('online') String presenceRaw,

    /// Seconds since the mesh last heard from this master.
    @JsonKey(name: 'last_seen') @Default(0) int lastSeen,
    @JsonKey(name: 'cred_stale') @Default(false) bool credStale,
  }) = _MeshPeer;

  const MeshPeer._();

  Presence get presence => Presence.parse(presenceRaw);

  /// A master can only be removed while it is reachable: removal requires
  /// it to delete its own mesh credentials and say so.
  bool get removable => presence == Presence.online;

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
