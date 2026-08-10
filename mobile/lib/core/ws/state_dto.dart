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
    @JsonKey(name: 'self_uid') @Default('') String selfUid,
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
    /// This is the master's presence verdict, not a guess: a board that has
    /// just come back reads false until it has been solid for a minute.
    @Default(true) bool online,

    /// Per-switch power-cut policy: true restores the last state, false
    /// starts off. The master owns this; the app only reflects it.
    @Default(false) bool restore,
  }) = _SwitchState;

  factory SwitchState.fromJson(Map<String, dynamic> json) =>
      _$SwitchStateFromJson(json);
}

/// How present something is, as the master sees it. Deliberately three
/// states: a board that keeps dropping and returning is a distinct
/// diagnostic case, not a switch blinking in and out of the dashboard.
enum Presence {
  online,
  offline,
  intermittent;

  static Presence parse(String? s) => switch (s) {
        'online' => Presence.online,
        'intermittent' => Presence.intermittent,
        _ => Presence.offline,
      };

  String get label => switch (this) {
        Presence.online => 'Online',
        Presence.offline => 'Offline',
        Presence.intermittent => 'Intermittent',
      };
}

/// "3 minutes ago" from the master's seconds-since count. The master has no
/// clock, so last-seen is always relative.
String lastSeenLabel(int seconds) {
  if (seconds <= 0) return 'just now';
  if (seconds < 60) return '${seconds}s ago';
  if (seconds < 3600) return '${seconds ~/ 60} min ago';
  if (seconds < 86400) return '${seconds ~/ 3600} h ago';
  return '${seconds ~/ 86400} d ago';
}

/// A peer master in the mesh, as reported in the snapshot's peer array.
@freezed
abstract class PeerState with _$PeerState {
  const factory PeerState({
    @Default('') String uid,
    @Default('') String name,
    @Default('') String fw,
    @Default(true) bool online,

    /// Debounced presence from the master. `online` is the same verdict as
    /// a bool; this distinguishes a settled outage from a flapping peer.
    @JsonKey(name: 'presence') @Default('online') String presenceRaw,

    /// Seconds since the peer was last heard from.
    @JsonKey(name: 'last_seen') @Default(0) int lastSeen,

    /// The peer's own switches, gossiped across the mesh. Without these a
    /// mesh dashboard could only ever show the master the phone happens to
    /// be talking to.
    @Default(<SwitchState>[]) List<SwitchState> switches,
  }) = _PeerState;

  const PeerState._();

  Presence get presence => Presence.parse(presenceRaw);

  factory PeerState.fromJson(Map<String, dynamic> json) =>
      _$PeerStateFromJson(json);
}
