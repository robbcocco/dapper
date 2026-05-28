// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'artist_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

ArtistDto _$ArtistDtoFromJson(Map<String, dynamic> json) {
  return _ArtistDto.fromJson(json);
}

/// @nodoc
mixin _$ArtistDto {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'coverArt')
  String? get coverArtId => throw _privateConstructorUsedError;
  @JsonKey(name: 'albumCount')
  int get albumCount => throw _privateConstructorUsedError;
  String? get musicBrainzId => throw _privateConstructorUsedError;

  /// Serializes this ArtistDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ArtistDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ArtistDtoCopyWith<ArtistDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ArtistDtoCopyWith<$Res> {
  factory $ArtistDtoCopyWith(ArtistDto value, $Res Function(ArtistDto) then) =
      _$ArtistDtoCopyWithImpl<$Res, ArtistDto>;
  @useResult
  $Res call({
    String id,
    String name,
    @JsonKey(name: 'coverArt') String? coverArtId,
    @JsonKey(name: 'albumCount') int albumCount,
    String? musicBrainzId,
  });
}

/// @nodoc
class _$ArtistDtoCopyWithImpl<$Res, $Val extends ArtistDto>
    implements $ArtistDtoCopyWith<$Res> {
  _$ArtistDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ArtistDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? coverArtId = freezed,
    Object? albumCount = null,
    Object? musicBrainzId = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            coverArtId: freezed == coverArtId
                ? _value.coverArtId
                : coverArtId // ignore: cast_nullable_to_non_nullable
                      as String?,
            albumCount: null == albumCount
                ? _value.albumCount
                : albumCount // ignore: cast_nullable_to_non_nullable
                      as int,
            musicBrainzId: freezed == musicBrainzId
                ? _value.musicBrainzId
                : musicBrainzId // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ArtistDtoImplCopyWith<$Res>
    implements $ArtistDtoCopyWith<$Res> {
  factory _$$ArtistDtoImplCopyWith(
    _$ArtistDtoImpl value,
    $Res Function(_$ArtistDtoImpl) then,
  ) = __$$ArtistDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    @JsonKey(name: 'coverArt') String? coverArtId,
    @JsonKey(name: 'albumCount') int albumCount,
    String? musicBrainzId,
  });
}

/// @nodoc
class __$$ArtistDtoImplCopyWithImpl<$Res>
    extends _$ArtistDtoCopyWithImpl<$Res, _$ArtistDtoImpl>
    implements _$$ArtistDtoImplCopyWith<$Res> {
  __$$ArtistDtoImplCopyWithImpl(
    _$ArtistDtoImpl _value,
    $Res Function(_$ArtistDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ArtistDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? coverArtId = freezed,
    Object? albumCount = null,
    Object? musicBrainzId = freezed,
  }) {
    return _then(
      _$ArtistDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        coverArtId: freezed == coverArtId
            ? _value.coverArtId
            : coverArtId // ignore: cast_nullable_to_non_nullable
                  as String?,
        albumCount: null == albumCount
            ? _value.albumCount
            : albumCount // ignore: cast_nullable_to_non_nullable
                  as int,
        musicBrainzId: freezed == musicBrainzId
            ? _value.musicBrainzId
            : musicBrainzId // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ArtistDtoImpl implements _ArtistDto {
  const _$ArtistDtoImpl({
    required this.id,
    required this.name,
    @JsonKey(name: 'coverArt') this.coverArtId,
    @JsonKey(name: 'albumCount') this.albumCount = 0,
    this.musicBrainzId,
  });

  factory _$ArtistDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$ArtistDtoImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  @JsonKey(name: 'coverArt')
  final String? coverArtId;
  @override
  @JsonKey(name: 'albumCount')
  final int albumCount;
  @override
  final String? musicBrainzId;

  @override
  String toString() {
    return 'ArtistDto(id: $id, name: $name, coverArtId: $coverArtId, albumCount: $albumCount, musicBrainzId: $musicBrainzId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ArtistDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.coverArtId, coverArtId) ||
                other.coverArtId == coverArtId) &&
            (identical(other.albumCount, albumCount) ||
                other.albumCount == albumCount) &&
            (identical(other.musicBrainzId, musicBrainzId) ||
                other.musicBrainzId == musicBrainzId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, name, coverArtId, albumCount, musicBrainzId);

  /// Create a copy of ArtistDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ArtistDtoImplCopyWith<_$ArtistDtoImpl> get copyWith =>
      __$$ArtistDtoImplCopyWithImpl<_$ArtistDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ArtistDtoImplToJson(this);
  }
}

abstract class _ArtistDto implements ArtistDto {
  const factory _ArtistDto({
    required final String id,
    required final String name,
    @JsonKey(name: 'coverArt') final String? coverArtId,
    @JsonKey(name: 'albumCount') final int albumCount,
    final String? musicBrainzId,
  }) = _$ArtistDtoImpl;

  factory _ArtistDto.fromJson(Map<String, dynamic> json) =
      _$ArtistDtoImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  @JsonKey(name: 'coverArt')
  String? get coverArtId;
  @override
  @JsonKey(name: 'albumCount')
  int get albumCount;
  @override
  String? get musicBrainzId;

  /// Create a copy of ArtistDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ArtistDtoImplCopyWith<_$ArtistDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
