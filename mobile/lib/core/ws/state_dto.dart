import 'package:freezed_annotation/freezed_annotation.dart';

part 'state_dto.freezed.dart';
part 'state_dto.g.dart';

/// The full state document the master pushes on connect and on every
/// change (API §4). Every message REPLACES local state wholesale —
/// never merged — because after a silent roam a different master with
/// different local switches may be answering (API §3).
///
/// Parsing is deliberately tolerant (defaults on every field): the
/// exact switch/peer array shapes are firmware-defined and the app
/// must survive fields it doesn't know. Contract tests pin the shapes
/// we rely on.
@freezed
abstract class StateSnapshot with _$StateSnapshot {
  const factory StateSnapshot({
    @JsonKey(name: 'master_name') @Default('') String masterName,
    @Default(0) int uptime,
    @JsonKey(name: 'boot_complete') @Default(true) bool bootComplete,
    @JsonKey(name: 'scan_active') @Default(false) bool scanActive,
    @Default(<SwitchState>[]) List<SwitchState> switches,
    @JsonKey(name: 'mesh_peers')
    @Default(<PeerState>[])
    List<PeerState> peers,
  }) = _StateSnapshot;

  factory StateSnapshot.fromJson(Map<String, dynamic> json) =>
      _$StateSnapshotFromJson(json);
}

/// One relay/switch as reported in the snapshot's switch array.
/// `id` is the wire identifier used by POST /api/relay (e.g. "ext0_1").
///
/// Wire-key note: the firmware's state document names the boolean
/// `state` and the channel `channel` (see master_v2 `build_state_json`).
/// The POST /api/relay endpoint, however, takes the channel as `ch` —
/// so we read `channel` here but send `ch` in [SwitchRepository].
@freezed
abstract class SwitchState with _$SwitchState {
  const factory SwitchState({
    @Default('') String id,
    @Default('') String name,
    @JsonKey(name: 'state') @Default(false) bool on,
    /// Channel for multi-channel switches. Wire key is `channel`.
    @JsonKey(name: 'channel') @Default(0) int ch,
    /// Whether the extension backing this switch is currently online.
    @Default(true) bool online,
  }) = _SwitchState;

  factory SwitchState.fromJson(Map<String, dynamic> json) =>
      _$SwitchStateFromJson(json);
}

/// A peer master in the mesh, as reported in the snapshot's peer array.
@freezed
abstract class PeerState with _$PeerState {
  const factory PeerState({
    @Default('') String uid,
    @Default('') String name,
    @Default('') String fw,
    @Default(true) bool online,
  }) = _PeerState;

  factory PeerState.fromJson(Map<String, dynamic> json) =>
      _$PeerStateFromJson(json);
}
