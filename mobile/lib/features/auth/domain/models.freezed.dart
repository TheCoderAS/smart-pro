// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DeviceInfo {

 int get uptime;@JsonKey(name: 'free_heap') int get freeHeap; String get uid; String get fw; bool get auth;/// The network name this master is broadcasting *right now* — its own
/// report, not the phone's OS. Instruction copy ("connect to X") comes
/// from here, so it self-heals after a rename and needs no location
/// permission to read.
 String get ssid;/// True when this master is in a mesh. Meshed masters are one home.
 bool get mesh;/// Stable mesh identity. The mesh name is user-changeable, so the
/// the app keys on this instead.
@JsonKey(name: 'mesh_id') int get meshId;
/// Create a copy of DeviceInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceInfoCopyWith<DeviceInfo> get copyWith => _$DeviceInfoCopyWithImpl<DeviceInfo>(this as DeviceInfo, _$identity);

  /// Serializes this DeviceInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceInfo&&(identical(other.uptime, uptime) || other.uptime == uptime)&&(identical(other.freeHeap, freeHeap) || other.freeHeap == freeHeap)&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.auth, auth) || other.auth == auth)&&(identical(other.ssid, ssid) || other.ssid == ssid)&&(identical(other.mesh, mesh) || other.mesh == mesh)&&(identical(other.meshId, meshId) || other.meshId == meshId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uptime,freeHeap,uid,fw,auth,ssid,mesh,meshId);

@override
String toString() {
  return 'DeviceInfo(uptime: $uptime, freeHeap: $freeHeap, uid: $uid, fw: $fw, auth: $auth, ssid: $ssid, mesh: $mesh, meshId: $meshId)';
}


}

