// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'state_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StateSnapshot {

@JsonKey(name: 'master_name') String get masterName;@JsonKey(name: 'self_uid') String get selfUid; int get uptime;@JsonKey(name: 'boot_complete') bool get bootComplete;@JsonKey(name: 'scan_active') bool get scanActive; List<SwitchState> get switches;@JsonKey(name: 'mesh_peers') List<PeerState> get peers;
/// Create a copy of StateSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StateSnapshotCopyWith<StateSnapshot> get copyWith => _$StateSnapshotCopyWithImpl<StateSnapshot>(this as StateSnapshot, _$identity);

  /// Serializes this StateSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StateSnapshot&&(identical(other.masterName, masterName) || other.masterName == masterName)&&(identical(other.selfUid, selfUid) || other.selfUid == selfUid)&&(identical(other.uptime, uptime) || other.uptime == uptime)&&(identical(other.bootComplete, bootComplete) || other.bootComplete == bootComplete)&&(identical(other.scanActive, scanActive) || other.scanActive == scanActive)&&const DeepCollectionEquality().equals(other.switches, switches)&&const DeepCollectionEquality().equals(other.peers, peers));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,masterName,selfUid,uptime,bootComplete,scanActive,const DeepCollectionEquality().hash(switches),const DeepCollectionEquality().hash(peers));

@override
String toString() {
  return 'StateSnapshot(masterName: $masterName, selfUid: $selfUid, uptime: $uptime, bootComplete: $bootComplete, scanActive: $scanActive, switches: $switches, peers: $peers)';
}


}

/// @nodoc
abstract mixin class $StateSnapshotCopyWith<$Res>  {
  factory $StateSnapshotCopyWith(StateSnapshot value, $Res Function(StateSnapshot) _then) = _$StateSnapshotCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'master_name') String masterName,@JsonKey(name: 'self_uid') String selfUid, int uptime,@JsonKey(name: 'boot_complete') bool bootComplete,@JsonKey(name: 'scan_active') bool scanActive, List<SwitchState> switches,@JsonKey(name: 'mesh_peers') List<PeerState> peers
});




}
/// @nodoc
class _$StateSnapshotCopyWithImpl<$Res>
    implements $StateSnapshotCopyWith<$Res> {
  _$StateSnapshotCopyWithImpl(this._self, this._then);

  final StateSnapshot _self;
  final $Res Function(StateSnapshot) _then;

/// Create a copy of StateSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? masterName = null,Object? selfUid = null,Object? uptime = null,Object? bootComplete = null,Object? scanActive = null,Object? switches = null,Object? peers = null,}) {
  return _then(_self.copyWith(
masterName: null == masterName ? _self.masterName : masterName // ignore: cast_nullable_to_non_nullable
as String,selfUid: null == selfUid ? _self.selfUid : selfUid // ignore: cast_nullable_to_non_nullable
as String,uptime: null == uptime ? _self.uptime : uptime // ignore: cast_nullable_to_non_nullable
as int,bootComplete: null == bootComplete ? _self.bootComplete : bootComplete // ignore: cast_nullable_to_non_nullable
as bool,scanActive: null == scanActive ? _self.scanActive : scanActive // ignore: cast_nullable_to_non_nullable
as bool,switches: null == switches ? _self.switches : switches // ignore: cast_nullable_to_non_nullable
as List<SwitchState>,peers: null == peers ? _self.peers : peers // ignore: cast_nullable_to_non_nullable
as List<PeerState>,
  ));
}

}


