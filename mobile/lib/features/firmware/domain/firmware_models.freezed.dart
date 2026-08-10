// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'firmware_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FirmwareManifest {

 int get type; String get version; int get sec; int get size; String get sig; String get url;/// Optional release notes from the CDN manifest (BLE spec v2 §7 —
/// the master stores no changelog). Rendered when present.
 String get changelog;
/// Create a copy of FirmwareManifest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareManifestCopyWith<FirmwareManifest> get copyWith => _$FirmwareManifestCopyWithImpl<FirmwareManifest>(this as FirmwareManifest, _$identity);

  /// Serializes this FirmwareManifest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareManifest&&(identical(other.type, type) || other.type == type)&&(identical(other.version, version) || other.version == version)&&(identical(other.sec, sec) || other.sec == sec)&&(identical(other.size, size) || other.size == size)&&(identical(other.sig, sig) || other.sig == sig)&&(identical(other.url, url) || other.url == url)&&(identical(other.changelog, changelog) || other.changelog == changelog));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,version,sec,size,sig,url,changelog);

@override
String toString() {
  return 'FirmwareManifest(type: $type, version: $version, sec: $sec, size: $size, sig: $sig, url: $url, changelog: $changelog)';
}


}

/// @nodoc
abstract mixin class $FirmwareManifestCopyWith<$Res>  {
  factory $FirmwareManifestCopyWith(FirmwareManifest value, $Res Function(FirmwareManifest) _then) = _$FirmwareManifestCopyWithImpl;
@useResult
$Res call({
 int type, String version, int sec, int size, String sig, String url, String changelog
});




}
/// @nodoc
class _$FirmwareManifestCopyWithImpl<$Res>
    implements $FirmwareManifestCopyWith<$Res> {
  _$FirmwareManifestCopyWithImpl(this._self, this._then);

  final FirmwareManifest _self;
  final $Res Function(FirmwareManifest) _then;

/// Create a copy of FirmwareManifest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? version = null,Object? sec = null,Object? size = null,Object? sig = null,Object? url = null,Object? changelog = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,sec: null == sec ? _self.sec : sec // ignore: cast_nullable_to_non_nullable
as int,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sig: null == sig ? _self.sig : sig // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,changelog: null == changelog ? _self.changelog : changelog // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FirmwareManifest].
extension FirmwareManifestPatterns on FirmwareManifest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FirmwareManifest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FirmwareManifest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FirmwareManifest value)  $default,){
final _that = this;
switch (_that) {
case _FirmwareManifest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FirmwareManifest value)?  $default,){
final _that = this;
switch (_that) {
case _FirmwareManifest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int type,  String version,  int sec,  int size,  String sig,  String url,  String changelog)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FirmwareManifest() when $default != null:
return $default(_that.type,_that.version,_that.sec,_that.size,_that.sig,_that.url,_that.changelog);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int type,  String version,  int sec,  int size,  String sig,  String url,  String changelog)  $default,) {final _that = this;
switch (_that) {
case _FirmwareManifest():
return $default(_that.type,_that.version,_that.sec,_that.size,_that.sig,_that.url,_that.changelog);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int type,  String version,  int sec,  int size,  String sig,  String url,  String changelog)?  $default,) {final _that = this;
switch (_that) {
case _FirmwareManifest() when $default != null:
return $default(_that.type,_that.version,_that.sec,_that.size,_that.sig,_that.url,_that.changelog);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FirmwareManifest extends FirmwareManifest {
  const _FirmwareManifest({required this.type, required this.version, this.sec = 0, this.size = 0, this.sig = '', this.url = '', this.changelog = ''}): super._();
  factory _FirmwareManifest.fromJson(Map<String, dynamic> json) => _$FirmwareManifestFromJson(json);

@override final  int type;
@override final  String version;
@override@JsonKey() final  int sec;
@override@JsonKey() final  int size;
@override@JsonKey() final  String sig;
@override@JsonKey() final  String url;
/// Optional release notes from the CDN manifest (BLE spec v2 §7 —
/// the master stores no changelog). Rendered when present.
@override@JsonKey() final  String changelog;

/// Create a copy of FirmwareManifest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FirmwareManifestCopyWith<_FirmwareManifest> get copyWith => __$FirmwareManifestCopyWithImpl<_FirmwareManifest>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FirmwareManifestToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FirmwareManifest&&(identical(other.type, type) || other.type == type)&&(identical(other.version, version) || other.version == version)&&(identical(other.sec, sec) || other.sec == sec)&&(identical(other.size, size) || other.size == size)&&(identical(other.sig, sig) || other.sig == sig)&&(identical(other.url, url) || other.url == url)&&(identical(other.changelog, changelog) || other.changelog == changelog));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,version,sec,size,sig,url,changelog);

@override
String toString() {
  return 'FirmwareManifest(type: $type, version: $version, sec: $sec, size: $size, sig: $sig, url: $url, changelog: $changelog)';
}


}

/// @nodoc
abstract mixin class _$FirmwareManifestCopyWith<$Res> implements $FirmwareManifestCopyWith<$Res> {
  factory _$FirmwareManifestCopyWith(_FirmwareManifest value, $Res Function(_FirmwareManifest) _then) = __$FirmwareManifestCopyWithImpl;
@override @useResult
$Res call({
 int type, String version, int sec, int size, String sig, String url, String changelog
});




}
/// @nodoc
class __$FirmwareManifestCopyWithImpl<$Res>
    implements _$FirmwareManifestCopyWith<$Res> {
  __$FirmwareManifestCopyWithImpl(this._self, this._then);

  final _FirmwareManifest _self;
  final $Res Function(_FirmwareManifest) _then;

/// Create a copy of FirmwareManifest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? version = null,Object? sec = null,Object? size = null,Object? sig = null,Object? url = null,Object? changelog = null,}) {
  return _then(_FirmwareManifest(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,sec: null == sec ? _self.sec : sec // ignore: cast_nullable_to_non_nullable
as int,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sig: null == sig ? _self.sig : sig // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,changelog: null == changelog ? _self.changelog : changelog // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$StoredImage {

 int get type;@JsonKey(name: 'version', readValue: _readVersion) String get version; int get size;
/// Create a copy of StoredImage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoredImageCopyWith<StoredImage> get copyWith => _$StoredImageCopyWithImpl<StoredImage>(this as StoredImage, _$identity);

  /// Serializes this StoredImage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StoredImage&&(identical(other.type, type) || other.type == type)&&(identical(other.version, version) || other.version == version)&&(identical(other.size, size) || other.size == size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,version,size);

@override
String toString() {
  return 'StoredImage(type: $type, version: $version, size: $size)';
}


}

/// @nodoc
abstract mixin class $StoredImageCopyWith<$Res>  {
  factory $StoredImageCopyWith(StoredImage value, $Res Function(StoredImage) _then) = _$StoredImageCopyWithImpl;
@useResult
$Res call({
 int type,@JsonKey(name: 'version', readValue: _readVersion) String version, int size
});




}
/// @nodoc
class _$StoredImageCopyWithImpl<$Res>
    implements $StoredImageCopyWith<$Res> {
  _$StoredImageCopyWithImpl(this._self, this._then);

  final StoredImage _self;
  final $Res Function(StoredImage) _then;

/// Create a copy of StoredImage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? version = null,Object? size = null,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [StoredImage].
extension StoredImagePatterns on StoredImage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StoredImage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StoredImage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StoredImage value)  $default,){
final _that = this;
switch (_that) {
case _StoredImage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StoredImage value)?  $default,){
final _that = this;
switch (_that) {
case _StoredImage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int type, @JsonKey(name: 'version', readValue: _readVersion)  String version,  int size)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StoredImage() when $default != null:
return $default(_that.type,_that.version,_that.size);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int type, @JsonKey(name: 'version', readValue: _readVersion)  String version,  int size)  $default,) {final _that = this;
switch (_that) {
case _StoredImage():
return $default(_that.type,_that.version,_that.size);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int type, @JsonKey(name: 'version', readValue: _readVersion)  String version,  int size)?  $default,) {final _that = this;
switch (_that) {
case _StoredImage() when $default != null:
return $default(_that.type,_that.version,_that.size);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StoredImage implements StoredImage {
  const _StoredImage({this.type = 0, @JsonKey(name: 'version', readValue: _readVersion) this.version = '', this.size = 0});
  factory _StoredImage.fromJson(Map<String, dynamic> json) => _$StoredImageFromJson(json);

@override@JsonKey() final  int type;
@override@JsonKey(name: 'version', readValue: _readVersion) final  String version;
@override@JsonKey() final  int size;

/// Create a copy of StoredImage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StoredImageCopyWith<_StoredImage> get copyWith => __$StoredImageCopyWithImpl<_StoredImage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StoredImageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StoredImage&&(identical(other.type, type) || other.type == type)&&(identical(other.version, version) || other.version == version)&&(identical(other.size, size) || other.size == size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,version,size);

@override
String toString() {
  return 'StoredImage(type: $type, version: $version, size: $size)';
}


}

/// @nodoc
abstract mixin class _$StoredImageCopyWith<$Res> implements $StoredImageCopyWith<$Res> {
  factory _$StoredImageCopyWith(_StoredImage value, $Res Function(_StoredImage) _then) = __$StoredImageCopyWithImpl;
@override @useResult
$Res call({
 int type,@JsonKey(name: 'version', readValue: _readVersion) String version, int size
});




}
/// @nodoc
class __$StoredImageCopyWithImpl<$Res>
    implements _$StoredImageCopyWith<$Res> {
  __$StoredImageCopyWithImpl(this._self, this._then);

  final _StoredImage _self;
  final $Res Function(_StoredImage) _then;

/// Create a copy of StoredImage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? version = null,Object? size = null,}) {
  return _then(_StoredImage(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$FwStatus {

 String get master; List<StoredImage> get images;
/// Create a copy of FwStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FwStatusCopyWith<FwStatus> get copyWith => _$FwStatusCopyWithImpl<FwStatus>(this as FwStatus, _$identity);

  /// Serializes this FwStatus to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FwStatus&&(identical(other.master, master) || other.master == master)&&const DeepCollectionEquality().equals(other.images, images));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,master,const DeepCollectionEquality().hash(images));

@override
String toString() {
  return 'FwStatus(master: $master, images: $images)';
}


}

/// @nodoc
abstract mixin class $FwStatusCopyWith<$Res>  {
  factory $FwStatusCopyWith(FwStatus value, $Res Function(FwStatus) _then) = _$FwStatusCopyWithImpl;
@useResult
$Res call({
 String master, List<StoredImage> images
});




}
/// @nodoc
class _$FwStatusCopyWithImpl<$Res>
    implements $FwStatusCopyWith<$Res> {
  _$FwStatusCopyWithImpl(this._self, this._then);

  final FwStatus _self;
  final $Res Function(FwStatus) _then;

/// Create a copy of FwStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? master = null,Object? images = null,}) {
  return _then(_self.copyWith(
master: null == master ? _self.master : master // ignore: cast_nullable_to_non_nullable
as String,images: null == images ? _self.images : images // ignore: cast_nullable_to_non_nullable
as List<StoredImage>,
  ));
}

}


/// Adds pattern-matching-related methods to [FwStatus].
extension FwStatusPatterns on FwStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FwStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FwStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FwStatus value)  $default,){
final _that = this;
switch (_that) {
case _FwStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FwStatus value)?  $default,){
final _that = this;
switch (_that) {
case _FwStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String master,  List<StoredImage> images)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FwStatus() when $default != null:
return $default(_that.master,_that.images);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String master,  List<StoredImage> images)  $default,) {final _that = this;
switch (_that) {
case _FwStatus():
return $default(_that.master,_that.images);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String master,  List<StoredImage> images)?  $default,) {final _that = this;
switch (_that) {
case _FwStatus() when $default != null:
return $default(_that.master,_that.images);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FwStatus implements FwStatus {
  const _FwStatus({this.master = '', final  List<StoredImage> images = const <StoredImage>[]}): _images = images;
  factory _FwStatus.fromJson(Map<String, dynamic> json) => _$FwStatusFromJson(json);

@override@JsonKey() final  String master;
 final  List<StoredImage> _images;
@override@JsonKey() List<StoredImage> get images {
  if (_images is EqualUnmodifiableListView) return _images;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_images);
}


/// Create a copy of FwStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FwStatusCopyWith<_FwStatus> get copyWith => __$FwStatusCopyWithImpl<_FwStatus>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FwStatusToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FwStatus&&(identical(other.master, master) || other.master == master)&&const DeepCollectionEquality().equals(other._images, _images));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,master,const DeepCollectionEquality().hash(_images));

@override
String toString() {
  return 'FwStatus(master: $master, images: $images)';
}


}

/// @nodoc
abstract mixin class _$FwStatusCopyWith<$Res> implements $FwStatusCopyWith<$Res> {
  factory _$FwStatusCopyWith(_FwStatus value, $Res Function(_FwStatus) _then) = __$FwStatusCopyWithImpl;
@override @useResult
$Res call({
 String master, List<StoredImage> images
});




}
/// @nodoc
class __$FwStatusCopyWithImpl<$Res>
    implements _$FwStatusCopyWith<$Res> {
  __$FwStatusCopyWithImpl(this._self, this._then);

  final _FwStatus _self;
  final $Res Function(_FwStatus) _then;

/// Create a copy of FwStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? master = null,Object? images = null,}) {
  return _then(_FwStatus(
master: null == master ? _self.master : master // ignore: cast_nullable_to_non_nullable
as String,images: null == images ? _self._images : images // ignore: cast_nullable_to_non_nullable
as List<StoredImage>,
  ));
}


}

// dart format on