/// @nodoc
abstract mixin class $DeviceInfoCopyWith<$Res>  {
  factory $DeviceInfoCopyWith(DeviceInfo value, $Res Function(DeviceInfo) _then) = _$DeviceInfoCopyWithImpl;
@useResult
$Res call({
 int uptime,@JsonKey(name: 'free_heap') int freeHeap, String uid, String fw, bool auth, String ssid, bool mesh,@JsonKey(name: 'mesh_id') int meshId
});




}
/// @nodoc
class _$DeviceInfoCopyWithImpl<$Res>
    implements $DeviceInfoCopyWith<$Res> {
  _$DeviceInfoCopyWithImpl(this._self, this._then);

  final DeviceInfo _self;
  final $Res Function(DeviceInfo) _then;

/// Create a copy of DeviceInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uptime = null,Object? freeHeap = null,Object? uid = null,Object? fw = null,Object? auth = null,Object? ssid = null,Object? mesh = null,Object? meshId = null,}) {
  return _then(_self.copyWith(
uptime: null == uptime ? _self.uptime : uptime // ignore: cast_nullable_to_non_nullable
as int,freeHeap: null == freeHeap ? _self.freeHeap : freeHeap // ignore: cast_nullable_to_non_nullable
as int,uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,auth: null == auth ? _self.auth : auth // ignore: cast_nullable_to_non_nullable
as bool,ssid: null == ssid ? _self.ssid : ssid // ignore: cast_nullable_to_non_nullable
as String,mesh: null == mesh ? _self.mesh : mesh // ignore: cast_nullable_to_non_nullable
as bool,meshId: null == meshId ? _self.meshId : meshId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceInfo].
extension DeviceInfoPatterns on DeviceInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceInfo value)  $default,){
final _that = this;
switch (_that) {
case _DeviceInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceInfo value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int uptime, @JsonKey(name: 'free_heap')  int freeHeap,  String uid,  String fw,  bool auth,  String ssid,  bool mesh, @JsonKey(name: 'mesh_id')  int meshId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceInfo() when $default != null:
return $default(_that.uptime,_that.freeHeap,_that.uid,_that.fw,_that.auth,_that.ssid,_that.mesh,_that.meshId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int uptime, @JsonKey(name: 'free_heap')  int freeHeap,  String uid,  String fw,  bool auth,  String ssid,  bool mesh, @JsonKey(name: 'mesh_id')  int meshId)  $default,) {final _that = this;
switch (_that) {
case _DeviceInfo():
return $default(_that.uptime,_that.freeHeap,_that.uid,_that.fw,_that.auth,_that.ssid,_that.mesh,_that.meshId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int uptime, @JsonKey(name: 'free_heap')  int freeHeap,  String uid,  String fw,  bool auth,  String ssid,  bool mesh, @JsonKey(name: 'mesh_id')  int meshId)?  $default,) {final _that = this;
switch (_that) {
case _DeviceInfo() when $default != null:
return $default(_that.uptime,_that.freeHeap,_that.uid,_that.fw,_that.auth,_that.ssid,_that.mesh,_that.meshId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DeviceInfo implements DeviceInfo {
  const _DeviceInfo({required this.uptime, @JsonKey(name: 'free_heap') required this.freeHeap, required this.uid, required this.fw, required this.auth, this.ssid = '', this.mesh = false, @JsonKey(name: 'mesh_id') this.meshId = 0});
  factory _DeviceInfo.fromJson(Map<String, dynamic> json) => _$DeviceInfoFromJson(json);

@override final  int uptime;
@override@JsonKey(name: 'free_heap') final  int freeHeap;
@override final  String uid;
@override final  String fw;
@override final  bool auth;
/// The network name this master is broadcasting *right now* — its own
/// report, not the phone's OS. Instruction copy ("connect to X") comes
/// from here, so it self-heals after a rename and needs no location
/// permission to read.
@override@JsonKey() final  String ssid;
/// True when this master is in a mesh. Meshed masters are one home.
@override@JsonKey() final  bool mesh;
/// Stable mesh identity. The mesh name is user-changeable, so the
/// the app keys on this instead.
@override@JsonKey(name: 'mesh_id') final  int meshId;

/// Create a copy of DeviceInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceInfoCopyWith<_DeviceInfo> get copyWith => __$DeviceInfoCopyWithImpl<_DeviceInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DeviceInfoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceInfo&&(identical(other.uptime, uptime) || other.uptime == uptime)&&(identical(other.freeHeap, freeHeap) || other.freeHeap == freeHeap)&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.auth, auth) || other.auth == auth)&&(identical(other.ssid, ssid) || other.ssid == ssid)&&(identical(other.mesh, mesh) || other.mesh == mesh)&&(identical(other.meshId, meshId) || other.meshId == meshId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,uptime,freeHeap,uid,fw,auth,ssid,mesh,meshId);

@override
String toString() {
  return 'DeviceInfo(uptime: $uptime, freeHeap: $freeHeap, uid: $uid, fw: $fw, auth: $auth, ssid: $ssid, mesh: $mesh, meshId: $meshId)';
}


}

/// @nodoc
abstract mixin class _$DeviceInfoCopyWith<$Res> implements $DeviceInfoCopyWith<$Res> {
  factory _$DeviceInfoCopyWith(_DeviceInfo value, $Res Function(_DeviceInfo) _then) = __$DeviceInfoCopyWithImpl;
@override @useResult
$Res call({
 int uptime,@JsonKey(name: 'free_heap') int freeHeap, String uid, String fw, bool auth, String ssid, bool mesh,@JsonKey(name: 'mesh_id') int meshId
});




}
/// @nodoc
class __$DeviceInfoCopyWithImpl<$Res>
    implements _$DeviceInfoCopyWith<$Res> {
  __$DeviceInfoCopyWithImpl(this._self, this._then);

  final _DeviceInfo _self;
  final $Res Function(_DeviceInfo) _then;

/// Create a copy of DeviceInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uptime = null,Object? freeHeap = null,Object? uid = null,Object? fw = null,Object? auth = null,Object? ssid = null,Object? mesh = null,Object? meshId = null,}) {
  return _then(_DeviceInfo(
uptime: null == uptime ? _self.uptime : uptime // ignore: cast_nullable_to_non_nullable
as int,freeHeap: null == freeHeap ? _self.freeHeap : freeHeap // ignore: cast_nullable_to_non_nullable
as int,uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,auth: null == auth ? _self.auth : auth // ignore: cast_nullable_to_non_nullable
as bool,ssid: null == ssid ? _self.ssid : ssid // ignore: cast_nullable_to_non_nullable
as String,mesh: null == mesh ? _self.mesh : mesh // ignore: cast_nullable_to_non_nullable
as bool,meshId: null == meshId ? _self.meshId : meshId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$LoginResult {

 String get token; bool get mesh;
/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoginResultCopyWith<LoginResult> get copyWith => _$LoginResultCopyWithImpl<LoginResult>(this as LoginResult, _$identity);

  /// Serializes this LoginResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoginResult&&(identical(other.token, token) || other.token == token)&&(identical(other.mesh, mesh) || other.mesh == mesh));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,token,mesh);

@override
String toString() {
  return 'LoginResult(token: $token, mesh: $mesh)';
}


}

/// @nodoc
abstract mixin class $LoginResultCopyWith<$Res>  {
  factory $LoginResultCopyWith(LoginResult value, $Res Function(LoginResult) _then) = _$LoginResultCopyWithImpl;
@useResult
$Res call({
 String token, bool mesh
});




}
/// @nodoc
class _$LoginResultCopyWithImpl<$Res>
    implements $LoginResultCopyWith<$Res> {
  _$LoginResultCopyWithImpl(this._self, this._then);

  final LoginResult _self;
  final $Res Function(LoginResult) _then;

/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? token = null,Object? mesh = null,}) {
  return _then(_self.copyWith(
token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,mesh: null == mesh ? _self.mesh : mesh // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [LoginResult].
extension LoginResultPatterns on LoginResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LoginResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LoginResult value)  $default,){
final _that = this;
switch (_that) {
case _LoginResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LoginResult value)?  $default,){
final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String token,  bool mesh)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
return $default(_that.token,_that.mesh);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String token,  bool mesh)  $default,) {final _that = this;
switch (_that) {
case _LoginResult():
return $default(_that.token,_that.mesh);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String token,  bool mesh)?  $default,) {final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
return $default(_that.token,_that.mesh);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LoginResult implements LoginResult {
  const _LoginResult({required this.token, required this.mesh});
  factory _LoginResult.fromJson(Map<String, dynamic> json) => _$LoginResultFromJson(json);

@override final  String token;
@override final  bool mesh;

/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoginResultCopyWith<_LoginResult> get copyWith => __$LoginResultCopyWithImpl<_LoginResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LoginResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoginResult&&(identical(other.token, token) || other.token == token)&&(identical(other.mesh, mesh) || other.mesh == mesh));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,token,mesh);

@override
String toString() {
  return 'LoginResult(token: $token, mesh: $mesh)';
}


}

/// @nodoc
abstract mixin class _$LoginResultCopyWith<$Res> implements $LoginResultCopyWith<$Res> {
  factory _$LoginResultCopyWith(_LoginResult value, $Res Function(_LoginResult) _then) = __$LoginResultCopyWithImpl;
@override @useResult
$Res call({
 String token, bool mesh
});




}
/// @nodoc
class __$LoginResultCopyWithImpl<$Res>
    implements _$LoginResultCopyWith<$Res> {
  __$LoginResultCopyWithImpl(this._self, this._then);

  final _LoginResult _self;
  final $Res Function(_LoginResult) _then;

/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? token = null,Object? mesh = null,}) {
  return _then(_LoginResult(
token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,mesh: null == mesh ? _self.mesh : mesh // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
