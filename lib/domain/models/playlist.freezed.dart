// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playlist.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$Playlist {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get comment => throw _privateConstructorUsedError;
  String? get coverArtId => throw _privateConstructorUsedError;
  int get songCount => throw _privateConstructorUsedError;
  int get duration => throw _privateConstructorUsedError;
  List<Song> get songs => throw _privateConstructorUsedError;

  /// Create a copy of Playlist
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PlaylistCopyWith<Playlist> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PlaylistCopyWith<$Res> {
  factory $PlaylistCopyWith(Playlist value, $Res Function(Playlist) then) =
      _$PlaylistCopyWithImpl<$Res, Playlist>;
  @useResult
  $Res call({
    String id,
    String name,
    String? comment,
    String? coverArtId,
    int songCount,
    int duration,
    List<Song> songs,
  });
}

/// @nodoc
class _$PlaylistCopyWithImpl<$Res, $Val extends Playlist>
    implements $PlaylistCopyWith<$Res> {
  _$PlaylistCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Playlist
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
                      as List<Song>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PlaylistImplCopyWith<$Res>
    implements $PlaylistCopyWith<$Res> {
  factory _$$PlaylistImplCopyWith(
    _$PlaylistImpl value,
    $Res Function(_$PlaylistImpl) then,
  ) = __$$PlaylistImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? comment,
    String? coverArtId,
    int songCount,
    int duration,
    List<Song> songs,
  });
}

/// @nodoc
class __$$PlaylistImplCopyWithImpl<$Res>
    extends _$PlaylistCopyWithImpl<$Res, _$PlaylistImpl>
    implements _$$PlaylistImplCopyWith<$Res> {
  __$$PlaylistImplCopyWithImpl(
    _$PlaylistImpl _value,
    $Res Function(_$PlaylistImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Playlist
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
      _$PlaylistImpl(
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
                  as List<Song>,
      ),
    );
  }
}

/// @nodoc

class _$PlaylistImpl implements _Playlist {
  const _$PlaylistImpl({
    required this.id,
    required this.name,
    this.comment,
    this.coverArtId,
    this.songCount = 0,
    this.duration = 0,
    final List<Song> songs = const [],
  }) : _songs = songs;

  @override
  final String id;
  @override
  final String name;
  @override
  final String? comment;
  @override
  final String? coverArtId;
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
  String toString() {
    return 'Playlist(id: $id, name: $name, comment: $comment, coverArtId: $coverArtId, songCount: $songCount, duration: $duration, songs: $songs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PlaylistImpl &&
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

  /// Create a copy of Playlist
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PlaylistImplCopyWith<_$PlaylistImpl> get copyWith =>
      __$$PlaylistImplCopyWithImpl<_$PlaylistImpl>(this, _$identity);
}

abstract class _Playlist implements Playlist {
  const factory _Playlist({
    required final String id,
    required final String name,
    final String? comment,
    final String? coverArtId,
    final int songCount,
    final int duration,
    final List<Song> songs,
  }) = _$PlaylistImpl;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get comment;
  @override
  String? get coverArtId;
  @override
  int get songCount;
  @override
  int get duration;
  @override
  List<Song> get songs;

  /// Create a copy of Playlist
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PlaylistImplCopyWith<_$PlaylistImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
