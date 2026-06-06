// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'song.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Song {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String? get albumId => throw _privateConstructorUsedError;
  String? get artistId => throw _privateConstructorUsedError;
  String? get album => throw _privateConstructorUsedError;
  String? get artist => throw _privateConstructorUsedError;
  int? get duration => throw _privateConstructorUsedError;
  int? get bitRate => throw _privateConstructorUsedError;
  String? get contentType => throw _privateConstructorUsedError;
  String? get suffix => throw _privateConstructorUsedError;
  int? get size => throw _privateConstructorUsedError;
  String? get coverArtId => throw _privateConstructorUsedError;
  int? get track => throw _privateConstructorUsedError;
  int? get discNumber => throw _privateConstructorUsedError;
  int? get year => throw _privateConstructorUsedError;
  String? get genre => throw _privateConstructorUsedError;
  String? get albumArtist => throw _privateConstructorUsedError;
  int? get userRating => throw _privateConstructorUsedError;

  /// Create a copy of Song
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SongCopyWith<Song> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SongCopyWith<$Res> {
  factory $SongCopyWith(Song value, $Res Function(Song) then) =
      _$SongCopyWithImpl<$Res, Song>;
  @useResult
  $Res call({
    String id,
    String title,
    String? albumId,
    String? artistId,
    String? album,
    String? artist,
    int? duration,
    int? bitRate,
    String? contentType,
    String? suffix,
    int? size,
    String? coverArtId,
    int? track,
    int? discNumber,
    int? year,
    String? genre,
    String? albumArtist,
    int? userRating,
  });
}

/// @nodoc
class _$SongCopyWithImpl<$Res, $Val extends Song>
    implements $SongCopyWith<$Res> {
  _$SongCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Song
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
abstract class _$$SongImplCopyWith<$Res> implements $SongCopyWith<$Res> {
  factory _$$SongImplCopyWith(
    _$SongImpl value,
    $Res Function(_$SongImpl) then,
  ) = __$$SongImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String title,
    String? albumId,
    String? artistId,
    String? album,
    String? artist,
    int? duration,
    int? bitRate,
    String? contentType,
    String? suffix,
    int? size,
    String? coverArtId,
    int? track,
    int? discNumber,
    int? year,
    String? genre,
    String? albumArtist,
    int? userRating,
  });
}

/// @nodoc
class __$$SongImplCopyWithImpl<$Res>
    extends _$SongCopyWithImpl<$Res, _$SongImpl>
    implements _$$SongImplCopyWith<$Res> {
  __$$SongImplCopyWithImpl(_$SongImpl _value, $Res Function(_$SongImpl) _then)
    : super(_value, _then);

  /// Create a copy of Song
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
      _$SongImpl(
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

class _$SongImpl implements _Song {
  const _$SongImpl({
    required this.id,
    required this.title,
    this.albumId,
    this.artistId,
    this.album,
    this.artist,
    this.duration,
    this.bitRate,
    this.contentType,
    this.suffix,
    this.size,
    this.coverArtId,
    this.track,
    this.discNumber,
    this.year,
    this.genre,
    this.albumArtist,
    this.userRating,
  });

  @override
  final String id;
  @override
  final String title;
  @override
  final String? albumId;
  @override
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
  final String? coverArtId;
  @override
  final int? track;
  @override
  final int? discNumber;
  @override
  final int? year;
  @override
  final String? genre;
  @override
  final String? albumArtist;
  @override
  final int? userRating;

  @override
  String toString() {
    return 'Song(id: $id, title: $title, albumId: $albumId, artistId: $artistId, album: $album, artist: $artist, duration: $duration, bitRate: $bitRate, contentType: $contentType, suffix: $suffix, size: $size, coverArtId: $coverArtId, track: $track, discNumber: $discNumber, year: $year, genre: $genre, albumArtist: $albumArtist, userRating: $userRating)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SongImpl &&
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

  /// Create a copy of Song
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SongImplCopyWith<_$SongImpl> get copyWith =>
      __$$SongImplCopyWithImpl<_$SongImpl>(this, _$identity);
}

abstract class _Song implements Song {
  const factory _Song({
    required final String id,
    required final String title,
    final String? albumId,
    final String? artistId,
    final String? album,
    final String? artist,
    final int? duration,
    final int? bitRate,
    final String? contentType,
    final String? suffix,
    final int? size,
    final String? coverArtId,
    final int? track,
    final int? discNumber,
    final int? year,
    final String? genre,
    final String? albumArtist,
    final int? userRating,
  }) = _$SongImpl;

  @override
  String get id;
  @override
  String get title;
  @override
  String? get albumId;
  @override
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
  String? get coverArtId;
  @override
  int? get track;
  @override
  int? get discNumber;
  @override
  int? get year;
  @override
  String? get genre;
  @override
  String? get albumArtist;
  @override
  int? get userRating;

  /// Create a copy of Song
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SongImplCopyWith<_$SongImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
