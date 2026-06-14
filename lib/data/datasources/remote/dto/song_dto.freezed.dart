// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'song_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SongDto {

 String get id; String get title;@JsonKey(name: 'albumId') String? get albumId;@JsonKey(name: 'artistId') String? get artistId; String? get album; String? get artist; int? get duration; int? get bitRate; String? get contentType; String? get suffix; int? get size;@JsonKey(name: 'coverArt') String? get coverArtId; int? get track;@JsonKey(name: 'discNumber') int? get discNumber; int? get year; String? get genre;@JsonKey(name: 'albumArtist') String? get albumArtist;@JsonKey(name: 'userRating') int? get userRating;
/// Create a copy of SongDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SongDtoCopyWith<SongDto> get copyWith => _$SongDtoCopyWithImpl<SongDto>(this as SongDto, _$identity);

  /// Serializes this SongDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SongDto&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.albumId, albumId) || other.albumId == albumId)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.album, album) || other.album == album)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.bitRate, bitRate) || other.bitRate == bitRate)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.suffix, suffix) || other.suffix == suffix)&&(identical(other.size, size) || other.size == size)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.track, track) || other.track == track)&&(identical(other.discNumber, discNumber) || other.discNumber == discNumber)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.albumArtist, albumArtist) || other.albumArtist == albumArtist)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,albumId,artistId,album,artist,duration,bitRate,contentType,suffix,size,coverArtId,track,discNumber,year,genre,albumArtist,userRating);

