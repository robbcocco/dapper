// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'song_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

SongDto _$SongDtoFromJson(Map<String, dynamic> json) {
  return _SongDto.fromJson(json);
}

/// @nodoc
mixin _$SongDto {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  @JsonKey(name: 'albumId')
  String? get albumId => throw _privateConstructorUsedError;
  @JsonKey(name: 'artistId')
  String? get artistId => throw _privateConstructorUsedError;
  String? get album => throw _privateConstructorUsedError;
  String? get artist => throw _privateConstructorUsedError;
  int? get duration => throw _privateConstructorUsedError;
  int? get bitRate => throw _privateConstructorUsedError;
  String? get contentType => throw _privateConstructorUsedError;
  String? get suffix => throw _privateConstructorUsedError;
  int? get size => throw _privateConstructorUsedError;
  @JsonKey(name: 'coverArt')
  String? get coverArtId => throw _privateConstructorUsedError;
  int? get track => throw _privateConstructorUsedError;
  @JsonKey(name: 'discNumber')
  int? get discNumber => throw _privateConstructorUsedError;
  int? get year => throw _privateConstructorUsedError;
  String? get genre => throw _privateConstructorUsedError;
  @JsonKey(name: 'albumArtist')
  String? get albumArtist => throw _privateConstructorUsedError; // Subsonic `userRating` (1-5) — present only when the user has rated.
  @JsonKey(name: 'userRating')
  int? get userRating => throw _privateConstructorUsedError;

  /// Serializes this SongDto to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SongDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SongDtoCopyWith<SongDto> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SongDtoCopyWith<$Res> {
  factory $SongDtoCopyWith(SongDto value, $Res Function(SongDto) then) =
      _$SongDtoCopyWithImpl<$Res, SongDto>;
  @useResult
  $Res call({
    String id,
    String title,
    @JsonKey(name: 'albumId') String? albumId,
    @JsonKey(name: 'artistId') String? artistId,
    String? album,
    String? artist,
    int? duration,
    int? bitRate,
    String? contentType,
    String? suffix,
    int? size,
    @JsonKey(name: 'coverArt') String? coverArtId,
    int? track,
    @JsonKey(name: 'discNumber') int? discNumber,
    int? year,
    String? genre,
    @JsonKey(name: 'albumArtist') String? albumArtist,
    @JsonKey(name: 'userRating') int? userRating,
  });
}

/// @nodoc
class _$SongDtoCopyWithImpl<$Res, $Val extends SongDto>
    implements $SongDtoCopyWith<$Res> {
  _$SongDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SongDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? albumId = freezed,
    Object? artistId = freezed,
    Object? album = freezed,
    Object? artist = freezed,
    Object? duration = freezed,
    Object? bitRate = freezed,
    Object? contentType = freezed,
    Object? suffix = freezed,
    Object? size = freezed,
    Object? coverArtId = freezed,
    Object? track = freezed,
    Object? discNumber = freezed,
    Object? year = freezed,
    Object? genre = freezed,
    Object? albumArtist = freezed,
    Object? userRating = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            title: null == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String,
            albumId: freezed == albumId
                ? _value.albumId
                : albumId // ignore: cast_nullable_to_non_nullable
                      as String?,
            artistId: freezed == artistId
                ? _value.artistId
                : artistId // ignore: cast_nullable_to_non_nullable
                      as String?,
            album: freezed == album
                ? _value.album
                : album // ignore: cast_nullable_to_non_nullable
                      as String?,
            artist: freezed == artist
                ? _value.artist
                : artist // ignore: cast_nullable_to_non_nullable
                      as String?,
            duration: freezed == duration
                ? _value.duration
                : duration // ignore: cast_nullable_to_non_nullable
                      as int?,
            bitRate: freezed == bitRate
                ? _value.bitRate
                : bitRate // ignore: cast_nullable_to_non_nullable
                      as int?,
            contentType: freezed == contentType
                ? _value.contentType
                : contentType // ignore: cast_nullable_to_non_nullable
                      as String?,
            suffix: freezed == suffix
                ? _value.suffix
                : suffix // ignore: cast_nullable_to_non_nullable
                      as String?,
            size: freezed == size
                ? _value.size
                : size // ignore: cast_nullable_to_non_nullable
                      as int?,
            coverArtId: freezed == coverArtId
                ? _value.coverArtId
                : coverArtId // ignore: cast_nullable_to_non_nullable
                      as String?,
            track: freezed == track
                ? _value.track
                : track // ignore: cast_nullable_to_non_nullable
                      as int?,
            discNumber: freezed == discNumber
                ? _value.discNumber
                : discNumber // ignore: cast_nullable_to_non_nullable
                      as int?,
            year: freezed == year
                ? _value.year
                : year // ignore: cast_nullable_to_non_nullable
                      as int?,
            genre: freezed == genre
                ? _value.genre
                : genre // ignore: cast_nullable_to_non_nullable
                      as String?,
            albumArtist: freezed == albumArtist
                ? _value.albumArtist
                : albumArtist // ignore: cast_nullable_to_non_nullable
                      as String?,
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
abstract class _$$SongDtoImplCopyWith<$Res> implements $SongDtoCopyWith<$Res> {
  factory _$$SongDtoImplCopyWith(
    _$SongDtoImpl value,
    $Res Function(_$SongDtoImpl) then,
  ) = __$$SongDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String title,
    @JsonKey(name: 'albumId') String? albumId,
    @JsonKey(name: 'artistId') String? artistId,
    String? album,
    String? artist,
    int? duration,
    int? bitRate,
    String? contentType,
    String? suffix,
    int? size,
    @JsonKey(name: 'coverArt') String? coverArtId,
    int? track,
    @JsonKey(name: 'discNumber') int? discNumber,
    int? year,
    String? genre,
    @JsonKey(name: 'albumArtist') String? albumArtist,
    @JsonKey(name: 'userRating') int? userRating,
  });
}

