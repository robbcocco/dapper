// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'song.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Song {

 String get id; String get title; String? get albumId; String? get artistId; String? get album; String? get artist; int? get duration; int? get bitRate; String? get contentType; String? get suffix; int? get size; String? get coverArtId; int? get track; int? get discNumber; int? get year; String? get genre; String? get albumArtist; int? get userRating;
/// Create a copy of Song
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SongCopyWith<Song> get copyWith => _$SongCopyWithImpl<Song>(this as Song, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Song&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.albumId, albumId) || other.albumId == albumId)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.album, album) || other.album == album)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.bitRate, bitRate) || other.bitRate == bitRate)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.suffix, suffix) || other.suffix == suffix)&&(identical(other.size, size) || other.size == size)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.track, track) || other.track == track)&&(identical(other.discNumber, discNumber) || other.discNumber == discNumber)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.albumArtist, albumArtist) || other.albumArtist == albumArtist)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,albumId,artistId,album,artist,duration,bitRate,contentType,suffix,size,coverArtId,track,discNumber,year,genre,albumArtist,userRating);

@override
String toString() {
  return 'Song(id: $id, title: $title, albumId: $albumId, artistId: $artistId, album: $album, artist: $artist, duration: $duration, bitRate: $bitRate, contentType: $contentType, suffix: $suffix, size: $size, coverArtId: $coverArtId, track: $track, discNumber: $discNumber, year: $year, genre: $genre, albumArtist: $albumArtist, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class $SongCopyWith<$Res>  {
  factory $SongCopyWith(Song value, $Res Function(Song) _then) = _$SongCopyWithImpl;
@useResult
$Res call({
 String id, String title, String? albumId, String? artistId, String? album, String? artist, int? duration, int? bitRate, String? contentType, String? suffix, int? size, String? coverArtId, int? track, int? discNumber, int? year, String? genre, String? albumArtist, int? userRating
});




}
/// @nodoc
class _$SongCopyWithImpl<$Res>
    implements $SongCopyWith<$Res> {
  _$SongCopyWithImpl(this._self, this._then);

  final Song _self;
  final $Res Function(Song) _then;

/// Create a copy of Song
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? albumId = freezed,Object? artistId = freezed,Object? album = freezed,Object? artist = freezed,Object? duration = freezed,Object? bitRate = freezed,Object? contentType = freezed,Object? suffix = freezed,Object? size = freezed,Object? coverArtId = freezed,Object? track = freezed,Object? discNumber = freezed,Object? year = freezed,Object? genre = freezed,Object? albumArtist = freezed,Object? userRating = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,albumId: freezed == albumId ? _self.albumId : albumId // ignore: cast_nullable_to_non_nullable
as String?,artistId: freezed == artistId ? _self.artistId : artistId // ignore: cast_nullable_to_non_nullable
as String?,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,artist: freezed == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int?,bitRate: freezed == bitRate ? _self.bitRate : bitRate // ignore: cast_nullable_to_non_nullable
as int?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,suffix: freezed == suffix ? _self.suffix : suffix // ignore: cast_nullable_to_non_nullable
as String?,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int?,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,track: freezed == track ? _self.track : track // ignore: cast_nullable_to_non_nullable
as int?,discNumber: freezed == discNumber ? _self.discNumber : discNumber // ignore: cast_nullable_to_non_nullable
as int?,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,genre: freezed == genre ? _self.genre : genre // ignore: cast_nullable_to_non_nullable
as String?,albumArtist: freezed == albumArtist ? _self.albumArtist : albumArtist // ignore: cast_nullable_to_non_nullable
as String?,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [Song].
extension SongPatterns on Song {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Song value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Song() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Song value)  $default,){
final _that = this;
switch (_that) {
case _Song():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Song value)?  $default,){
final _that = this;
switch (_that) {
case _Song() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String? albumId,  String? artistId,  String? album,  String? artist,  int? duration,  int? bitRate,  String? contentType,  String? suffix,  int? size,  String? coverArtId,  int? track,  int? discNumber,  int? year,  String? genre,  String? albumArtist,  int? userRating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Song() when $default != null:
return $default(_that.id,_that.title,_that.albumId,_that.artistId,_that.album,_that.artist,_that.duration,_that.bitRate,_that.contentType,_that.suffix,_that.size,_that.coverArtId,_that.track,_that.discNumber,_that.year,_that.genre,_that.albumArtist,_that.userRating);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String? albumId,  String? artistId,  String? album,  String? artist,  int? duration,  int? bitRate,  String? contentType,  String? suffix,  int? size,  String? coverArtId,  int? track,  int? discNumber,  int? year,  String? genre,  String? albumArtist,  int? userRating)  $default,) {final _that = this;
switch (_that) {
case _Song():
return $default(_that.id,_that.title,_that.albumId,_that.artistId,_that.album,_that.artist,_that.duration,_that.bitRate,_that.contentType,_that.suffix,_that.size,_that.coverArtId,_that.track,_that.discNumber,_that.year,_that.genre,_that.albumArtist,_that.userRating);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String? albumId,  String? artistId,  String? album,  String? artist,  int? duration,  int? bitRate,  String? contentType,  String? suffix,  int? size,  String? coverArtId,  int? track,  int? discNumber,  int? year,  String? genre,  String? albumArtist,  int? userRating)?  $default,) {final _that = this;
switch (_that) {
case _Song() when $default != null:
return $default(_that.id,_that.title,_that.albumId,_that.artistId,_that.album,_that.artist,_that.duration,_that.bitRate,_that.contentType,_that.suffix,_that.size,_that.coverArtId,_that.track,_that.discNumber,_that.year,_that.genre,_that.albumArtist,_that.userRating);case _:
  return null;

}
}

}

