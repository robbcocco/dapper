// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'album.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Album {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get artistId => throw _privateConstructorUsedError;
  String? get artist => throw _privateConstructorUsedError;
  String? get coverArtId => throw _privateConstructorUsedError;
  int? get year => throw _privateConstructorUsedError;
  String? get genre => throw _privateConstructorUsedError;
  int get songCount => throw _privateConstructorUsedError;
  int get duration => throw _privateConstructorUsedError;
  List<Song> get songs => throw _privateConstructorUsedError;
  int? get userRating => throw _privateConstructorUsedError;

  /// Create a copy of Album
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AlbumCopyWith<Album> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AlbumCopyWith<$Res> {
  factory $AlbumCopyWith(Album value, $Res Function(Album) then) =
      _$AlbumCopyWithImpl<$Res, Album>;
  @useResult
  $Res call({
    String id,
    String name,
    String? artistId,
    String? artist,
    String? coverArtId,
    int? year,
    String? genre,
    int songCount,
    int duration,
    List<Song> songs,
    int? userRating,
  });
}

/// @nodoc
class _$AlbumCopyWithImpl<$Res, $Val extends Album>
    implements $AlbumCopyWith<$Res> {
  _$AlbumCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Album
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
                      as List<Song>,
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
abstract class _$$AlbumImplCopyWith<$Res> implements $AlbumCopyWith<$Res> {
  factory _$$AlbumImplCopyWith(
    _$AlbumImpl value,
    $Res Function(_$AlbumImpl) then,
  ) = __$$AlbumImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? artistId,
    String? artist,
    String? coverArtId,
    int? year,
    String? genre,
    int songCount,
    int duration,
    List<Song> songs,
    int? userRating,
  });
}

/// @nodoc
class __$$AlbumImplCopyWithImpl<$Res>
    extends _$AlbumCopyWithImpl<$Res, _$AlbumImpl>
    implements _$$AlbumImplCopyWith<$Res> {
  __$$AlbumImplCopyWithImpl(
    _$AlbumImpl _value,
    $Res Function(_$AlbumImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Album
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
      _$AlbumImpl(
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
                  as List<Song>,
        userRating: freezed == userRating
            ? _value.userRating
            : userRating // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc

class _$AlbumImpl implements _Album {
  const _$AlbumImpl({
    required this.id,
    required this.name,
    this.artistId,
    this.artist,
    this.coverArtId,
    this.year,
    this.genre,
    this.songCount = 0,
    this.duration = 0,
    final List<Song> songs = const [],
    this.userRating,
  }) : _songs = songs;

  @override
  final String id;
  @override
  final String name;
  @override
  final String? artistId;
  @override
  final String? artist;
  @override
  final String? coverArtId;
  @override
  final int? year;
  @override
  final String? genre;
  @override
  @JsonKey()
  final int songCount;
  @override
  @JsonKey()
  final int duration;
  final List<Song> _songs;
  @override
  @JsonKey()
  List<Song> get songs {
    if (_songs is EqualUnmodifiableListView) return _songs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_songs);
  }

  @override
  final int? userRating;

  @override
  String toString() {
    return 'Album(id: $id, name: $name, artistId: $artistId, artist: $artist, coverArtId: $coverArtId, year: $year, genre: $genre, songCount: $songCount, duration: $duration, songs: $songs, userRating: $userRating)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AlbumImpl &&
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

  /// Create a copy of Album
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AlbumImplCopyWith<_$AlbumImpl> get copyWith =>
      __$$AlbumImplCopyWithImpl<_$AlbumImpl>(this, _$identity);
}

abstract class _Album implements Album {
  const factory _Album({
    required final String id,
    required final String name,
    final String? artistId,
    final String? artist,
    final String? coverArtId,
    final int? year,
    final String? genre,
    final int songCount,
    final int duration,
    final List<Song> songs,
    final int? userRating,
  }) = _$AlbumImpl;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get artistId;
  @override
  String? get artist;
  @override
  String? get coverArtId;
  @override
  int? get year;
  @override
  String? get genre;
  @override
  int get songCount;
  @override
  int get duration;
  @override
  List<Song> get songs;
  @override
  int? get userRating;

  /// Create a copy of Album
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AlbumImplCopyWith<_$AlbumImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
