// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mesh_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MeshStatus {

 bool get active;@JsonKey(name: 'mesh_name') String get meshName;@JsonKey(name: 'peer_count') int get peerCount; String get fw; bool get syncing;@JsonKey(name: 'cred_stale') bool get credStale; List<MeshPeer> get peers;
/// Create a copy of MeshStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MeshStatusCopyWith<MeshStatus> get copyWith => _$MeshStatusCopyWithImpl<MeshStatus>(this as MeshStatus, _$identity);

  /// Serializes this MeshStatus to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MeshStatus&&(identical(other.active, active) || other.active == active)&&(identical(other.meshName, meshName) || other.meshName == meshName)&&(identical(other.peerCount, peerCount) || other.peerCount == peerCount)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.syncing, syncing) || other.syncing == syncing)&&(identical(other.credStale, credStale) || other.credStale == credStale)&&const DeepCollectionEquality().equals(other.peers, peers));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,active,meshName,peerCount,fw,syncing,credStale,const DeepCollectionEquality().hash(peers));

@override
String toString() {
  return 'MeshStatus(active: $active, meshName: $meshName, peerCount: $peerCount, fw: $fw, syncing: $syncing, credStale: $credStale, peers: $peers)';
}


}

/// @nodoc
abstract mixin class $MeshStatusCopyWith<$Res>  {
  factory $MeshStatusCopyWith(MeshStatus value, $Res Function(MeshStatus) _then) = _$MeshStatusCopyWithImpl;
@useResult
$Res call({
 bool active,@JsonKey(name: 'mesh_name') String meshName,@JsonKey(name: 'peer_count') int peerCount, String fw, bool syncing,@JsonKey(name: 'cred_stale') bool credStale, List<MeshPeer> peers
});




}
/// @nodoc
class _$MeshStatusCopyWithImpl<$Res>
    implements $MeshStatusCopyWith<$Res> {
  _$MeshStatusCopyWithImpl(this._self, this._then);

  final MeshStatus _self;
  final $Res Function(MeshStatus) _then;

/// Create a copy of MeshStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? active = null,Object? meshName = null,Object? peerCount = null,Object? fw = null,Object? syncing = null,Object? credStale = null,Object? peers = null,}) {
  return _then(_self.copyWith(
active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,meshName: null == meshName ? _self.meshName : meshName // ignore: cast_nullable_to_non_nullable
as String,peerCount: null == peerCount ? _self.peerCount : peerCount // ignore: cast_nullable_to_non_nullable
as int,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,syncing: null == syncing ? _self.syncing : syncing // ignore: cast_nullable_to_non_nullable
as bool,credStale: null == credStale ? _self.credStale : credStale // ignore: cast_nullable_to_non_nullable
as bool,peers: null == peers ? _self.peers : peers // ignore: cast_nullable_to_non_nullable
as List<MeshPeer>,
  ));
}

}


