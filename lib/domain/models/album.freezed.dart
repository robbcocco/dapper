// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'album.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Album {

 String get id; String get name; String? get artistId; String? get artist; String? get coverArtId; int? get year; String? get genre; int get songCount; int get duration; List<Song> get songs; int? get userRating;
/// Create a copy of Album
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlbumCopyWith<Album> get copyWith => _$AlbumCopyWithImpl<Album>(this as Album, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Album&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other.songs, songs)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,artistId,artist,coverArtId,year,genre,songCount,duration,const DeepCollectionEquality().hash(songs),userRating);

@override
String toString() {
  return 'Album(id: $id, name: $name, artistId: $artistId, artist: $artist, coverArtId: $coverArtId, year: $year, genre: $genre, songCount: $songCount, duration: $duration, songs: $songs, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class $AlbumCopyWith<$Res>  {
  factory $AlbumCopyWith(Album value, $Res Function(Album) _then) = _$AlbumCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? artistId, String? artist, String? coverArtId, int? year, String? genre, int songCount, int duration, List<Song> songs, int? userRating
});




}
/// @nodoc
class _$AlbumCopyWithImpl<$Res>
    implements $AlbumCopyWith<$Res> {
  _$AlbumCopyWithImpl(this._self, this._then);

  final Album _self;
  final $Res Function(Album) _then;

/// Create a copy of Album
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? artistId = freezed,Object? artist = freezed,Object? coverArtId = freezed,Object? year = freezed,Object? genre = freezed,Object? songCount = null,Object? duration = null,Object? songs = null,Object? userRating = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,artistId: freezed == artistId ? _self.artistId : artistId // ignore: cast_nullable_to_non_nullable
as String?,artist: freezed == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String?,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,genre: freezed == genre ? _self.genre : genre // ignore: cast_nullable_to_non_nullable
as String?,songCount: null == songCount ? _self.songCount : songCount // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int,songs: null == songs ? _self.songs : songs // ignore: cast_nullable_to_non_nullable
as List<Song>,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [Album].
extension AlbumPatterns on Album {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Album value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Album() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Album value)  $default,){
final _that = this;
switch (_that) {
case _Album():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Album value)?  $default,){
final _that = this;
switch (_that) {
case _Album() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? artistId,  String? artist,  String? coverArtId,  int? year,  String? genre,  int songCount,  int duration,  List<Song> songs,  int? userRating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Album() when $default != null:
return $default(_that.id,_that.name,_that.artistId,_that.artist,_that.coverArtId,_that.year,_that.genre,_that.songCount,_that.duration,_that.songs,_that.userRating);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? artistId,  String? artist,  String? coverArtId,  int? year,  String? genre,  int songCount,  int duration,  List<Song> songs,  int? userRating)  $default,) {final _that = this;
switch (_that) {
case _Album():
return $default(_that.id,_that.name,_that.artistId,_that.artist,_that.coverArtId,_that.year,_that.genre,_that.songCount,_that.duration,_that.songs,_that.userRating);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? artistId,  String? artist,  String? coverArtId,  int? year,  String? genre,  int songCount,  int duration,  List<Song> songs,  int? userRating)?  $default,) {final _that = this;
switch (_that) {
case _Album() when $default != null:
return $default(_that.id,_that.name,_that.artistId,_that.artist,_that.coverArtId,_that.year,_that.genre,_that.songCount,_that.duration,_that.songs,_that.userRating);case _:
  return null;

}
}

}

/// @nodoc


class _Album implements Album {
  const _Album({required this.id, required this.name, this.artistId, this.artist, this.coverArtId, this.year, this.genre, this.songCount = 0, this.duration = 0, final  List<Song> songs = const [], this.userRating}): _songs = songs;
  

@override final  String id;
@override final  String name;
@override final  String? artistId;
@override final  String? artist;
@override final  String? coverArtId;
@override final  int? year;
@override final  String? genre;
@override@JsonKey() final  int songCount;
@override@JsonKey() final  int duration;
 final  List<Song> _songs;
@override@JsonKey() List<Song> get songs {
  if (_songs is EqualUnmodifiableListView) return _songs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_songs);
}

@override final  int? userRating;

/// Create a copy of Album
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlbumCopyWith<_Album> get copyWith => __$AlbumCopyWithImpl<_Album>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Album&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other._songs, _songs)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,artistId,artist,coverArtId,year,genre,songCount,duration,const DeepCollectionEquality().hash(_songs),userRating);

@override
String toString() {
  return 'Album(id: $id, name: $name, artistId: $artistId, artist: $artist, coverArtId: $coverArtId, year: $year, genre: $genre, songCount: $songCount, duration: $duration, songs: $songs, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class _$AlbumCopyWith<$Res> implements $AlbumCopyWith<$Res> {
  factory _$AlbumCopyWith(_Album value, $Res Function(_Album) _then) = __$AlbumCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? artistId, String? artist, String? coverArtId, int? year, String? genre, int songCount, int duration, List<Song> songs, int? userRating
});




}
/// @nodoc
class __$AlbumCopyWithImpl<$Res>
    implements _$AlbumCopyWith<$Res> {
  __$AlbumCopyWithImpl(this._self, this._then);

  final _Album _self;
  final $Res Function(_Album) _then;

/// Create a copy of Album
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? artistId = freezed,Object? artist = freezed,Object? coverArtId = freezed,Object? year = freezed,Object? genre = freezed,Object? songCount = null,Object? duration = null,Object? songs = null,Object? userRating = freezed,}) {
  return _then(_Album(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,artistId: freezed == artistId ? _self.artistId : artistId // ignore: cast_nullable_to_non_nullable
as String?,artist: freezed == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String?,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,genre: freezed == genre ? _self.genre : genre // ignore: cast_nullable_to_non_nullable
as String?,songCount: null == songCount ? _self.songCount : songCount // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int,songs: null == songs ? _self._songs : songs // ignore: cast_nullable_to_non_nullable
as List<Song>,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
