// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transfer_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$TransferTask {
  String get id => throw _privateConstructorUsedError;
  Song get song => throw _privateConstructorUsedError;
  String get devicePath => throw _privateConstructorUsedError;
  TransferStatus get status => throw _privateConstructorUsedError;
  int get bytesReceived => throw _privateConstructorUsedError;
  int get totalBytes => throw _privateConstructorUsedError;
  String? get errorMessage => throw _privateConstructorUsedError;

  /// Create a copy of TransferTask
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TransferTaskCopyWith<TransferTask> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TransferTaskCopyWith<$Res> {
  factory $TransferTaskCopyWith(
    TransferTask value,
    $Res Function(TransferTask) then,
  ) = _$TransferTaskCopyWithImpl<$Res, TransferTask>;
  @useResult
  $Res call({
    String id,
    Song song,
    String devicePath,
    TransferStatus status,
    int bytesReceived,
    int totalBytes,
    String? errorMessage,
  });

  $SongCopyWith<$Res> get song;
}

/// @nodoc
class _$TransferTaskCopyWithImpl<$Res, $Val extends TransferTask>
    implements $TransferTaskCopyWith<$Res> {
  _$TransferTaskCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TransferTask
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? song = null,
    Object? devicePath = null,
    Object? status = null,
    Object? bytesReceived = null,
    Object? totalBytes = null,
    Object? errorMessage = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            song: null == song
                ? _value.song
                : song // ignore: cast_nullable_to_non_nullable
                      as Song,
            devicePath: null == devicePath
                ? _value.devicePath
                : devicePath // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as TransferStatus,
            bytesReceived: null == bytesReceived
                ? _value.bytesReceived
                : bytesReceived // ignore: cast_nullable_to_non_nullable
                      as int,
            totalBytes: null == totalBytes
                ? _value.totalBytes
                : totalBytes // ignore: cast_nullable_to_non_nullable
                      as int,
            errorMessage: freezed == errorMessage
                ? _value.errorMessage
                : errorMessage // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }

  /// Create a copy of TransferTask
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SongCopyWith<$Res> get song {
    return $SongCopyWith<$Res>(_value.song, (value) {
      return _then(_value.copyWith(song: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$TransferTaskImplCopyWith<$Res>
    implements $TransferTaskCopyWith<$Res> {
  factory _$$TransferTaskImplCopyWith(
    _$TransferTaskImpl value,
    $Res Function(_$TransferTaskImpl) then,
  ) = __$$TransferTaskImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    Song song,
    String devicePath,
    TransferStatus status,
    int bytesReceived,
    int totalBytes,
    String? errorMessage,
  });

  @override
  $SongCopyWith<$Res> get song;
}

/// @nodoc
class __$$TransferTaskImplCopyWithImpl<$Res>
    extends _$TransferTaskCopyWithImpl<$Res, _$TransferTaskImpl>
    implements _$$TransferTaskImplCopyWith<$Res> {
  __$$TransferTaskImplCopyWithImpl(
    _$TransferTaskImpl _value,
    $Res Function(_$TransferTaskImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TransferTask
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? song = null,
    Object? devicePath = null,
    Object? status = null,
    Object? bytesReceived = null,
    Object? totalBytes = null,
    Object? errorMessage = freezed,
  }) {
    return _then(
      _$TransferTaskImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        song: null == song
            ? _value.song
            : song // ignore: cast_nullable_to_non_nullable
                  as Song,
        devicePath: null == devicePath
            ? _value.devicePath
            : devicePath // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as TransferStatus,
        bytesReceived: null == bytesReceived
            ? _value.bytesReceived
            : bytesReceived // ignore: cast_nullable_to_non_nullable
                  as int,
        totalBytes: null == totalBytes
            ? _value.totalBytes
            : totalBytes // ignore: cast_nullable_to_non_nullable
                  as int,
        errorMessage: freezed == errorMessage
            ? _value.errorMessage
            : errorMessage // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$TransferTaskImpl extends _TransferTask {
  const _$TransferTaskImpl({
    required this.id,
    required this.song,
    required this.devicePath,
    this.status = TransferStatus.queued,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.errorMessage,
  }) : super._();

  @override
  final String id;
  @override
  final Song song;
  @override
  final String devicePath;
  @override
  @JsonKey()
  final TransferStatus status;
  @override
  @JsonKey()
  final int bytesReceived;
  @override
  @JsonKey()
  final int totalBytes;
  @override
  final String? errorMessage;

  @override
  String toString() {
    return 'TransferTask(id: $id, song: $song, devicePath: $devicePath, status: $status, bytesReceived: $bytesReceived, totalBytes: $totalBytes, errorMessage: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TransferTaskImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.song, song) || other.song == song) &&
            (identical(other.devicePath, devicePath) ||
                other.devicePath == devicePath) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.bytesReceived, bytesReceived) ||
                other.bytesReceived == bytesReceived) &&
            (identical(other.totalBytes, totalBytes) ||
                other.totalBytes == totalBytes) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    song,
    devicePath,
    status,
    bytesReceived,
    totalBytes,
    errorMessage,
  );

  /// Create a copy of TransferTask
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TransferTaskImplCopyWith<_$TransferTaskImpl> get copyWith =>
      __$$TransferTaskImplCopyWithImpl<_$TransferTaskImpl>(this, _$identity);
}

abstract class _TransferTask extends TransferTask {
  const factory _TransferTask({
    required final String id,
    required final Song song,
    required final String devicePath,
    final TransferStatus status,
    final int bytesReceived,
    final int totalBytes,
    final String? errorMessage,
  }) = _$TransferTaskImpl;
  const _TransferTask._() : super._();

  @override
  String get id;
  @override
  Song get song;
  @override
  String get devicePath;
  @override
  TransferStatus get status;
  @override
  int get bytesReceived;
  @override
  int get totalBytes;
  @override
  String? get errorMessage;

  /// Create a copy of TransferTask
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TransferTaskImplCopyWith<_$TransferTaskImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