/// Adds pattern-matching-related methods to [MeshStatus].
extension MeshStatusPatterns on MeshStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MeshStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MeshStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MeshStatus value)  $default,){
final _that = this;
switch (_that) {
case _MeshStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MeshStatus value)?  $default,){
final _that = this;
switch (_that) {
case _MeshStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool active, @JsonKey(name: 'mesh_name')  String meshName, @JsonKey(name: 'peer_count')  int peerCount,  String fw,  bool syncing, @JsonKey(name: 'cred_stale')  bool credStale,  List<MeshPeer> peers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MeshStatus() when $default != null:
return $default(_that.active,_that.meshName,_that.peerCount,_that.fw,_that.syncing,_that.credStale,_that.peers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool active, @JsonKey(name: 'mesh_name')  String meshName, @JsonKey(name: 'peer_count')  int peerCount,  String fw,  bool syncing, @JsonKey(name: 'cred_stale')  bool credStale,  List<MeshPeer> peers)  $default,) {final _that = this;
switch (_that) {
case _MeshStatus():
return $default(_that.active,_that.meshName,_that.peerCount,_that.fw,_that.syncing,_that.credStale,_that.peers);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool active, @JsonKey(name: 'mesh_name')  String meshName, @JsonKey(name: 'peer_count')  int peerCount,  String fw,  bool syncing, @JsonKey(name: 'cred_stale')  bool credStale,  List<MeshPeer> peers)?  $default,) {final _that = this;
switch (_that) {
case _MeshStatus() when $default != null:
return $default(_that.active,_that.meshName,_that.peerCount,_that.fw,_that.syncing,_that.credStale,_that.peers);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MeshStatus implements MeshStatus {
  const _MeshStatus({this.active = false, @JsonKey(name: 'mesh_name') this.meshName = '', @JsonKey(name: 'peer_count') this.peerCount = 0, this.fw = '', this.syncing = false, @JsonKey(name: 'cred_stale') this.credStale = false, final  List<MeshPeer> peers = const <MeshPeer>[]}): _peers = peers;
  factory _MeshStatus.fromJson(Map<String, dynamic> json) => _$MeshStatusFromJson(json);

@override@JsonKey() final  bool active;
@override@JsonKey(name: 'mesh_name') final  String meshName;
@override@JsonKey(name: 'peer_count') final  int peerCount;
@override@JsonKey() final  String fw;
@override@JsonKey() final  bool syncing;
@override@JsonKey(name: 'cred_stale') final  bool credStale;
 final  List<MeshPeer> _peers;
@override@JsonKey() List<MeshPeer> get peers {
  if (_peers is EqualUnmodifiableListView) return _peers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_peers);
}


/// Create a copy of MeshStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MeshStatusCopyWith<_MeshStatus> get copyWith => __$MeshStatusCopyWithImpl<_MeshStatus>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MeshStatusToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MeshStatus&&(identical(other.active, active) || other.active == active)&&(identical(other.meshName, meshName) || other.meshName == meshName)&&(identical(other.peerCount, peerCount) || other.peerCount == peerCount)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.syncing, syncing) || other.syncing == syncing)&&(identical(other.credStale, credStale) || other.credStale == credStale)&&const DeepCollectionEquality().equals(other._peers, _peers));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,active,meshName,peerCount,fw,syncing,credStale,const DeepCollectionEquality().hash(_peers));

@override
String toString() {
  return 'MeshStatus(active: $active, meshName: $meshName, peerCount: $peerCount, fw: $fw, syncing: $syncing, credStale: $credStale, peers: $peers)';
}


}

/// @nodoc
abstract mixin class _$MeshStatusCopyWith<$Res> implements $MeshStatusCopyWith<$Res> {
  factory _$MeshStatusCopyWith(_MeshStatus value, $Res Function(_MeshStatus) _then) = __$MeshStatusCopyWithImpl;
@override @useResult
$Res call({
 bool active,@JsonKey(name: 'mesh_name') String meshName,@JsonKey(name: 'peer_count') int peerCount, String fw, bool syncing,@JsonKey(name: 'cred_stale') bool credStale, List<MeshPeer> peers
});




}
/// @nodoc
class __$MeshStatusCopyWithImpl<$Res>
    implements _$MeshStatusCopyWith<$Res> {
  __$MeshStatusCopyWithImpl(this._self, this._then);

  final _MeshStatus _self;
  final $Res Function(_MeshStatus) _then;

/// Create a copy of MeshStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? active = null,Object? meshName = null,Object? peerCount = null,Object? fw = null,Object? syncing = null,Object? credStale = null,Object? peers = null,}) {
  return _then(_MeshStatus(
active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,meshName: null == meshName ? _self.meshName : meshName // ignore: cast_nullable_to_non_nullable
as String,peerCount: null == peerCount ? _self.peerCount : peerCount // ignore: cast_nullable_to_non_nullable
as int,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,syncing: null == syncing ? _self.syncing : syncing // ignore: cast_nullable_to_non_nullable
as bool,credStale: null == credStale ? _self.credStale : credStale // ignore: cast_nullable_to_non_nullable
as bool,peers: null == peers ? _self._peers : peers // ignore: cast_nullable_to_non_nullable
as List<MeshPeer>,
  ));
}


}


/// @nodoc
mixin _$MeshPeer {

 String get name; String get fw;@JsonKey(name: 'cred_stale') bool get credStale;
/// Create a copy of MeshPeer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MeshPeerCopyWith<MeshPeer> get copyWith => _$MeshPeerCopyWithImpl<MeshPeer>(this as MeshPeer, _$identity);

  /// Serializes this MeshPeer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MeshPeer&&(identical(other.name, name) || other.name == name)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.credStale, credStale) || other.credStale == credStale));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,fw,credStale);

@override
String toString() {
  return 'MeshPeer(name: $name, fw: $fw, credStale: $credStale)';
}


}

/// @nodoc
abstract mixin class $MeshPeerCopyWith<$Res>  {
  factory $MeshPeerCopyWith(MeshPeer value, $Res Function(MeshPeer) _then) = _$MeshPeerCopyWithImpl;
@useResult
$Res call({
 String name, String fw,@JsonKey(name: 'cred_stale') bool credStale
});




}
/// @nodoc
class _$MeshPeerCopyWithImpl<$Res>
    implements $MeshPeerCopyWith<$Res> {
  _$MeshPeerCopyWithImpl(this._self, this._then);

  final MeshPeer _self;
  final $Res Function(MeshPeer) _then;

/// Create a copy of MeshPeer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? fw = null,Object? credStale = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,credStale: null == credStale ? _self.credStale : credStale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [MeshPeer].
extension MeshPeerPatterns on MeshPeer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MeshPeer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MeshPeer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MeshPeer value)  $default,){
final _that = this;
switch (_that) {
case _MeshPeer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MeshPeer value)?  $default,){
final _that = this;
switch (_that) {
case _MeshPeer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String fw, @JsonKey(name: 'cred_stale')  bool credStale)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MeshPeer() when $default != null:
return $default(_that.name,_that.fw,_that.credStale);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String fw, @JsonKey(name: 'cred_stale')  bool credStale)  $default,) {final _that = this;
switch (_that) {
case _MeshPeer():
return $default(_that.name,_that.fw,_that.credStale);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String fw, @JsonKey(name: 'cred_stale')  bool credStale)?  $default,) {final _that = this;
switch (_that) {
case _MeshPeer() when $default != null:
return $default(_that.name,_that.fw,_that.credStale);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MeshPeer implements MeshPeer {
  const _MeshPeer({this.name = '', this.fw = '', @JsonKey(name: 'cred_stale') this.credStale = false});
  factory _MeshPeer.fromJson(Map<String, dynamic> json) => _$MeshPeerFromJson(json);

@override@JsonKey() final  String name;
@override@JsonKey() final  String fw;
@override@JsonKey(name: 'cred_stale') final  bool credStale;

/// Create a copy of MeshPeer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MeshPeerCopyWith<_MeshPeer> get copyWith => __$MeshPeerCopyWithImpl<_MeshPeer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MeshPeerToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MeshPeer&&(identical(other.name, name) || other.name == name)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.credStale, credStale) || other.credStale == credStale));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,fw,credStale);

@override
String toString() {
  return 'MeshPeer(name: $name, fw: $fw, credStale: $credStale)';
}


}

/// @nodoc
abstract mixin class _$MeshPeerCopyWith<$Res> implements $MeshPeerCopyWith<$Res> {
  factory _$MeshPeerCopyWith(_MeshPeer value, $Res Function(_MeshPeer) _then) = __$MeshPeerCopyWithImpl;
@override @useResult
$Res call({
 String name, String fw,@JsonKey(name: 'cred_stale') bool credStale
});




}
/// @nodoc
class __$MeshPeerCopyWithImpl<$Res>
    implements _$MeshPeerCopyWith<$Res> {
  __$MeshPeerCopyWithImpl(this._self, this._then);

  final _MeshPeer _self;
  final $Res Function(_MeshPeer) _then;

/// Create a copy of MeshPeer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? fw = null,Object? credStale = null,}) {
  return _then(_MeshPeer(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,credStale: null == credStale ? _self.credStale : credStale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$MeshInvite {

 String get mac; String get pin;
/// Create a copy of MeshInvite
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MeshInviteCopyWith<MeshInvite> get copyWith => _$MeshInviteCopyWithImpl<MeshInvite>(this as MeshInvite, _$identity);

  /// Serializes this MeshInvite to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MeshInvite&&(identical(other.mac, mac) || other.mac == mac)&&(identical(other.pin, pin) || other.pin == pin));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,mac,pin);

@override
String toString() {
  return 'MeshInvite(mac: $mac, pin: $pin)';
}


}

/// @nodoc
abstract mixin class $MeshInviteCopyWith<$Res>  {
  factory $MeshInviteCopyWith(MeshInvite value, $Res Function(MeshInvite) _then) = _$MeshInviteCopyWithImpl;
@useResult
$Res call({
 String mac, String pin
});




}
/// @nodoc
class _$MeshInviteCopyWithImpl<$Res>
    implements $MeshInviteCopyWith<$Res> {
  _$MeshInviteCopyWithImpl(this._self, this._then);

  final MeshInvite _self;
  final $Res Function(MeshInvite) _then;

/// Create a copy of MeshInvite
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mac = null,Object? pin = null,}) {
  return _then(_self.copyWith(
mac: null == mac ? _self.mac : mac // ignore: cast_nullable_to_non_nullable
as String,pin: null == pin ? _self.pin : pin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [MeshInvite].
extension MeshInvitePatterns on MeshInvite {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MeshInvite value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MeshInvite() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MeshInvite value)  $default,){
final _that = this;
switch (_that) {
case _MeshInvite():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MeshInvite value)?  $default,){
final _that = this;
switch (_that) {
case _MeshInvite() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String mac,  String pin)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MeshInvite() when $default != null:
return $default(_that.mac,_that.pin);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String mac,  String pin)  $default,) {final _that = this;
switch (_that) {
case _MeshInvite():
return $default(_that.mac,_that.pin);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String mac,  String pin)?  $default,) {final _that = this;
switch (_that) {
case _MeshInvite() when $default != null:
return $default(_that.mac,_that.pin);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MeshInvite implements MeshInvite {
  const _MeshInvite({this.mac = '', this.pin = ''});
  factory _MeshInvite.fromJson(Map<String, dynamic> json) => _$MeshInviteFromJson(json);

@override@JsonKey() final  String mac;
@override@JsonKey() final  String pin;

/// Create a copy of MeshInvite
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MeshInviteCopyWith<_MeshInvite> get copyWith => __$MeshInviteCopyWithImpl<_MeshInvite>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MeshInviteToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MeshInvite&&(identical(other.mac, mac) || other.mac == mac)&&(identical(other.pin, pin) || other.pin == pin));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,mac,pin);

@override
String toString() {
  return 'MeshInvite(mac: $mac, pin: $pin)';
}


}

/// @nodoc
abstract mixin class _$MeshInviteCopyWith<$Res> implements $MeshInviteCopyWith<$Res> {
  factory _$MeshInviteCopyWith(_MeshInvite value, $Res Function(_MeshInvite) _then) = __$MeshInviteCopyWithImpl;
@override @useResult
$Res call({
 String mac, String pin
});




}
/// @nodoc
class __$MeshInviteCopyWithImpl<$Res>
    implements _$MeshInviteCopyWith<$Res> {
  __$MeshInviteCopyWithImpl(this._self, this._then);

  final _MeshInvite _self;
  final $Res Function(_MeshInvite) _then;

/// Create a copy of MeshInvite
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mac = null,Object? pin = null,}) {
  return _then(_MeshInvite(
mac: null == mac ? _self.mac : mac // ignore: cast_nullable_to_non_nullable
as String,pin: null == pin ? _self.pin : pin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