/// Adds pattern-matching-related methods to [StateSnapshot].
extension StateSnapshotPatterns on StateSnapshot {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StateSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StateSnapshot() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StateSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _StateSnapshot():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StateSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _StateSnapshot() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'master_name')  String masterName, @JsonKey(name: 'self_uid')  String selfUid,  int uptime, @JsonKey(name: 'boot_complete')  bool bootComplete, @JsonKey(name: 'scan_active')  bool scanActive,  List<SwitchState> switches, @JsonKey(name: 'mesh_peers')  List<PeerState> peers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StateSnapshot() when $default != null:
return $default(_that.masterName,_that.selfUid,_that.uptime,_that.bootComplete,_that.scanActive,_that.switches,_that.peers);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'master_name')  String masterName, @JsonKey(name: 'self_uid')  String selfUid,  int uptime, @JsonKey(name: 'boot_complete')  bool bootComplete, @JsonKey(name: 'scan_active')  bool scanActive,  List<SwitchState> switches, @JsonKey(name: 'mesh_peers')  List<PeerState> peers)  $default,) {final _that = this;
switch (_that) {
case _StateSnapshot():
return $default(_that.masterName,_that.selfUid,_that.uptime,_that.bootComplete,_that.scanActive,_that.switches,_that.peers);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'master_name')  String masterName, @JsonKey(name: 'self_uid')  String selfUid,  int uptime, @JsonKey(name: 'boot_complete')  bool bootComplete, @JsonKey(name: 'scan_active')  bool scanActive,  List<SwitchState> switches, @JsonKey(name: 'mesh_peers')  List<PeerState> peers)?  $default,) {final _that = this;
switch (_that) {
case _StateSnapshot() when $default != null:
return $default(_that.masterName,_that.selfUid,_that.uptime,_that.bootComplete,_that.scanActive,_that.switches,_that.peers);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StateSnapshot implements StateSnapshot {
  const _StateSnapshot({@JsonKey(name: 'master_name') this.masterName = '', @JsonKey(name: 'self_uid') this.selfUid = '', this.uptime = 0, @JsonKey(name: 'boot_complete') this.bootComplete = true, @JsonKey(name: 'scan_active') this.scanActive = false, final  List<SwitchState> switches = const <SwitchState>[], @JsonKey(name: 'mesh_peers') final  List<PeerState> peers = const <PeerState>[]}): _switches = switches,_peers = peers;
  factory _StateSnapshot.fromJson(Map<String, dynamic> json) => _$StateSnapshotFromJson(json);

@override@JsonKey(name: 'master_name') final  String masterName;
@override@JsonKey(name: 'self_uid') final  String selfUid;
@override@JsonKey() final  int uptime;
@override@JsonKey(name: 'boot_complete') final  bool bootComplete;
@override@JsonKey(name: 'scan_active') final  bool scanActive;
 final  List<SwitchState> _switches;
@override@JsonKey() List<SwitchState> get switches {
  if (_switches is EqualUnmodifiableListView) return _switches;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_switches);
}

 final  List<PeerState> _peers;
@override@JsonKey(name: 'mesh_peers') List<PeerState> get peers {
  if (_peers is EqualUnmodifiableListView) return _peers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_peers);
}


/// Create a copy of StateSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StateSnapshotCopyWith<_StateSnapshot> get copyWith => __$StateSnapshotCopyWithImpl<_StateSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StateSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StateSnapshot&&(identical(other.masterName, masterName) || other.masterName == masterName)&&(identical(other.selfUid, selfUid) || other.selfUid == selfUid)&&(identical(other.uptime, uptime) || other.uptime == uptime)&&(identical(other.bootComplete, bootComplete) || other.bootComplete == bootComplete)&&(identical(other.scanActive, scanActive) || other.scanActive == scanActive)&&const DeepCollectionEquality().equals(other._switches, _switches)&&const DeepCollectionEquality().equals(other._peers, _peers));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,masterName,selfUid,uptime,bootComplete,scanActive,const DeepCollectionEquality().hash(_switches),const DeepCollectionEquality().hash(_peers));

@override
String toString() {
  return 'StateSnapshot(masterName: $masterName, selfUid: $selfUid, uptime: $uptime, bootComplete: $bootComplete, scanActive: $scanActive, switches: $switches, peers: $peers)';
}


}

