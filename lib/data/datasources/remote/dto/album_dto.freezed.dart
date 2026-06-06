// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'album_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

AlbumDto _$AlbumDtoFromJson(Map<String, dynamic> json) {
  return _AlbumDto.fromJson(json);
}

/// @nodoc
mixin _$AlbumDto {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'artistId')
  String? get artistId => throw _privateConstructorUsedError;
  String? get artist => throw _privateConstructorUsedError;
  @JsonKey(name: 'coverArt')
  String? get coverArtId => throw _privateConstructorUsedError;
  int? get year => throw _privateConstructorUsedError;
  String? get genre => throw _privateConstructorUsedError;
  @JsonKey(name: 'songCount')
  int get songCount => throw _privateConstructorUsedError;
  int get duration => throw _privateConstructorUsedError;
  @JsonKey(name: 'song')
  List<SongDto> get songs => throw _privateConstructorUsedError;
  @JsonKey(name: 'userRating')
  int? get userRating => throw _privateConstructorUsedError;

  /// Serializes this AlbumDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AlbumDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AlbumDtoCopyWith<AlbumDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AlbumDtoCopyWith<$Res> {
  factory $AlbumDtoCopyWith(AlbumDto value, $Res Function(AlbumDto) then) =
      _$AlbumDtoCopyWithImpl<$Res, AlbumDto>;
  @useResult
  $Res call({
    String id,
    String name,
    @JsonKey(name: 'artistId') String? artistId,
    String? artist,
    @JsonKey(name: 'coverArt') String? coverArtId,
    int? year,
    String? genre,
    @JsonKey(name: 'songCount') int songCount,
    int duration,
    @JsonKey(name: 'song') List<SongDto> songs,
    @JsonKey(name: 'userRating') int? userRating,
  });
}

/// @nodoc
class _$AlbumDtoCopyWithImpl<$Res, $Val extends AlbumDto>
    implements $AlbumDtoCopyWith<$Res> {
  _$AlbumDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AlbumDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? artistId = freezed,
    Object? artist = freezed,
    Object? coverArtId = freezed,
    Object? year = freezed,
    Object? genre = freezed,
    Object? songCount = null,
    Object? duration = null,
    Object? songs = null,
    Object? userRating = freezed,
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
            artistId: freezed == artistId
                ? _value.artistId
                : artistId // ignore: cast_nullable_to_non_nullable
                      as String?,
            artist: freezed == artist
                ? _value.artist
                : artist // ignore: cast_nullable_to_non_nullable
                      as String?,
            coverArtId: freezed == coverArtId
                ? _value.coverArtId
                : coverArtId // ignore: cast_nullable_to_non_nullable
                      as String?,
            year: freezed == year
                ? _value.year
                : year // ignore: cast_nullable_to_non_nullable
                      as int?,
            genre: freezed == genre
                ? _value.genre
                : genre // ignore: cast_nullable_to_non_nullable
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
            userRating: freezed == userRating
                ? _value.userRating
                : userRating // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$AlbumDtoImplCopyWith<$Res>
    implements $AlbumDtoCopyWith<$Res> {
  factory _$$AlbumDtoImplCopyWith(
    _$AlbumDtoImpl value,
    $Res Function(_$AlbumDtoImpl) then,
  ) = __$$AlbumDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    @JsonKey(name: 'artistId') String? artistId,
    String? artist,
    @JsonKey(name: 'coverArt') String? coverArtId,
    int? year,
    String? genre,
    @JsonKey(name: 'songCount') int songCount,
    int duration,
    @JsonKey(name: 'song') List<SongDto> songs,
    @JsonKey(name: 'userRating') int? userRating,
  });
}

