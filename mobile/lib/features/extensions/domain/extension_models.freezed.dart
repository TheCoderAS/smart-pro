// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'extension_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ExtensionInfo {

 int get slot; int get addr; bool get online; int get type; int get rev; String get fw; String get name; String get sw1; String get sw2; int get fails; bool get stuck; String? get avail;
/// Create a copy of ExtensionInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtensionInfoCopyWith<ExtensionInfo> get copyWith => _$ExtensionInfoCopyWithImpl<ExtensionInfo>(this as ExtensionInfo, _$identity);

  /// Serializes this ExtensionInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtensionInfo&&(identical(other.slot, slot) || other.slot == slot)&&(identical(other.addr, addr) || other.addr == addr)&&(identical(other.online, online) || other.online == online)&&(identical(other.type, type) || other.type == type)&&(identical(other.rev, rev) || other.rev == rev)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.name, name) || other.name == name)&&(identical(other.sw1, sw1) || other.sw1 == sw1)&&(identical(other.sw2, sw2) || other.sw2 == sw2)&&(identical(other.fails, fails) || other.fails == fails)&&(identical(other.stuck, stuck) || other.stuck == stuck)&&(identical(other.avail, avail) || other.avail == avail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,slot,addr,online,type,rev,fw,name,sw1,sw2,fails,stuck,avail);

@override
String toString() {
  return 'ExtensionInfo(slot: $slot, addr: $addr, online: $online, type: $type, rev: $rev, fw: $fw, name: $name, sw1: $sw1, sw2: $sw2, fails: $fails, stuck: $stuck, avail: $avail)';
}


}