/// @nodoc
class __$$SongDtoImplCopyWithImpl<$Res>
    extends _$SongDtoCopyWithImpl<$Res, _$SongDtoImpl>
    implements _$$SongDtoImplCopyWith<$Res> {
  __$$SongDtoImplCopyWithImpl(
    _$SongDtoImpl _value,
    $Res Function(_$SongDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SongDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? albumId = freezed,
    Object? artistId = freezed,
    Object? album = freezed,
    Object? artist = freezed,
    Object? duration = freezed,
    Object? bitRate = freezed,
    Object? contentType = freezed,
    Object? suffix = freezed,
    Object? size = freezed,
    Object? coverArtId = freezed,
    Object? track = freezed,
    Object? discNumber = freezed,
    Object? year = freezed,
    Object? genre = freezed,
    Object? albumArtist = freezed,
    Object? userRating = freezed,
  }) {
    return _then(
      _$SongDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        title: null == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String,
        albumId: freezed == albumId
            ? _value.albumId
            : albumId // ignore: cast_nullable_to_non_nullable
                  as String?,
        artistId: freezed == artistId
            ? _value.artistId
            : artistId // ignore: cast_nullable_to_non_nullable
                  as String?,
        album: freezed == album
            ? _value.album
            : album // ignore: cast_nullable_to_non_nullable
                  as String?,
        artist: freezed == artist
            ? _value.artist
            : artist // ignore: cast_nullable_to_non_nullable
                  as String?,
        duration: freezed == duration
            ? _value.duration
            : duration // ignore: cast_nullable_to_non_nullable
                  as int?,
        bitRate: freezed == bitRate
            ? _value.bitRate
            : bitRate // ignore: cast_nullable_to_non_nullable
                  as int?,
        contentType: freezed == contentType
            ? _value.contentType
            : contentType // ignore: cast_nullable_to_non_nullable
                  as String?,
        suffix: freezed == suffix
            ? _value.suffix
            : suffix // ignore: cast_nullable_to_non_nullable
                  as String?,
        size: freezed == size
            ? _value.size
            : size // ignore: cast_nullable_to_non_nullable
                  as int?,
        coverArtId: freezed == coverArtId
            ? _value.coverArtId
            : coverArtId // ignore: cast_nullable_to_non_nullable
                  as String?,
        track: freezed == track
            ? _value.track
            : track // ignore: cast_nullable_to_non_nullable
                  as int?,
        discNumber: freezed == discNumber
            ? _value.discNumber
            : discNumber // ignore: cast_nullable_to_non_nullable
                  as int?,
        year: freezed == year
            ? _value.year
            : year // ignore: cast_nullable_to_non_nullable
                  as int?,
        genre: freezed == genre
            ? _value.genre
            : genre // ignore: cast_nullable_to_non_nullable
                  as String?,
        albumArtist: freezed == albumArtist
            ? _value.albumArtist
            : albumArtist // ignore: cast_nullable_to_non_nullable
                  as String?,
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
class _$SongDtoImpl implements _SongDto {
  const _$SongDtoImpl({
    required this.id,
    required this.title,
    @JsonKey(name: 'albumId') this.albumId,
    @JsonKey(name: 'artistId') this.artistId,
    this.album,
    this.artist,
    this.duration,
    this.bitRate,
    this.contentType,
    this.suffix,
    this.size,
    @JsonKey(name: 'coverArt') this.coverArtId,
    this.track,
    @JsonKey(name: 'discNumber') this.discNumber,
    this.year,
    this.genre,
    @JsonKey(name: 'albumArtist') this.albumArtist,
    @JsonKey(name: 'userRating') this.userRating,
  });

  factory _$SongDtoImpl.fromJson(Map<String, dynamic> json) =>
      _$$SongDtoImplFromJson(json);

  @override
  final String id;
  @override
  final String title;
  @override
  @JsonKey(name: 'albumId')
  final String? albumId;
  @override
  @JsonKey(name: 'artistId')
  final String? artistId;
  @override
  final String? album;
  @override
  final String? artist;
  @override
  final int? duration;
  @override
  final int? bitRate;
  @override
  final String? contentType;
  @override
  final String? suffix;
  @override
  final int? size;
  @override
  @JsonKey(name: 'coverArt')
  final String? coverArtId;
  @override
  final int? track;
  @override
  @JsonKey(name: 'discNumber')
  final int? discNumber;
  @override
  final int? year;
  @override
  final String? genre;
  @override
  @JsonKey(name: 'albumArtist')
  final String? albumArtist;
  // Subsonic `userRating` (1-5) — present only when the user has rated.
  @override
  @JsonKey(name: 'userRating')
  final int? userRating;

  @override
  String toString() {
    return 'SongDto(id: $id, title: $title, albumId: $albumId, artistId: $artistId, album: $album, artist: $artist, duration: $duration, bitRate: $bitRate, contentType: $contentType, suffix: $suffix, size: $size, coverArtId: $coverArtId, track: $track, discNumber: $discNumber, year: $year, genre: $genre, albumArtist: $albumArtist, userRating: $userRating)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SongDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.albumId, albumId) || other.albumId == albumId) &&
            (identical(other.artistId, artistId) ||
                other.artistId == artistId) &&
            (identical(other.album, album) || other.album == album) &&
            (identical(other.artist, artist) || other.artist == artist) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            (identical(other.bitRate, bitRate) || other.bitRate == bitRate) &&
            (identical(other.contentType, contentType) ||
                other.contentType == contentType) &&
            (identical(other.suffix, suffix) || other.suffix == suffix) &&
            (identical(other.size, size) || other.size == size) &&
            (identical(other.coverArtId, coverArtId) ||
                other.coverArtId == coverArtId) &&
            (identical(other.track, track) || other.track == track) &&
            (identical(other.discNumber, discNumber) ||
                other.discNumber == discNumber) &&
            (identical(other.year, year) || other.year == year) &&
            (identical(other.genre, genre) || other.genre == genre) &&
            (identical(other.albumArtist, albumArtist) ||
                other.albumArtist == albumArtist) &&
            (identical(other.userRating, userRating) ||
                other.userRating == userRating));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    title,
    albumId,
    artistId,
    album,
    artist,
    duration,
    bitRate,
    contentType,
    suffix,
    size,
    coverArtId,
    track,
    discNumber,
    year,
    genre,
    albumArtist,
    userRating,
  );

  /// Create a copy of SongDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SongDtoImplCopyWith<_$SongDtoImpl> get copyWith =>
      __$$SongDtoImplCopyWithImpl<_$SongDtoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SongDtoImplToJson(this);
  }
}

abstract class _SongDto implements SongDto {
  const factory _SongDto({
    required final String id,
    required final String title,
    @JsonKey(name: 'albumId') final String? albumId,
    @JsonKey(name: 'artistId') final String? artistId,
    final String? album,
    final String? artist,
    final int? duration,
    final int? bitRate,
    final String? contentType,
    final String? suffix,
    final int? size,
    @JsonKey(name: 'coverArt') final String? coverArtId,
    final int? track,
    @JsonKey(name: 'discNumber') final int? discNumber,
    final int? year,
    final String? genre,
    @JsonKey(name: 'albumArtist') final String? albumArtist,
    @JsonKey(name: 'userRating') final int? userRating,
  }) = _$SongDtoImpl;

  factory _SongDto.fromJson(Map<String, dynamic> json) = _$SongDtoImpl.fromJson;

  @override
  String get id;
  @override
  String get title;
  @override
  @JsonKey(name: 'albumId')
  String? get albumId;
  @override
  @JsonKey(name: 'artistId')
  String? get artistId;
  @override
  String? get album;
  @override
  String? get artist;
  @override
  int? get duration;
  @override
  int? get bitRate;
  @override
  String? get contentType;
  @override
  String? get suffix;
  @override
  int? get size;
  @override
  @JsonKey(name: 'coverArt')
  String? get coverArtId;
  @override
  int? get track;
  @override
  @JsonKey(name: 'discNumber')
  int? get discNumber;
  @override
  int? get year;
  @override
  String? get genre;
  @override
  @JsonKey(name: 'albumArtist')
  String? get albumArtist; // Subsonic `userRating` (1-5) — present only when the user has rated.
  @override
  @JsonKey(name: 'userRating')
  int? get userRating;

  /// Create a copy of SongDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SongDtoImplCopyWith<_$SongDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
