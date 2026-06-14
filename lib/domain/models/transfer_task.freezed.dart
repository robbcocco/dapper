// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transfer_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TransferTask {

 String get id; Song get song; String get devicePath; TransferStatus get status; int get bytesReceived; int get totalBytes; String? get errorMessage;/// Non-null when this task is part of a bulk-zip group. All tasks in the
/// group share the same id; the engine processes the group as a single
/// download + extract operation.
 String? get zipGroupId;/// Album/artist id passed to /rest/download. Only set on the "leader"
/// task within a [zipGroupId] — the leader's execution drives the zip
/// fetch and dispatches each extracted entry to its sibling task.
 String? get zipSourceId;
/// Create a copy of TransferTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransferTaskCopyWith<TransferTask> get copyWith => _$TransferTaskCopyWithImpl<TransferTask>(this as TransferTask, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TransferTask&&(identical(other.id, id) || other.id == id)&&(identical(other.song, song) || other.song == song)&&(identical(other.devicePath, devicePath) || other.devicePath == devicePath)&&(identical(other.status, status) || other.status == status)&&(identical(other.bytesReceived, bytesReceived) || other.bytesReceived == bytesReceived)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.zipGroupId, zipGroupId) || other.zipGroupId == zipGroupId)&&(identical(other.zipSourceId, zipSourceId) || other.zipSourceId == zipSourceId));
}


@override
int get hashCode => Object.hash(runtimeType,id,song,devicePath,status,bytesReceived,totalBytes,errorMessage,zipGroupId,zipSourceId);

@override
String toString() {
  return 'TransferTask(id: $id, song: $song, devicePath: $devicePath, status: $status, bytesReceived: $bytesReceived, totalBytes: $totalBytes, errorMessage: $errorMessage, zipGroupId: $zipGroupId, zipSourceId: $zipSourceId)';
}


}

/// @nodoc
abstract mixin class $TransferTaskCopyWith<$Res>  {
  factory $TransferTaskCopyWith(TransferTask value, $Res Function(TransferTask) _then) = _$TransferTaskCopyWithImpl;
@useResult
$Res call({
 String id, Song song, String devicePath, TransferStatus status, int bytesReceived, int totalBytes, String? errorMessage, String? zipGroupId, String? zipSourceId
});


$SongCopyWith<$Res> get song;

}
/// @nodoc
class _$TransferTaskCopyWithImpl<$Res>
    implements $TransferTaskCopyWith<$Res> {
  _$TransferTaskCopyWithImpl(this._self, this._then);

  final TransferTask _self;
  final $Res Function(TransferTask) _then;

/// Create a copy of TransferTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? song = null,Object? devicePath = null,Object? status = null,Object? bytesReceived = null,Object? totalBytes = null,Object? errorMessage = freezed,Object? zipGroupId = freezed,Object? zipSourceId = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,song: null == song ? _self.song : song // ignore: cast_nullable_to_non_nullable
as Song,devicePath: null == devicePath ? _self.devicePath : devicePath // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TransferStatus,bytesReceived: null == bytesReceived ? _self.bytesReceived : bytesReceived // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,zipGroupId: freezed == zipGroupId ? _self.zipGroupId : zipGroupId // ignore: cast_nullable_to_non_nullable
as String?,zipSourceId: freezed == zipSourceId ? _self.zipSourceId : zipSourceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of TransferTask
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SongCopyWith<$Res> get song {
  
  return $SongCopyWith<$Res>(_self.song, (value) {
    return _then(_self.copyWith(song: value));
  });
}
}


