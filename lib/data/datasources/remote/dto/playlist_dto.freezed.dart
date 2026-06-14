// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playlist_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PlaylistDto {

 String get id; String get name; String? get comment;@JsonKey(name: 'coverArt') String? get coverArtId;@JsonKey(name: 'songCount') int get songCount; int get duration;@JsonKey(name: 'entry') List<SongDto> get songs;
/// Create a copy of PlaylistDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaylistDtoCopyWith<PlaylistDto> get copyWith => _$PlaylistDtoCopyWithImpl<PlaylistDto>(this as PlaylistDto, _$identity);

  /// Serializes this PlaylistDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlaylistDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.comment, comment) || other.comment == comment)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other.songs, songs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,comment,coverArtId,songCount,duration,const DeepCollectionEquality().hash(songs));

@override
String toString() {
  return 'PlaylistDto(id: $id, name: $name, comment: $comment, coverArtId: $coverArtId, songCount: $songCount, duration: $duration, songs: $songs)';
}


}

/// @nodoc
abstract mixin class $PlaylistDtoCopyWith<$Res>  {
  factory $PlaylistDtoCopyWith(PlaylistDto value, $Res Function(PlaylistDto) _then) = _$PlaylistDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? comment,@JsonKey(name: 'coverArt') String? coverArtId,@JsonKey(name: 'songCount') int songCount, int duration,@JsonKey(name: 'entry') List<SongDto> songs
});




}
/// @nodoc
class _$PlaylistDtoCopyWithImpl<$Res>
    implements $PlaylistDtoCopyWith<$Res> {
  _$PlaylistDtoCopyWithImpl(this._self, this._then);

  final PlaylistDto _self;
  final $Res Function(PlaylistDto) _then;

/// Create a copy of PlaylistDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? comment = freezed,Object? coverArtId = freezed,Object? songCount = null,Object? duration = null,Object? songs = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,comment: freezed == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as String?,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,songCount: null == songCount ? _self.songCount : songCount // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int,songs: null == songs ? _self.songs : songs // ignore: cast_nullable_to_non_nullable
as List<SongDto>,
  ));
}

}


/// Adds pattern-matching-related methods to [PlaylistDto].
extension PlaylistDtoPatterns on PlaylistDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlaylistDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlaylistDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlaylistDto value)  $default,){
final _that = this;
switch (_that) {
case _PlaylistDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlaylistDto value)?  $default,){
final _that = this;
switch (_that) {
case _PlaylistDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? comment, @JsonKey(name: 'coverArt')  String? coverArtId, @JsonKey(name: 'songCount')  int songCount,  int duration, @JsonKey(name: 'entry')  List<SongDto> songs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlaylistDto() when $default != null:
return $default(_that.id,_that.name,_that.comment,_that.coverArtId,_that.songCount,_that.duration,_that.songs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? comment, @JsonKey(name: 'coverArt')  String? coverArtId, @JsonKey(name: 'songCount')  int songCount,  int duration, @JsonKey(name: 'entry')  List<SongDto> songs)  $default,) {final _that = this;
switch (_that) {
case _PlaylistDto():
return $default(_that.id,_that.name,_that.comment,_that.coverArtId,_that.songCount,_that.duration,_that.songs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? comment, @JsonKey(name: 'coverArt')  String? coverArtId, @JsonKey(name: 'songCount')  int songCount,  int duration, @JsonKey(name: 'entry')  List<SongDto> songs)?  $default,) {final _that = this;
switch (_that) {
case _PlaylistDto() when $default != null:
return $default(_that.id,_that.name,_that.comment,_that.coverArtId,_that.songCount,_that.duration,_that.songs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PlaylistDto implements PlaylistDto {
  const _PlaylistDto({required this.id, required this.name, this.comment, @JsonKey(name: 'coverArt') this.coverArtId, @JsonKey(name: 'songCount') this.songCount = 0, this.duration = 0, @JsonKey(name: 'entry') final  List<SongDto> songs = const []}): _songs = songs;
  factory _PlaylistDto.fromJson(Map<String, dynamic> json) => _$PlaylistDtoFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? comment;
@override@JsonKey(name: 'coverArt') final  String? coverArtId;
@override@JsonKey(name: 'songCount') final  int songCount;
@override@JsonKey() final  int duration;
 final  List<SongDto> _songs;
@override@JsonKey(name: 'entry') List<SongDto> get songs {
  if (_songs is EqualUnmodifiableListView) return _songs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_songs);
}


/// Create a copy of PlaylistDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlaylistDtoCopyWith<_PlaylistDto> get copyWith => __$PlaylistDtoCopyWithImpl<_PlaylistDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlaylistDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlaylistDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.comment, comment) || other.comment == comment)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other._songs, _songs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,comment,coverArtId,songCount,duration,const DeepCollectionEquality().hash(_songs));

@override
String toString() {
  return 'PlaylistDto(id: $id, name: $name, comment: $comment, coverArtId: $coverArtId, songCount: $songCount, duration: $duration, songs: $songs)';
}


}

/// @nodoc
abstract mixin class _$PlaylistDtoCopyWith<$Res> implements $PlaylistDtoCopyWith<$Res> {
  factory _$PlaylistDtoCopyWith(_PlaylistDto value, $Res Function(_PlaylistDto) _then) = __$PlaylistDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? comment,@JsonKey(name: 'coverArt') String? coverArtId,@JsonKey(name: 'songCount') int songCount, int duration,@JsonKey(name: 'entry') List<SongDto> songs
});




}
/// @nodoc
class __$PlaylistDtoCopyWithImpl<$Res>
    implements _$PlaylistDtoCopyWith<$Res> {
  __$PlaylistDtoCopyWithImpl(this._self, this._then);

  final _PlaylistDto _self;
  final $Res Function(_PlaylistDto) _then;

/// Create a copy of PlaylistDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? comment = freezed,Object? coverArtId = freezed,Object? songCount = null,Object? duration = null,Object? songs = null,}) {
  return _then(_PlaylistDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,comment: freezed == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as String?,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,songCount: null == songCount ? _self.songCount : songCount // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int,songs: null == songs ? _self._songs : songs // ignore: cast_nullable_to_non_nullable
as List<SongDto>,
  ));
}


}

// dart format on