/// @nodoc
abstract mixin class _$StateSnapshotCopyWith<$Res> implements $StateSnapshotCopyWith<$Res> {
  factory _$StateSnapshotCopyWith(_StateSnapshot value, $Res Function(_StateSnapshot) _then) = __$StateSnapshotCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'master_name') String masterName,@JsonKey(name: 'self_uid') String selfUid, int uptime,@JsonKey(name: 'boot_complete') bool bootComplete,@JsonKey(name: 'scan_active') bool scanActive, List<SwitchState> switches,@JsonKey(name: 'mesh_peers') List<PeerState> peers
});




}
/// @nodoc
class __$StateSnapshotCopyWithImpl<$Res>
    implements _$StateSnapshotCopyWith<$Res> {
  __$StateSnapshotCopyWithImpl(this._self, this._then);

  final _StateSnapshot _self;
  final $Res Function(_StateSnapshot) _then;

/// Create a copy of StateSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? masterName = null,Object? selfUid = null,Object? uptime = null,Object? bootComplete = null,Object? scanActive = null,Object? switches = null,Object? peers = null,}) {
  return _then(_StateSnapshot(
masterName: null == masterName ? _self.masterName : masterName // ignore: cast_nullable_to_non_nullable
as String,selfUid: null == selfUid ? _self.selfUid : selfUid // ignore: cast_nullable_to_non_nullable
as String,uptime: null == uptime ? _self.uptime : uptime // ignore: cast_nullable_to_non_nullable
as int,bootComplete: null == bootComplete ? _self.bootComplete : bootComplete // ignore: cast_nullable_to_non_nullable
as bool,scanActive: null == scanActive ? _self.scanActive : scanActive // ignore: cast_nullable_to_non_nullable
as bool,switches: null == switches ? _self._switches : switches // ignore: cast_nullable_to_non_nullable
as List<SwitchState>,peers: null == peers ? _self._peers : peers // ignore: cast_nullable_to_non_nullable
as List<PeerState>,
  ));
}


}


/// @nodoc
mixin _$SwitchState {

 String get id; String get name;@JsonKey(name: 'state') bool get on;/// Channel for multi-channel switches. Wire key is `channel`.
@JsonKey(name: 'channel') int get ch;/// Whether the extension backing this switch is currently online.
/// This is the master's presence verdict, not a guess: a board that has
/// just come back reads false until it has been solid for a minute.
 bool get online;/// Per-switch power-cut policy: true restores the last state, false
/// starts off. The master owns this; the app only reflects it.
 bool get restore;
/// Create a copy of SwitchState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SwitchStateCopyWith<SwitchState> get copyWith => _$SwitchStateCopyWithImpl<SwitchState>(this as SwitchState, _$identity);

  /// Serializes this SwitchState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SwitchState&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.on, on) || other.on == on)&&(identical(other.ch, ch) || other.ch == ch)&&(identical(other.online, online) || other.online == online)&&(identical(other.restore, restore) || other.restore == restore));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,on,ch,online,restore);

@override
String toString() {
  return 'SwitchState(id: $id, name: $name, on: $on, ch: $ch, online: $online, restore: $restore)';
}


}