@override
String toString() {
  return 'SongDto(id: $id, title: $title, albumId: $albumId, artistId: $artistId, album: $album, artist: $artist, duration: $duration, bitRate: $bitRate, contentType: $contentType, suffix: $suffix, size: $size, coverArtId: $coverArtId, track: $track, discNumber: $discNumber, year: $year, genre: $genre, albumArtist: $albumArtist, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class $SongDtoCopyWith<$Res>  {
  factory $SongDtoCopyWith(SongDto value, $Res Function(SongDto) _then) = _$SongDtoCopyWithImpl;
@useResult
$Res call({
 String id, String title,@JsonKey(name: 'albumId') String? albumId,@JsonKey(name: 'artistId') String? artistId, String? album, String? artist, int? duration, int? bitRate, String? contentType, String? suffix, int? size,@JsonKey(name: 'coverArt') String? coverArtId, int? track,@JsonKey(name: 'discNumber') int? discNumber, int? year, String? genre,@JsonKey(name: 'albumArtist') String? albumArtist,@JsonKey(name: 'userRating') int? userRating
});




}
/// @nodoc
class _$SongDtoCopyWithImpl<$Res>
    implements $SongDtoCopyWith<$Res> {
  _$SongDtoCopyWithImpl(this._self, this._then);

  final SongDto _self;
  final $Res Function(SongDto) _then;

/// Create a copy of SongDto
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


/// Adds pattern-matching-related methods to [SongDto].
extension SongDtoPatterns on SongDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SongDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SongDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SongDto value)  $default,){
final _that = this;
switch (_that) {
case _SongDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SongDto value)?  $default,){
final _that = this;
switch (_that) {
case _SongDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title, @JsonKey(name: 'albumId')  String? albumId, @JsonKey(name: 'artistId')  String? artistId,  String? album,  String? artist,  int? duration,  int? bitRate,  String? contentType,  String? suffix,  int? size, @JsonKey(name: 'coverArt')  String? coverArtId,  int? track, @JsonKey(name: 'discNumber')  int? discNumber,  int? year,  String? genre, @JsonKey(name: 'albumArtist')  String? albumArtist, @JsonKey(name: 'userRating')  int? userRating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SongDto() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title, @JsonKey(name: 'albumId')  String? albumId, @JsonKey(name: 'artistId')  String? artistId,  String? album,  String? artist,  int? duration,  int? bitRate,  String? contentType,  String? suffix,  int? size, @JsonKey(name: 'coverArt')  String? coverArtId,  int? track, @JsonKey(name: 'discNumber')  int? discNumber,  int? year,  String? genre, @JsonKey(name: 'albumArtist')  String? albumArtist, @JsonKey(name: 'userRating')  int? userRating)  $default,) {final _that = this;
switch (_that) {
case _SongDto():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title, @JsonKey(name: 'albumId')  String? albumId, @JsonKey(name: 'artistId')  String? artistId,  String? album,  String? artist,  int? duration,  int? bitRate,  String? contentType,  String? suffix,  int? size, @JsonKey(name: 'coverArt')  String? coverArtId,  int? track, @JsonKey(name: 'discNumber')  int? discNumber,  int? year,  String? genre, @JsonKey(name: 'albumArtist')  String? albumArtist, @JsonKey(name: 'userRating')  int? userRating)?  $default,) {final _that = this;
switch (_that) {
case _SongDto() when $default != null:
return $default(_that.id,_that.title,_that.albumId,_that.artistId,_that.album,_that.artist,_that.duration,_that.bitRate,_that.contentType,_that.suffix,_that.size,_that.coverArtId,_that.track,_that.discNumber,_that.year,_that.genre,_that.albumArtist,_that.userRating);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SongDto implements SongDto {
  const _SongDto({required this.id, required this.title, @JsonKey(name: 'albumId') this.albumId, @JsonKey(name: 'artistId') this.artistId, this.album, this.artist, this.duration, this.bitRate, this.contentType, this.suffix, this.size, @JsonKey(name: 'coverArt') this.coverArtId, this.track, @JsonKey(name: 'discNumber') this.discNumber, this.year, this.genre, @JsonKey(name: 'albumArtist') this.albumArtist, @JsonKey(name: 'userRating') this.userRating});
  factory _SongDto.fromJson(Map<String, dynamic> json) => _$SongDtoFromJson(json);

@override final  String id;
@override final  String title;
@override@JsonKey(name: 'albumId') final  String? albumId;
@override@JsonKey(name: 'artistId') final  String? artistId;
@override final  String? album;
@override final  String? artist;
@override final  int? duration;
@override final  int? bitRate;
@override final  String? contentType;
@override final  String? suffix;
@override final  int? size;
@override@JsonKey(name: 'coverArt') final  String? coverArtId;
@override final  int? track;
@override@JsonKey(name: 'discNumber') final  int? discNumber;
@override final  int? year;
@override final  String? genre;
@override@JsonKey(name: 'albumArtist') final  String? albumArtist;
@override@JsonKey(name: 'userRating') final  int? userRating;

/// Create a copy of SongDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SongDtoCopyWith<_SongDto> get copyWith => __$SongDtoCopyWithImpl<_SongDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SongDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SongDto&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.albumId, albumId) || other.albumId == albumId)&&(identical(other.artistId, artistId) || other.artistId == artistId)&&(identical(other.album, album) || other.album == album)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.bitRate, bitRate) || other.bitRate == bitRate)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.suffix, suffix) || other.suffix == suffix)&&(identical(other.size, size) || other.size == size)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.track, track) || other.track == track)&&(identical(other.discNumber, discNumber) || other.discNumber == discNumber)&&(identical(other.year, year) || other.year == year)&&(identical(other.genre, genre) || other.genre == genre)&&(identical(other.albumArtist, albumArtist) || other.albumArtist == albumArtist)&&(identical(other.userRating, userRating) || other.userRating == userRating));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,albumId,artistId,album,artist,duration,bitRate,contentType,suffix,size,coverArtId,track,discNumber,year,genre,albumArtist,userRating);

@override
String toString() {
  return 'SongDto(id: $id, title: $title, albumId: $albumId, artistId: $artistId, album: $album, artist: $artist, duration: $duration, bitRate: $bitRate, contentType: $contentType, suffix: $suffix, size: $size, coverArtId: $coverArtId, track: $track, discNumber: $discNumber, year: $year, genre: $genre, albumArtist: $albumArtist, userRating: $userRating)';
}


}

/// @nodoc
abstract mixin class _$SongDtoCopyWith<$Res> implements $SongDtoCopyWith<$Res> {
  factory _$SongDtoCopyWith(_SongDto value, $Res Function(_SongDto) _then) = __$SongDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String title,@JsonKey(name: 'albumId') String? albumId,@JsonKey(name: 'artistId') String? artistId, String? album, String? artist, int? duration, int? bitRate, String? contentType, String? suffix, int? size,@JsonKey(name: 'coverArt') String? coverArtId, int? track,@JsonKey(name: 'discNumber') int? discNumber, int? year, String? genre,@JsonKey(name: 'albumArtist') String? albumArtist,@JsonKey(name: 'userRating') int? userRating
});




}
/// @nodoc
class __$SongDtoCopyWithImpl<$Res>
    implements _$SongDtoCopyWith<$Res> {
  __$SongDtoCopyWithImpl(this._self, this._then);

  final _SongDto _self;
  final $Res Function(_SongDto) _then;

/// Create a copy of SongDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? albumId = freezed,Object? artistId = freezed,Object? album = freezed,Object? artist = freezed,Object? duration = freezed,Object? bitRate = freezed,Object? contentType = freezed,Object? suffix = freezed,Object? size = freezed,Object? coverArtId = freezed,Object? track = freezed,Object? discNumber = freezed,Object? year = freezed,Object? genre = freezed,Object? albumArtist = freezed,Object? userRating = freezed,}) {
  return _then(_SongDto(
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
