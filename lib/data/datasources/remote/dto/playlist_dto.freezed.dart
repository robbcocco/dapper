// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playlist_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

PlaylistDto _$PlaylistDtoFromJson(Map<String, dynamic> json) {
  return _PlaylistDto.fromJson(json);
}

/// @nodoc
mixin _$PlaylistDto {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get comment => throw _privateConstructorUsedError;
  @JsonKey(name: 'coverArt')
  String? get coverArtId => throw _privateConstructorUsedError;
  @JsonKey(name: 'songCount')
  int get songCount => throw _privateConstructorUsedError;
  int get duration => throw _privateConstructorUsedError;
  @JsonKey(name: 'entry')
  List<SongDto> get songs => throw _privateConstructorUsedError;

  /// Serializes this PlaylistDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PlaylistDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlaylistDtoCopyWith<PlaylistDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlaylistDtoCopyWith<$Res> {
  factory $PlaylistDtoCopyWith(
    PlaylistDto value,
    $Res Function(PlaylistDto) then,
  ) = _$PlaylistDtoCopyWithImpl<$Res, PlaylistDto>;
  @useResult
  $Res call({
    String id,
    String name,
    String? comment,
    @JsonKey(name: 'coverArt') String? coverArtId,
    @JsonKey(name: 'songCount') int songCount,
    int duration,
    @JsonKey(name: 'entry') List<SongDto> songs,
  });
}

/// @nodoc
class _$PlaylistDtoCopyWithImpl<$Res, $Val extends PlaylistDto>
    implements $PlaylistDtoCopyWith<$Res> {
  _$PlaylistDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PlaylistDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? comment = freezed,
    Object? coverArtId = freezed,
    Object? songCount = null,
    Object? duration = null,
    Object? songs = null,
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
            comment: freezed == comment
                ? _value.comment
                : comment // ignore: cast_nullable_to_non_nullable
                      as String?,
            coverArtId: freezed == coverArtId
                ? _value.coverArtId
                : coverArtId // ignore: cast_nullable_to_non_nullable
                      as String?,
            songCount: null == songCount
                ? _value.songCount
                : songCount // ignore: cast_nullable_to_non_nullable
                      as int,
            duration: null == duration
                ? _value.duration
                : duration // ignore: cast_nullable_to_non_nullable
                      as int,
            songs: null == songs
                ? _value.songs
                : songs // ignore: cast_nullable_to_non_nullable
                      as List<SongDto>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlaylistDtoImplCopyWith<$Res>
    implements $PlaylistDtoCopyWith<$Res> {
  factory _$$PlaylistDtoImplCopyWith(
    _$PlaylistDtoImpl value,
    $Res Function(_$PlaylistDtoImpl) then,
  ) = __$$PlaylistDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? comment,
    @JsonKey(name: 'coverArt') String? coverArtId,
    @JsonKey(name: 'songCount') int songCount,
    int duration,
    @JsonKey(name: 'entry') List<SongDto> songs,
  });
}

/// @nodoc
class __$$PlaylistDtoImplCopyWithImpl<$Res>
    extends _$PlaylistDtoCopyWithImpl<$Res, _$PlaylistDtoImpl>
    implements _$$PlaylistDtoImplCopyWith<$Res> {
  __$$PlaylistDtoImplCopyWithImpl(
    _$PlaylistDtoImpl _value,
    $Res Function(_$PlaylistDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PlaylistDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? comment = freezed,
    Object? coverArtId = freezed,
    Object? songCount = null,
    Object? duration = null,
    Object? songs = null,
  }) {
    return _then(
      _$PlaylistDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        comment: freezed == comment
            ? _value.comment
            : comment // ignore: cast_nullable_to_non_nullable
                  as String?,
        coverArtId: freezed == coverArtId
            ? _value.coverArtId
            : coverArtId // ignore: cast_nullable_to_non_nullable
                  as String?,
        songCount: null == songCount
            ? _value.songCount
            : songCount // ignore: cast_nullable_to_non_nullable
                  as int,
        duration: null == duration
            ? _value.duration
            : duration // ignore: cast_nullable_to_non_nullable
                  as int,
        songs: null == songs
            ? _value._songs
            : songs // ignore: cast_nullable_to_non_nullable
                  as List<SongDto>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$PlaylistDtoImpl implements _PlaylistDto {
  const _$PlaylistDtoImpl({
    required this.id,
    required this.name,
    this.comment,
    @JsonKey(name: 'coverArt') this.coverArtId,
    @JsonKey(name: 'songCount') this.songCount = 0,
    this.duration = 0,
    @JsonKey(name: 'entry') final List<SongDto> songs = const [],
  }) : _songs = songs;

  factory _$PlaylistDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$PlaylistDtoImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? comment;
  @override
  @JsonKey(name: 'coverArt')
  final String? coverArtId;
  @override
  @JsonKey(name: 'songCount')
  final int songCount;
  @override
  @JsonKey()
  final int duration;
  final List<SongDto> _songs;
  @override
  @JsonKey(name: 'entry')
  List<SongDto> get songs {
    if (_songs is EqualUnmodifiableListView) return _songs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_songs);
  }

  @override
  String toString() {
    return 'PlaylistDto(id: $id, name: $name, comment: $comment, coverArtId: $coverArtId, songCount: $songCount, duration: $duration, songs: $songs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaylistDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.comment, comment) || other.comment == comment) &&
            (identical(other.coverArtId, coverArtId) ||
                other.coverArtId == coverArtId) &&
            (identical(other.songCount, songCount) ||
                other.songCount == songCount) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            const DeepCollectionEquality().equals(other._songs, _songs));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    comment,
    coverArtId,
    songCount,
    duration,
    const DeepCollectionEquality().hash(_songs),
  );

  /// Create a copy of PlaylistDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaylistDtoImplCopyWith<_$PlaylistDtoImpl> get copyWith =>
      __$$PlaylistDtoImplCopyWithImpl<_$PlaylistDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PlaylistDtoImplToJson(this);
  }
}

abstract class _PlaylistDto implements PlaylistDto {
  const factory _PlaylistDto({
    required final String id,
    required final String name,
    final String? comment,
    @JsonKey(name: 'coverArt') final String? coverArtId,
    @JsonKey(name: 'songCount') final int songCount,
    final int duration,
    @JsonKey(name: 'entry') final List<SongDto> songs,
  }) = _$PlaylistDtoImpl;

  factory _PlaylistDto.fromJson(Map<String, dynamic> json) =
      _$PlaylistDtoImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get comment;
  @override
  @JsonKey(name: 'coverArt')
  String? get coverArtId;
  @override
  @JsonKey(name: 'songCount')
  int get songCount;
  @override
  int get duration;
  @override
  @JsonKey(name: 'entry')
  List<SongDto> get songs;

  /// Create a copy of PlaylistDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlaylistDtoImplCopyWith<_$PlaylistDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
