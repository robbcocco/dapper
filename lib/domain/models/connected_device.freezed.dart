// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'connected_device.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConnectedDevice {

 String get path; String get label; int get totalBytes; int get availableBytes;
/// Create a copy of ConnectedDevice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectedDeviceCopyWith<ConnectedDevice> get copyWith => _$ConnectedDeviceCopyWithImpl<ConnectedDevice>(this as ConnectedDevice, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectedDevice&&(identical(other.path, path) || other.path == path)&&(identical(other.label, label) || other.label == label)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.availableBytes, availableBytes) || other.availableBytes == availableBytes));
}


@override
int get hashCode => Object.hash(runtimeType,path,label,totalBytes,availableBytes);

@override
String toString() {
  return 'ConnectedDevice(path: $path, label: $label, totalBytes: $totalBytes, availableBytes: $availableBytes)';
}


}

/// @nodoc
abstract mixin class $ConnectedDeviceCopyWith<$Res>  {
  factory $ConnectedDeviceCopyWith(ConnectedDevice value, $Res Function(ConnectedDevice) _then) = _$ConnectedDeviceCopyWithImpl;
@useResult
$Res call({
 String path, String label, int totalBytes, int availableBytes
});




}
/// @nodoc
class _$ConnectedDeviceCopyWithImpl<$Res>
    implements $ConnectedDeviceCopyWith<$Res> {
  _$ConnectedDeviceCopyWithImpl(this._self, this._then);

  final ConnectedDevice _self;
  final $Res Function(ConnectedDevice) _then;

/// Create a copy of ConnectedDevice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? label = null,Object? totalBytes = null,Object? availableBytes = null,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,availableBytes: null == availableBytes ? _self.availableBytes : availableBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ConnectedDevice].
extension ConnectedDevicePatterns on ConnectedDevice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectedDevice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectedDevice() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectedDevice value)  $default,){
final _that = this;
switch (_that) {
case _ConnectedDevice():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectedDevice value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectedDevice() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String label,  int totalBytes,  int availableBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectedDevice() when $default != null:
return $default(_that.path,_that.label,_that.totalBytes,_that.availableBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String label,  int totalBytes,  int availableBytes)  $default,) {final _that = this;
switch (_that) {
case _ConnectedDevice():
return $default(_that.path,_that.label,_that.totalBytes,_that.availableBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String label,  int totalBytes,  int availableBytes)?  $default,) {final _that = this;
switch (_that) {
case _ConnectedDevice() when $default != null:
return $default(_that.path,_that.label,_that.totalBytes,_that.availableBytes);case _:
  return null;

}
}

}

/// @nodoc


class _ConnectedDevice extends ConnectedDevice {
  const _ConnectedDevice({required this.path, required this.label, required this.totalBytes, required this.availableBytes}): super._();
  

@override final  String path;
@override final  String label;
@override final  int totalBytes;
@override final  int availableBytes;

/// Create a copy of ConnectedDevice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectedDeviceCopyWith<_ConnectedDevice> get copyWith => __$ConnectedDeviceCopyWithImpl<_ConnectedDevice>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectedDevice&&(identical(other.path, path) || other.path == path)&&(identical(other.label, label) || other.label == label)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.availableBytes, availableBytes) || other.availableBytes == availableBytes));
}


@override
int get hashCode => Object.hash(runtimeType,path,label,totalBytes,availableBytes);

@override
String toString() {
  return 'ConnectedDevice(path: $path, label: $label, totalBytes: $totalBytes, availableBytes: $availableBytes)';
}


}

/// @nodoc
abstract mixin class _$ConnectedDeviceCopyWith<$Res> implements $ConnectedDeviceCopyWith<$Res> {
  factory _$ConnectedDeviceCopyWith(_ConnectedDevice value, $Res Function(_ConnectedDevice) _then) = __$ConnectedDeviceCopyWithImpl;
@override @useResult
$Res call({
 String path, String label, int totalBytes, int availableBytes
});




}
/// @nodoc
class __$ConnectedDeviceCopyWithImpl<$Res>
    implements _$ConnectedDeviceCopyWith<$Res> {
  __$ConnectedDeviceCopyWithImpl(this._self, this._then);

  final _ConnectedDevice _self;
  final $Res Function(_ConnectedDevice) _then;

/// Create a copy of ConnectedDevice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? label = null,Object? totalBytes = null,Object? availableBytes = null,}) {
  return _then(_ConnectedDevice(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,availableBytes: null == availableBytes ? _self.availableBytes : availableBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
