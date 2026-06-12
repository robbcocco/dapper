// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'connected_device.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$ConnectedDevice {
  String get path => throw _privateConstructorUsedError;
  String get label => throw _privateConstructorUsedError;
  int get totalBytes => throw _privateConstructorUsedError;
  int get availableBytes => throw _privateConstructorUsedError;
  DeviceProtocol get protocol => throw _privateConstructorUsedError;

  /// Create a copy of ConnectedDevice
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ConnectedDeviceCopyWith<ConnectedDevice> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConnectedDeviceCopyWith<$Res> {
  factory $ConnectedDeviceCopyWith(
    ConnectedDevice value,
    $Res Function(ConnectedDevice) then,
  ) = _$ConnectedDeviceCopyWithImpl<$Res, ConnectedDevice>;
  @useResult
  $Res call({
    String path,
    String label,
    int totalBytes,
    int availableBytes,
    DeviceProtocol protocol,
  });
}

/// @nodoc
class _$ConnectedDeviceCopyWithImpl<$Res, $Val extends ConnectedDevice>
    implements $ConnectedDeviceCopyWith<$Res> {
  _$ConnectedDeviceCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ConnectedDevice
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? path = null,
    Object? label = null,
    Object? totalBytes = null,
    Object? availableBytes = null,
    Object? protocol = null,
  }) {
    return _then(
      _value.copyWith(
            path: null == path
                ? _value.path
                : path // ignore: cast_nullable_to_non_nullable
                      as String,
            label: null == label
                ? _value.label
                : label // ignore: cast_nullable_to_non_nullable
                      as String,
            totalBytes: null == totalBytes
                ? _value.totalBytes
                : totalBytes // ignore: cast_nullable_to_non_nullable
                      as int,
            availableBytes: null == availableBytes
                ? _value.availableBytes
                : availableBytes // ignore: cast_nullable_to_non_nullable
                      as int,
            protocol: null == protocol
                ? _value.protocol
                : protocol // ignore: cast_nullable_to_non_nullable
                      as DeviceProtocol,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ConnectedDeviceImplCopyWith<$Res>
    implements $ConnectedDeviceCopyWith<$Res> {
  factory _$$ConnectedDeviceImplCopyWith(
    _$ConnectedDeviceImpl value,
    $Res Function(_$ConnectedDeviceImpl) then,
  ) = __$$ConnectedDeviceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String path,
    String label,
    int totalBytes,
    int availableBytes,
    DeviceProtocol protocol,
  });
}

/// @nodoc
class __$$ConnectedDeviceImplCopyWithImpl<$Res>
    extends _$ConnectedDeviceCopyWithImpl<$Res, _$ConnectedDeviceImpl>
    implements _$$ConnectedDeviceImplCopyWith<$Res> {
  __$$ConnectedDeviceImplCopyWithImpl(
    _$ConnectedDeviceImpl _value,
    $Res Function(_$ConnectedDeviceImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ConnectedDevice
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? path = null,
    Object? label = null,
    Object? totalBytes = null,
    Object? availableBytes = null,
    Object? protocol = null,
  }) {
    return _then(
      _$ConnectedDeviceImpl(
        path: null == path
            ? _value.path
            : path // ignore: cast_nullable_to_non_nullable
                  as String,
        label: null == label
            ? _value.label
            : label // ignore: cast_nullable_to_non_nullable
                  as String,
        totalBytes: null == totalBytes
            ? _value.totalBytes
            : totalBytes // ignore: cast_nullable_to_non_nullable
                  as int,
        availableBytes: null == availableBytes
            ? _value.availableBytes
            : availableBytes // ignore: cast_nullable_to_non_nullable
                  as int,
        protocol: null == protocol
            ? _value.protocol
            : protocol // ignore: cast_nullable_to_non_nullable
                  as DeviceProtocol,
      ),
    );
  }
}

/// @nodoc

class _$ConnectedDeviceImpl extends _ConnectedDevice {
  const _$ConnectedDeviceImpl({
    required this.path,
    required this.label,
    required this.totalBytes,
    required this.availableBytes,
    this.protocol = DeviceProtocol.filesystem,
  }) : super._();

  @override
  final String path;
  @override
  final String label;
  @override
  final int totalBytes;
  @override
  final int availableBytes;
  @override
  @JsonKey()
  final DeviceProtocol protocol;

  @override
  String toString() {
    return 'ConnectedDevice(path: $path, label: $label, totalBytes: $totalBytes, availableBytes: $availableBytes, protocol: $protocol)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConnectedDeviceImpl &&
            (identical(other.path, path) || other.path == path) &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.totalBytes, totalBytes) ||
                other.totalBytes == totalBytes) &&
            (identical(other.availableBytes, availableBytes) ||
                other.availableBytes == availableBytes) &&
            (identical(other.protocol, protocol) ||
                other.protocol == protocol));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    path,
    label,
    totalBytes,
    availableBytes,
    protocol,
  );

  /// Create a copy of ConnectedDevice
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ConnectedDeviceImplCopyWith<_$ConnectedDeviceImpl> get copyWith =>
      __$$ConnectedDeviceImplCopyWithImpl<_$ConnectedDeviceImpl>(
        this,
        _$identity,
      );
}

abstract class _ConnectedDevice extends ConnectedDevice {
  const factory _ConnectedDevice({
    required final String path,
    required final String label,
    required final int totalBytes,
    required final int availableBytes,
    final DeviceProtocol protocol,
  }) = _$ConnectedDeviceImpl;
  const _ConnectedDevice._() : super._();

  @override
  String get path;
  @override
  String get label;
  @override
  int get totalBytes;
  @override
  int get availableBytes;
  @override
  DeviceProtocol get protocol;

  /// Create a copy of ConnectedDevice
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ConnectedDeviceImplCopyWith<_$ConnectedDeviceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