/// @nodoc
abstract mixin class $ExtensionInfoCopyWith<$Res>  {
  factory $ExtensionInfoCopyWith(ExtensionInfo value, $Res Function(ExtensionInfo) _then) = _$ExtensionInfoCopyWithImpl;
@useResult
$Res call({
 int slot, int addr, bool online, int type, int rev, String fw, String name, String sw1, String sw2, int fails, bool stuck, String? avail
});




}
/// @nodoc
class _$ExtensionInfoCopyWithImpl<$Res>
    implements $ExtensionInfoCopyWith<$Res> {
  _$ExtensionInfoCopyWithImpl(this._self, this._then);

  final ExtensionInfo _self;
  final $Res Function(ExtensionInfo) _then;

/// Create a copy of ExtensionInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? slot = null,Object? addr = null,Object? online = null,Object? type = null,Object? rev = null,Object? fw = null,Object? name = null,Object? sw1 = null,Object? sw2 = null,Object? fails = null,Object? stuck = null,Object? avail = freezed,}) {
  return _then(_self.copyWith(
slot: null == slot ? _self.slot : slot // ignore: cast_nullable_to_non_nullable
as int,addr: null == addr ? _self.addr : addr // ignore: cast_nullable_to_non_nullable
as int,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as int,rev: null == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sw1: null == sw1 ? _self.sw1 : sw1 // ignore: cast_nullable_to_non_nullable
as String,sw2: null == sw2 ? _self.sw2 : sw2 // ignore: cast_nullable_to_non_nullable
as String,fails: null == fails ? _self.fails : fails // ignore: cast_nullable_to_non_nullable
as int,stuck: null == stuck ? _self.stuck : stuck // ignore: cast_nullable_to_non_nullable
as bool,avail: freezed == avail ? _self.avail : avail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ExtensionInfo].
extension ExtensionInfoPatterns on ExtensionInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExtensionInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExtensionInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExtensionInfo value)  $default,){
final _that = this;
switch (_that) {
case _ExtensionInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExtensionInfo value)?  $default,){
final _that = this;
switch (_that) {
case _ExtensionInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int slot,  int addr,  bool online,  int type,  int rev,  String fw,  String name,  String sw1,  String sw2,  int fails,  bool stuck,  String? avail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExtensionInfo() when $default != null:
return $default(_that.slot,_that.addr,_that.online,_that.type,_that.rev,_that.fw,_that.name,_that.sw1,_that.sw2,_that.fails,_that.stuck,_that.avail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int slot,  int addr,  bool online,  int type,  int rev,  String fw,  String name,  String sw1,  String sw2,  int fails,  bool stuck,  String? avail)  $default,) {final _that = this;
switch (_that) {
case _ExtensionInfo():
return $default(_that.slot,_that.addr,_that.online,_that.type,_that.rev,_that.fw,_that.name,_that.sw1,_that.sw2,_that.fails,_that.stuck,_that.avail);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int slot,  int addr,  bool online,  int type,  int rev,  String fw,  String name,  String sw1,  String sw2,  int fails,  bool stuck,  String? avail)?  $default,) {final _that = this;
switch (_that) {
case _ExtensionInfo() when $default != null:
return $default(_that.slot,_that.addr,_that.online,_that.type,_that.rev,_that.fw,_that.name,_that.sw1,_that.sw2,_that.fails,_that.stuck,_that.avail);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExtensionInfo implements ExtensionInfo {
  const _ExtensionInfo({required this.slot, this.addr = 0, this.online = false, this.type = 0, this.rev = 0, this.fw = '', this.name = '', this.sw1 = '', this.sw2 = '', this.fails = 0, this.stuck = false, this.avail});
  factory _ExtensionInfo.fromJson(Map<String, dynamic> json) => _$ExtensionInfoFromJson(json);

@override final  int slot;
@override@JsonKey() final  int addr;
@override@JsonKey() final  bool online;
@override@JsonKey() final  int type;
@override@JsonKey() final  int rev;
@override@JsonKey() final  String fw;
@override@JsonKey() final  String name;
@override@JsonKey() final  String sw1;
@override@JsonKey() final  String sw2;
@override@JsonKey() final  int fails;
@override@JsonKey() final  bool stuck;
@override final  String? avail;

/// Create a copy of ExtensionInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExtensionInfoCopyWith<_ExtensionInfo> get copyWith => __$ExtensionInfoCopyWithImpl<_ExtensionInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExtensionInfoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExtensionInfo&&(identical(other.slot, slot) || other.slot == slot)&&(identical(other.addr, addr) || other.addr == addr)&&(identical(other.online, online) || other.online == online)&&(identical(other.type, type) || other.type == type)&&(identical(other.rev, rev) || other.rev == rev)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.name, name) || other.name == name)&&(identical(other.sw1, sw1) || other.sw1 == sw1)&&(identical(other.sw2, sw2) || other.sw2 == sw2)&&(identical(other.fails, fails) || other.fails == fails)&&(identical(other.stuck, stuck) || other.stuck == stuck)&&(identical(other.avail, avail) || other.avail == avail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,slot,addr,online,type,rev,fw,name,sw1,sw2,fails,stuck,avail);

@override
String toString() {
  return 'ExtensionInfo(slot: $slot, addr: $addr, online: $online, type: $type, rev: $rev, fw: $fw, name: $name, sw1: $sw1, sw2: $sw2, fails: $fails, stuck: $stuck, avail: $avail)';
}


}

/// @nodoc
abstract mixin class _$ExtensionInfoCopyWith<$Res> implements $ExtensionInfoCopyWith<$Res> {
  factory _$ExtensionInfoCopyWith(_ExtensionInfo value, $Res Function(_ExtensionInfo) _then) = __$ExtensionInfoCopyWithImpl;
@override @useResult
$Res call({
 int slot, int addr, bool online, int type, int rev, String fw, String name, String sw1, String sw2, int fails, bool stuck, String? avail
});




}
/// @nodoc
class __$ExtensionInfoCopyWithImpl<$Res>
    implements _$ExtensionInfoCopyWith<$Res> {
  __$ExtensionInfoCopyWithImpl(this._self, this._then);

  final _ExtensionInfo _self;
  final $Res Function(_ExtensionInfo) _then;

/// Create a copy of ExtensionInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? slot = null,Object? addr = null,Object? online = null,Object? type = null,Object? rev = null,Object? fw = null,Object? name = null,Object? sw1 = null,Object? sw2 = null,Object? fails = null,Object? stuck = null,Object? avail = freezed,}) {
  return _then(_ExtensionInfo(
slot: null == slot ? _self.slot : slot // ignore: cast_nullable_to_non_nullable
as int,addr: null == addr ? _self.addr : addr // ignore: cast_nullable_to_non_nullable
as int,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as int,rev: null == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sw1: null == sw1 ? _self.sw1 : sw1 // ignore: cast_nullable_to_non_nullable
as String,sw2: null == sw2 ? _self.sw2 : sw2 // ignore: cast_nullable_to_non_nullable
as String,fails: null == fails ? _self.fails : fails // ignore: cast_nullable_to_non_nullable
as int,stuck: null == stuck ? _self.stuck : stuck // ignore: cast_nullable_to_non_nullable
as bool,avail: freezed == avail ? _self.avail : avail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