/// @nodoc


class _Song implements Song {
  const _Song({required this.id, required this.title, this.albumId, this.artistId, this.album, this.artist, this.duration, this.bitRate, this.contentType, this.suffix, this.size, this.coverArtId, this.track, this.discNumber, this.year, this.genre, this.albumArtist, this.userRating});
  

@override final  String id;
@override final  String title;
@override final  String? albumId;
@override final  String? artistId;
@override final  String? album;
@override final  String? artist;
@override final  int? duration;
@override final  int? bitRate;
@override final  String? contentType;
@override final  String? suffix;
@override final  int? size;
@override final  String? coverArtId;
@override final  int? track;
@override final  int? discNumber;
@override final  int? year;
@override final  String? genre;
@override final  String? albumArtist;
@override final  int? userRating;

/// Create a copy of Song
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SongCopyWith<_Song> get copyWith => __$SongCopyWithImpl<_Song>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Song&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.albumId, albumId) || other.albumId == albumId)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.album, album) || other.album == album)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.bitRate, bitRate) || other.bitRate == bitRate)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.suffix, suffix) || other.suffix == suffix)&&(identical(other.size, size) || other.size == size)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.track, track) || other.track == track)&&(identical(other.discNumber, discNumber) || other.discNumber == discNumber)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.albumArtist, albumArtist) || other.albumArtist == albumArtist)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,albumId,artistId,album,artist,duration,bitRate,contentType,suffix,size,coverArtId,track,discNumber,year,genre,albumArtist,userRating);

@override
String toString() {
  return 'Song(id: $id, title: $title, albumId: $albumId, artistId: $artistId, album: $album, artist: $artist, duration: $duration, bitRate: $bitRate, contentType: $contentType, suffix: $suffix, size: $size, coverArtId: $coverArtId, track: $track, discNumber: $discNumber, year: $year, genre: $genre, albumArtist: $albumArtist, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class _$SongCopyWith<$Res> implements $SongCopyWith<$Res> {
  factory _$SongCopyWith(_Song value, $Res Function(_Song) _then) = __$SongCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String? albumId, String? artistId, String? album, String? artist, int? duration, int? bitRate, String? contentType, String? suffix, int? size, String? coverArtId, int? track, int? discNumber, int? year, String? genre, String? albumArtist, int? userRating
});




}
/// @nodoc
class __$SongCopyWithImpl<$Res>
    implements _$SongCopyWith<$Res> {
  __$SongCopyWithImpl(this._self, this._then);

  final _Song _self;
  final $Res Function(_Song) _then;

/// Create a copy of Song
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? albumId = freezed,Object? artistId = freezed,Object? album = freezed,Object? artist = freezed,Object? duration = freezed,Object? bitRate = freezed,Object? contentType = freezed,Object? suffix = freezed,Object? size = freezed,Object? coverArtId = freezed,Object? track = freezed,Object? discNumber = freezed,Object? year = freezed,Object? genre = freezed,Object? albumArtist = freezed,Object? userRating = freezed,}) {
  return _then(_Song(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,albumId: freezed == albumId ? _self.albumId : albumId // ignore: cast_nullable_to_non_nullable
as String?,artistId: freezed == artistId ? _self.artistId : artistId // ignore: cast_nullable_to_non_nullable
as String?,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,artist: freezed == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int?,bitRate: freezed == bitRate ? _self.bitRate : bitRate // ignore: cast_nullable_to_non_nullable
as int?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,suffix: freezed == suffix ? _self.suffix : suffix // ignore: cast_nullable_to_non_nullable
as String?,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int?,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,track: freezed == track ? _self.track : track // ignore: cast_nullable_to_non_nullable
as int?,discNumber: freezed == discNumber ? _self.discNumber : discNumber // ignore: cast_nullable_to_non_nullable
as int?,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,genre: freezed == genre ? _self.genre : genre // ignore: cast_nullable_to_non_nullable
as String?,albumArtist: freezed == albumArtist ? _self.albumArtist : albumArtist // ignore: cast_nullable_to_non_nullable
as String?,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