/// @nodoc
abstract mixin class $SwitchStateCopyWith<$Res>  {
  factory $SwitchStateCopyWith(SwitchState value, $Res Function(SwitchState) _then) = _$SwitchStateCopyWithImpl;
@useResult
$Res call({
 String id, String name,@JsonKey(name: 'state') bool on,@JsonKey(name: 'channel') int ch, bool online, bool restore
});




}
/// @nodoc
class _$SwitchStateCopyWithImpl<$Res>
    implements $SwitchStateCopyWith<$Res> {
  _$SwitchStateCopyWithImpl(this._self, this._then);

  final SwitchState _self;
  final $Res Function(SwitchState) _then;

/// Create a copy of SwitchState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? on = null,Object? ch = null,Object? online = null,Object? restore = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,on: null == on ? _self.on : on // ignore: cast_nullable_to_non_nullable
as bool,ch: null == ch ? _self.ch : ch // ignore: cast_nullable_to_non_nullable
as int,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,restore: null == restore ? _self.restore : restore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SwitchState].
extension SwitchStatePatterns on SwitchState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SwitchState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SwitchState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SwitchState value)  $default,){
final _that = this;
switch (_that) {
case _SwitchState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SwitchState value)?  $default,){
final _that = this;
switch (_that) {
case _SwitchState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name, @JsonKey(name: 'state')  bool on, @JsonKey(name: 'channel')  int ch,  bool online,  bool restore)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SwitchState() when $default != null:
return $default(_that.id,_that.name,_that.on,_that.ch,_that.online,_that.restore);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name, @JsonKey(name: 'state')  bool on, @JsonKey(name: 'channel')  int ch,  bool online,  bool restore)  $default,) {final _that = this;
switch (_that) {
case _SwitchState():
return $default(_that.id,_that.name,_that.on,_that.ch,_that.online,_that.restore);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name, @JsonKey(name: 'state')  bool on, @JsonKey(name: 'channel')  int ch,  bool online,  bool restore)?  $default,) {final _that = this;
switch (_that) {
case _SwitchState() when $default != null:
return $default(_that.id,_that.name,_that.on,_that.ch,_that.online,_that.restore);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SwitchState implements SwitchState {
  const _SwitchState({this.id = '', this.name = '', @JsonKey(name: 'state') this.on = false, @JsonKey(name: 'channel') this.ch = 0, this.online = true, this.restore = false});
  factory _SwitchState.fromJson(Map<String, dynamic> json) => _$SwitchStateFromJson(json);

@override@JsonKey() final  String id;
@override@JsonKey() final  String name;
@override@JsonKey(name: 'state') final  bool on;
/// Channel for multi-channel switches. Wire key is `channel`.
@override@JsonKey(name: 'channel') final  int ch;
/// Whether the extension backing this switch is currently online.
/// This is the master's presence verdict, not a guess: a board that has
/// just come back reads false until it has been solid for a minute.
@override@JsonKey() final  bool online;
/// Per-switch power-cut policy: true restores the last state, false
/// starts off. The master owns this; the app only reflects it.
@override@JsonKey() final  bool restore;

/// Create a copy of SwitchState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SwitchStateCopyWith<_SwitchState> get copyWith => __$SwitchStateCopyWithImpl<_SwitchState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SwitchStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SwitchState&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.on, on) || other.on == on)&&(identical(other.ch, ch) || other.ch == ch)&&(identical(other.online, online) || other.online == online)&&(identical(other.restore, restore) || other.restore == restore));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,on,ch,online,restore);

@override
String toString() {
  return 'SwitchState(id: $id, name: $name, on: $on, ch: $ch, online: $online, restore: $restore)';
}


}

/// @nodoc
abstract mixin class _$SwitchStateCopyWith<$Res> implements $SwitchStateCopyWith<$Res> {
  factory _$SwitchStateCopyWith(_SwitchState value, $Res Function(_SwitchState) _then) = __$SwitchStateCopyWithImpl;
@override @useResult
$Res call({
 String id, String name,@JsonKey(name: 'state') bool on,@JsonKey(name: 'channel') int ch, bool online, bool restore
});




}
/// @nodoc
class __$SwitchStateCopyWithImpl<$Res>
    implements _$SwitchStateCopyWith<$Res> {
  __$SwitchStateCopyWithImpl(this._self, this._then);

  final _SwitchState _self;
  final $Res Function(_SwitchState) _then;

/// Create a copy of SwitchState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? on = null,Object? ch = null,Object? online = null,Object? restore = null,}) {
  return _then(_SwitchState(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,on: null == on ? _self.on : on // ignore: cast_nullable_to_non_nullable
as bool,ch: null == ch ? _self.ch : ch // ignore: cast_nullable_to_non_nullable
as int,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,restore: null == restore ? _self.restore : restore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$PeerState {

 String get uid; String get name; String get fw; bool get online;/// Debounced presence from the master. `online` is the same verdict as
/// a bool; this distinguishes a settled outage from a flapping peer.
@JsonKey(name: 'presence') String get presenceRaw;/// Seconds since the peer was last heard from.
@JsonKey(name: 'last_seen') int get lastSeen;
/// Create a copy of PeerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PeerStateCopyWith<PeerState> get copyWith => _$PeerStateCopyWithImpl<PeerState>(this as PeerState, _$identity);

  /// Serializes this PeerState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PeerState&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.name, name) || other.name == name)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.online, online) || other.online == online)&&(identical(other.presenceRaw, presenceRaw) || other.presenceRaw == presenceRaw)&&(identical(other.lastSeen, lastSeen) || other.lastSeen == lastSeen));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,name,fw,online,presenceRaw,lastSeen);

@override
String toString() {
  return 'PeerState(uid: $uid, name: $name, fw: $fw, online: $online, presenceRaw: $presenceRaw, lastSeen: $lastSeen)';
}


}

/// @nodoc
abstract mixin class $PeerStateCopyWith<$Res>  {
  factory $PeerStateCopyWith(PeerState value, $Res Function(PeerState) _then) = _$PeerStateCopyWithImpl;
@useResult
$Res call({
 String uid, String name, String fw, bool online,@JsonKey(name: 'presence') String presenceRaw,@JsonKey(name: 'last_seen') int lastSeen
});




}
/// @nodoc
class _$PeerStateCopyWithImpl<$Res>
    implements $PeerStateCopyWith<$Res> {
  _$PeerStateCopyWithImpl(this._self, this._then);

  final PeerState _self;
  final $Res Function(PeerState) _then;

/// Create a copy of PeerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uid = null,Object? name = null,Object? fw = null,Object? online = null,Object? presenceRaw = null,Object? lastSeen = null,}) {
  return _then(_self.copyWith(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,presenceRaw: null == presenceRaw ? _self.presenceRaw : presenceRaw // ignore: cast_nullable_to_non_nullable
as String,lastSeen: null == lastSeen ? _self.lastSeen : lastSeen // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PeerState].
extension PeerStatePatterns on PeerState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PeerState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PeerState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PeerState value)  $default,){
final _that = this;
switch (_that) {
case _PeerState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PeerState value)?  $default,){
final _that = this;
switch (_that) {
case _PeerState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String uid,  String name,  String fw,  bool online, @JsonKey(name: 'presence')  String presenceRaw, @JsonKey(name: 'last_seen')  int lastSeen)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PeerState() when $default != null:
return $default(_that.uid,_that.name,_that.fw,_that.online,_that.presenceRaw,_that.lastSeen);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String uid,  String name,  String fw,  bool online, @JsonKey(name: 'presence')  String presenceRaw, @JsonKey(name: 'last_seen')  int lastSeen)  $default,) {final _that = this;
switch (_that) {
case _PeerState():
return $default(_that.uid,_that.name,_that.fw,_that.online,_that.presenceRaw,_that.lastSeen);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String uid,  String name,  String fw,  bool online, @JsonKey(name: 'presence')  String presenceRaw, @JsonKey(name: 'last_seen')  int lastSeen)?  $default,) {final _that = this;
switch (_that) {
case _PeerState() when $default != null:
return $default(_that.uid,_that.name,_that.fw,_that.online,_that.presenceRaw,_that.lastSeen);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PeerState extends PeerState {
  const _PeerState({this.uid = '', this.name = '', this.fw = '', this.online = true, @JsonKey(name: 'presence') this.presenceRaw = 'online', @JsonKey(name: 'last_seen') this.lastSeen = 0}): super._();
  factory _PeerState.fromJson(Map<String, dynamic> json) => _$PeerStateFromJson(json);

@override@JsonKey() final  String uid;
@override@JsonKey() final  String name;
@override@JsonKey() final  String fw;
@override@JsonKey() final  bool online;
/// Debounced presence from the master. `online` is the same verdict as
/// a bool; this distinguishes a settled outage from a flapping peer.
@override@JsonKey(name: 'presence') final  String presenceRaw;
/// Seconds since the peer was last heard from.
@override@JsonKey(name: 'last_seen') final  int lastSeen;

/// Create a copy of PeerState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PeerStateCopyWith<_PeerState> get copyWith => __$PeerStateCopyWithImpl<_PeerState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PeerStateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PeerState&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.name, name) || other.name == name)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.online, online) || other.online == online)&&(identical(other.presenceRaw, presenceRaw) || other.presenceRaw == presenceRaw)&&(identical(other.lastSeen, lastSeen) || other.lastSeen == lastSeen));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uid,name,fw,online,presenceRaw,lastSeen);

@override
String toString() {
  return 'PeerState(uid: $uid, name: $name, fw: $fw, online: $online, presenceRaw: $presenceRaw, lastSeen: $lastSeen)';
}


}

/// @nodoc
abstract mixin class _$PeerStateCopyWith<$Res> implements $PeerStateCopyWith<$Res> {
  factory _$PeerStateCopyWith(_PeerState value, $Res Function(_PeerState) _then) = __$PeerStateCopyWithImpl;
@override @useResult
$Res call({
 String uid, String name, String fw, bool online,@JsonKey(name: 'presence') String presenceRaw,@JsonKey(name: 'last_seen') int lastSeen
});




}
/// @nodoc
class __$PeerStateCopyWithImpl<$Res>
    implements _$PeerStateCopyWith<$Res> {
  __$PeerStateCopyWithImpl(this._self, this._then);

  final _PeerState _self;
  final $Res Function(_PeerState) _then;

/// Create a copy of PeerState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uid = null,Object? name = null,Object? fw = null,Object? online = null,Object? presenceRaw = null,Object? lastSeen = null,}) {
  return _then(_PeerState(
uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,presenceRaw: null == presenceRaw ? _self.presenceRaw : presenceRaw // ignore: cast_nullable_to_non_nullable
as String,lastSeen: null == lastSeen ? _self.lastSeen : lastSeen // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