/// @nodoc
class __$$AlbumDtoImplCopyWithImpl<$Res>
    extends _$AlbumDtoCopyWithImpl<$Res, _$AlbumDtoImpl>
    implements _$$AlbumDtoImplCopyWith<$Res> {
  __$$AlbumDtoImplCopyWithImpl(
    _$AlbumDtoImpl _value,
    $Res Function(_$AlbumDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AlbumDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? artistId = freezed,
    Object? artist = freezed,
    Object? coverArtId = freezed,
    Object? year = freezed,
    Object? genre = freezed,
    Object? songCount = null,
    Object? duration = null,
    Object? songs = null,
    Object? userRating = freezed,
  }) {
    return _then(
      _$AlbumDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        artistId: freezed == artistId
            ? _value.artistId
            : artistId // ignore: cast_nullable_to_non_nullable
                  as String?,
        artist: freezed == artist
            ? _value.artist
            : artist // ignore: cast_nullable_to_non_nullable
                  as String?,
        coverArtId: freezed == coverArtId
            ? _value.coverArtId
            : coverArtId // ignore: cast_nullable_to_non_nullable
                  as String?,
        year: freezed == year
            ? _value.year
            : year // ignore: cast_nullable_to_non_nullable
                  as int?,
        genre: freezed == genre
            ? _value.genre
            : genre // ignore: cast_nullable_to_non_nullable
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
        userRating: freezed == userRating
            ? _value.userRating
            : userRating // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$AlbumDtoImpl implements _AlbumDto {
  const _$AlbumDtoImpl({
    required this.id,
    required this.name,
    @JsonKey(name: 'artistId') this.artistId,
    this.artist,
    @JsonKey(name: 'coverArt') this.coverArtId,
    this.year,
    this.genre,
    @JsonKey(name: 'songCount') this.songCount = 0,
    this.duration = 0,
    @JsonKey(name: 'song') final List<SongDto> songs = const [],
    @JsonKey(name: 'userRating') this.userRating,
  }) : _songs = songs;

  factory _$AlbumDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$AlbumDtoImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  @JsonKey(name: 'artistId')
  final String? artistId;
  @override
  final String? artist;
  @override
  @JsonKey(name: 'coverArt')
  final String? coverArtId;
  @override
  final int? year;
  @override
  final String? genre;
  @override
  @JsonKey(name: 'songCount')
  final int songCount;
  @override
  @JsonKey()
  final int duration;
  final List<SongDto> _songs;
  @override
  @JsonKey(name: 'song')
  List<SongDto> get songs {
    if (_songs is EqualUnmodifiableListView) return _songs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_songs);
  }

  @override
  @JsonKey(name: 'userRating')
  final int? userRating;

  @override
  String toString() {
    return 'AlbumDto(id: $id, name: $name, artistId: $artistId, artist: $artist, coverArtId: $coverArtId, year: $year, genre: $genre, songCount: $songCount, duration: $duration, songs: $songs, userRating: $userRating)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AlbumDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.artistId, artistId) ||
                other.artistId == artistId) &&
            (identical(other.artist, artist) || other.artist == artist) &&
            (identical(other.coverArtId, coverArtId) ||
                other.coverArtId == coverArtId) &&
            (identical(other.year, year) || other.year == year) &&
            (identical(other.genre, genre) || other.genre == genre) &&
            (identical(other.songCount, songCount) ||
                other.songCount == songCount) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            const DeepCollectionEquality().equals(other._songs, _songs) &&
            (identical(other.userRating, userRating) ||
                other.userRating == userRating));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    artistId,
    artist,
    coverArtId,
    year,
    genre,
    songCount,
    duration,
    const DeepCollectionEquality().hash(_songs),
    userRating,
  );

  /// Create a copy of AlbumDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AlbumDtoImplCopyWith<_$AlbumDtoImpl> get copyWith =>
      __$$AlbumDtoImplCopyWithImpl<_$AlbumDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AlbumDtoImplToJson(this);
  }
}

abstract class _AlbumDto implements AlbumDto {
  const factory _AlbumDto({
    required final String id,
    required final String name,
    @JsonKey(name: 'artistId') final String? artistId,
    final String? artist,
    @JsonKey(name: 'coverArt') final String? coverArtId,
    final int? year,
    final String? genre,
    @JsonKey(name: 'songCount') final int songCount,
    final int duration,
    @JsonKey(name: 'song') final List<SongDto> songs,
    @JsonKey(name: 'userRating') final int? userRating,
  }) = _$AlbumDtoImpl;

  factory _AlbumDto.fromJson(Map<String, dynamic> json) =
      _$AlbumDtoImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  @JsonKey(name: 'artistId')
  String? get artistId;
  @override
  String? get artist;
  @override
  @JsonKey(name: 'coverArt')
  String? get coverArtId;
  @override
  int? get year;
  @override
  String? get genre;
  @override
  @JsonKey(name: 'songCount')
  int get songCount;
  @override
  int get duration;
  @override
  @JsonKey(name: 'song')
  List<SongDto> get songs;
  @override
  @JsonKey(name: 'userRating')
  int? get userRating;

  /// Create a copy of AlbumDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AlbumDtoImplCopyWith<_$AlbumDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
