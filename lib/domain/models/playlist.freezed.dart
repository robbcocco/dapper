// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'playlist.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Playlist {

 String get id; String get name; String? get comment; String? get coverArtId; int get songCount; int get duration; List<Song> get songs;
/// Create a copy of Playlist
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlaylistCopyWith<Playlist> get copyWith => _$PlaylistCopyWithImpl<Playlist>(this as Playlist, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Playlist&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.comment, comment) || other.comment == comment)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other.songs, songs));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,comment,coverArtId,songCount,duration,const DeepCollectionEquality().hash(songs));

@override
String toString() {
  return 'Playlist(id: $id, name: $name, comment: $comment, coverArtId: $coverArtId, songCount: $songCount, duration: $duration, songs: $songs)';
}


}

/// @nodoc
abstract mixin class $PlaylistCopyWith<$Res>  {
  factory $PlaylistCopyWith(Playlist value, $Res Function(Playlist) _then) = _$PlaylistCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? comment, String? coverArtId, int songCount, int duration, List<Song> songs
});




}
/// @nodoc
class _$PlaylistCopyWithImpl<$Res>
    implements $PlaylistCopyWith<$Res> {
  _$PlaylistCopyWithImpl(this._self, this._then);

  final Playlist _self;
  final $Res Function(Playlist) _then;

/// Create a copy of Playlist
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
as List<Song>,
  ));
}

}


/// Adds pattern-matching-related methods to [Playlist].
extension PlaylistPatterns on Playlist {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Playlist value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Playlist() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Playlist value)  $default,){
final _that = this;
switch (_that) {
case _Playlist():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Playlist value)?  $default,){
final _that = this;
switch (_that) {
case _Playlist() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? comment,  String? coverArtId,  int songCount,  int duration,  List<Song> songs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Playlist() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? comment,  String? coverArtId,  int songCount,  int duration,  List<Song> songs)  $default,) {final _that = this;
switch (_that) {
case _Playlist():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? comment,  String? coverArtId,  int songCount,  int duration,  List<Song> songs)?  $default,) {final _that = this;
switch (_that) {
case _Playlist() when $default != null:
return $default(_that.id,_that.name,_that.comment,_that.coverArtId,_that.songCount,_that.duration,_that.songs);case _:
  return null;

}
}

}

/// @nodoc


class _Playlist implements Playlist {
  const _Playlist({required this.id, required this.name, this.comment, this.coverArtId, this.songCount = 0, this.duration = 0, final  List<Song> songs = const []}): _songs = songs;
  

@override final  String id;
@override final  String name;
@override final  String? comment;
@override final  String? coverArtId;
@override@JsonKey() final  int songCount;
@override@JsonKey() final  int duration;
 final  List<Song> _songs;
@override@JsonKey() List<Song> get songs {
  if (_songs is EqualUnmodifiableListView) return _songs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_songs);
}


/// Create a copy of Playlist
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlaylistCopyWith<_Playlist> get copyWith => __$PlaylistCopyWithImpl<_Playlist>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Playlist&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.comment, comment) || other.comment == comment)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.songCount, songCount) || other.songCount == songCount)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other._songs, _songs));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,comment,coverArtId,songCount,duration,const DeepCollectionEquality().hash(_songs));

@override
String toString() {
  return 'Playlist(id: $id, name: $name, comment: $comment, coverArtId: $coverArtId, songCount: $songCount, duration: $duration, songs: $songs)';
}


}

/// @nodoc
abstract mixin class _$PlaylistCopyWith<$Res> implements $PlaylistCopyWith<$Res> {
  factory _$PlaylistCopyWith(_Playlist value, $Res Function(_Playlist) _then) = __$PlaylistCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? comment, String? coverArtId, int songCount, int duration, List<Song> songs
});




}
/// @nodoc
class __$PlaylistCopyWithImpl<$Res>
    implements _$PlaylistCopyWith<$Res> {
  __$PlaylistCopyWithImpl(this._self, this._then);

  final _Playlist _self;
  final $Res Function(_Playlist) _then;

/// Create a copy of Playlist
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? comment = freezed,Object? coverArtId = freezed,Object? songCount = null,Object? duration = null,Object? songs = null,}) {
  return _then(_Playlist(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,comment: freezed == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as String?,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,songCount: null == songCount ? _self.songCount : songCount // ignore: cast_nullable_to_non_nullable
as int,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int,songs: null == songs ? _self._songs : songs // ignore: cast_nullable_to_non_nullable
as List<Song>,
  ));
}


}

// dart format on
