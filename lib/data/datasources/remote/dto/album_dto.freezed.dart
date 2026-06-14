// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'album_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlbumDto {

 String get id; String get name;@JsonKey(name: 'artistId') String? get artistId; String? get artist;@JsonKey(name: 'coverArt') String? get coverArtId; int? get year; String? get genre;@JsonKey(name: 'songCount') int get songCount; int get duration;@JsonKey(name: 'song') List<SongDto> get songs;@JsonKey(name: 'userRating') int? get userRating;
/// Create a copy of AlbumDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlbumDtoCopyWith<AlbumDto> get copyWith => _$AlbumDtoCopyWithImpl<AlbumDto>(this as AlbumDto, _$identity);

  /// Serializes this AlbumDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlbumDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other.songs, songs)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,artistId,artist,coverArtId,year,genre,songCount,duration,const DeepCollectionEquality().hash(songs),userRating);

@override
String toString() {
  return 'AlbumDto(id: $id, name: $name, artistId: $artistId, artist: $artist, coverArtId: $coverArtId, year: $year, genre: $genre, songCount: $songCount, duration: $duration, songs: $songs, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class $AlbumDtoCopyWith<$Res>  {
  factory $AlbumDtoCopyWith(AlbumDto value, $Res Function(AlbumDto) _then) = _$AlbumDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name,@JsonKey(name: 'artistId') String? artistId, String? artist,@JsonKey(name: 'coverArt') String? coverArtId, int? year, String? genre,@JsonKey(name: 'songCount') int songCount, int duration,@JsonKey(name: 'song') List<SongDto> songs,@JsonKey(name: 'userRating') int? userRating
});




}
/// @nodoc
class _$AlbumDtoCopyWithImpl<$Res>
    implements $AlbumDtoCopyWith<$Res> {
  _$AlbumDtoCopyWithImpl(this._self, this._then);

  final AlbumDto _self;
  final $Res Function(AlbumDto) _then;

/// Create a copy of AlbumDto
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
as List<SongDto>,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AlbumDto].
extension AlbumDtoPatterns on AlbumDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlbumDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlbumDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlbumDto value)  $default,){
final _that = this;
switch (_that) {
case _AlbumDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlbumDto value)?  $default,){
final _that = this;
switch (_that) {
case _AlbumDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name, @JsonKey(name: 'artistId')  String? artistId,  String? artist, @JsonKey(name: 'coverArt')  String? coverArtId,  int? year,  String? genre, @JsonKey(name: 'songCount')  int songCount,  int duration, @JsonKey(name: 'song')  List<SongDto> songs, @JsonKey(name: 'userRating')  int? userRating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlbumDto() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name, @JsonKey(name: 'artistId')  String? artistId,  String? artist, @JsonKey(name: 'coverArt')  String? coverArtId,  int? year,  String? genre, @JsonKey(name: 'songCount')  int songCount,  int duration, @JsonKey(name: 'song')  List<SongDto> songs, @JsonKey(name: 'userRating')  int? userRating)  $default,) {final _that = this;
switch (_that) {
case _AlbumDto():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name, @JsonKey(name: 'artistId')  String? artistId,  String? artist, @JsonKey(name: 'coverArt')  String? coverArtId,  int? year,  String? genre, @JsonKey(name: 'songCount')  int songCount,  int duration, @JsonKey(name: 'song')  List<SongDto> songs, @JsonKey(name: 'userRating')  int? userRating)?  $default,) {final _that = this;
switch (_that) {
case _AlbumDto() when $default != null:
return $default(_that.id,_that.name,_that.artistId,_that.artist,_that.coverArtId,_that.year,_that.genre,_that.songCount,_that.duration,_that.songs,_that.userRating);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlbumDto implements AlbumDto {
  const _AlbumDto({required this.id, required this.name, @JsonKey(name: 'artistId') this.artistId, this.artist, @JsonKey(name: 'coverArt') this.coverArtId, this.year, this.genre, @JsonKey(name: 'songCount') this.songCount = 0, this.duration = 0, @JsonKey(name: 'song') final  List<SongDto> songs = const [], @JsonKey(name: 'userRating') this.userRating}): _songs = songs;
  factory _AlbumDto.fromJson(Map<String, dynamic> json) => _$AlbumDtoFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey(name: 'artistId') final  String? artistId;
@override final  String? artist;
@override@JsonKey(name: 'coverArt') final  String? coverArtId;
@override final  int? year;
@override final  String? genre;
@override@JsonKey(name: 'songCount') final  int songCount;
@override@JsonKey() final  int duration;
 final  List<SongDto> _songs;
@override@JsonKey(name: 'song') List<SongDto> get songs {
  if (_songs is EqualUnmodifiableListView) return _songs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_songs);
}

@override@JsonKey(name: 'userRating') final  int? userRating;

/// Create a copy of AlbumDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlbumDtoCopyWith<_AlbumDto> get copyWith => __$AlbumDtoCopyWithImpl<_AlbumDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlbumDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlbumDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other._songs, _songs)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,artistId,artist,coverArtId,year,genre,songCount,duration,const DeepCollectionEquality().hash(_songs),userRating);

@override
String toString() {
  return 'AlbumDto(id: $id, name: $name, artistId: $artistId, artist: $artist, coverArtId: $coverArtId, year: $year, genre: $genre, songCount: $songCount, duration: $duration, songs: $songs, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class _$AlbumDtoCopyWith<$Res> implements $AlbumDtoCopyWith<$Res> {
  factory _$AlbumDtoCopyWith(_AlbumDto value, $Res Function(_AlbumDto) _then) = __$AlbumDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name,@JsonKey(name: 'artistId') String? artistId, String? artist,@JsonKey(name: 'coverArt') String? coverArtId, int? year, String? genre,@JsonKey(name: 'songCount') int songCount, int duration,@JsonKey(name: 'song') List<SongDto> songs,@JsonKey(name: 'userRating') int? userRating
});




}
/// @nodoc
class __$AlbumDtoCopyWithImpl<$Res>
    implements _$AlbumDtoCopyWith<$Res> {
  __$AlbumDtoCopyWithImpl(this._self, this._then);

  final _AlbumDto _self;
  final $Res Function(_AlbumDto) _then;

/// Create a copy of AlbumDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? artistId = freezed,Object? artist = freezed,Object? coverArtId = freezed,Object? year = freezed,Object? genre = freezed,Object? songCount = null,Object? duration = null,Object? songs = null,Object? userRating = freezed,}) {
  return _then(_AlbumDto(
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
as List<SongDto>,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