/// Adds pattern-matching-related methods to [TransferTask].
extension TransferTaskPatterns on TransferTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TransferTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TransferTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TransferTask value)  $default,){
final _that = this;
switch (_that) {
case _TransferTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TransferTask value)?  $default,){
final _that = this;
switch (_that) {
case _TransferTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  Song song,  String devicePath,  TransferStatus status,  int bytesReceived,  int totalBytes,  String? errorMessage,  String? zipGroupId,  String? zipSourceId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TransferTask() when $default != null:
return $default(_that.id,_that.song,_that.devicePath,_that.status,_that.bytesReceived,_that.totalBytes,_that.errorMessage,_that.zipGroupId,_that.zipSourceId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  Song song,  String devicePath,  TransferStatus status,  int bytesReceived,  int totalBytes,  String? errorMessage,  String? zipGroupId,  String? zipSourceId)  $default,) {final _that = this;
switch (_that) {
case _TransferTask():
return $default(_that.id,_that.song,_that.devicePath,_that.status,_that.bytesReceived,_that.totalBytes,_that.errorMessage,_that.zipGroupId,_that.zipSourceId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  Song song,  String devicePath,  TransferStatus status,  int bytesReceived,  int totalBytes,  String? errorMessage,  String? zipGroupId,  String? zipSourceId)?  $default,) {final _that = this;
switch (_that) {
case _TransferTask() when $default != null:
return $default(_that.id,_that.song,_that.devicePath,_that.status,_that.bytesReceived,_that.totalBytes,_that.errorMessage,_that.zipGroupId,_that.zipSourceId);case _:
  return null;

}
}

}

/// @nodoc


class _TransferTask extends TransferTask {
  const _TransferTask({required this.id, required this.song, required this.devicePath, this.status = TransferStatus.queued, this.bytesReceived = 0, this.totalBytes = 0, this.errorMessage, this.zipGroupId, this.zipSourceId}): super._();
  

@override final  String id;
@override final  Song song;
@override final  String devicePath;
@override@JsonKey() final  TransferStatus status;
@override@JsonKey() final  int bytesReceived;
@override@JsonKey() final  int totalBytes;
@override final  String? errorMessage;
/// Non-null when this task is part of a bulk-zip group. All tasks in the
/// group share the same id; the engine processes the group as a single
/// download + extract operation.
@override final  String? zipGroupId;
/// Album/artist id passed to /rest/download. Only set on the "leader"
/// task within a [zipGroupId] — the leader's execution drives the zip
/// fetch and dispatches each extracted entry to its sibling task.
@override final  String? zipSourceId;

/// Create a copy of TransferTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TransferTaskCopyWith<_TransferTask> get copyWith => __$TransferTaskCopyWithImpl<_TransferTask>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TransferTask&&(identical(other.id, id) || other.id == id)&&(identical(other.song, song) || other.song == song)&&(identical(other.devicePath, devicePath) || other.devicePath == devicePath)&&(identical(other.status, status) || other.status == status)&&(identical(other.bytesReceived, bytesReceived) || other.bytesReceived == bytesReceived)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.zipGroupId, zipGroupId) || other.zipGroupId == zipGroupId)&&(identical(other.zipSourceId, zipSourceId) || other.zipSourceId == zipSourceId));
}


@override
int get hashCode => Object.hash(runtimeType,id,song,devicePath,status,bytesReceived,totalBytes,errorMessage,zipGroupId,zipSourceId);

@override
String toString() {
  return 'TransferTask(id: $id, song: $song, devicePath: $devicePath, status: $status, bytesReceived: $bytesReceived, totalBytes: $totalBytes, errorMessage: $errorMessage, zipGroupId: $zipGroupId, zipSourceId: $zipSourceId)';
}


}

/// @nodoc
abstract mixin class _$TransferTaskCopyWith<$Res> implements $TransferTaskCopyWith<$Res> {
  factory _$TransferTaskCopyWith(_TransferTask value, $Res Function(_TransferTask) _then) = __$TransferTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, Song song, String devicePath, TransferStatus status, int bytesReceived, int totalBytes, String? errorMessage, String? zipGroupId, String? zipSourceId
});


@override $SongCopyWith<$Res> get song;

}
/// @nodoc
class __$TransferTaskCopyWithImpl<$Res>
    implements _$TransferTaskCopyWith<$Res> {
  __$TransferTaskCopyWithImpl(this._self, this._then);

  final _TransferTask _self;
  final $Res Function(_TransferTask) _then;

/// Create a copy of TransferTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? song = null,Object? devicePath = null,Object? status = null,Object? bytesReceived = null,Object? totalBytes = null,Object? errorMessage = freezed,Object? zipGroupId = freezed,Object? zipSourceId = freezed,}) {
  return _then(_TransferTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,song: null == song ? _self.song : song // ignore: cast_nullable_to_non_nullable
as Song,devicePath: null == devicePath ? _self.devicePath : devicePath // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TransferStatus,bytesReceived: null == bytesReceived ? _self.bytesReceived : bytesReceived // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,zipGroupId: freezed == zipGroupId ? _self.zipGroupId : zipGroupId // ignore: cast_nullable_to_non_nullable
as String?,zipSourceId: freezed == zipSourceId ? _self.zipSourceId : zipSourceId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of TransferTask
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SongCopyWith<$Res> get song {
  
  return $SongCopyWith<$Res>(_self.song, (value) {
    return _then(_self.copyWith(song: value));
  });
}
}

// dart format on
