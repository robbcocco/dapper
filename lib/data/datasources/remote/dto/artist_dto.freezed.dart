// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'artist_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ArtistDto {

 String get id; String get name;@JsonKey(name: 'coverArt') String? get coverArtId;@JsonKey(name: 'albumCount') int get albumCount; String? get musicBrainzId;
/// Create a copy of ArtistDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArtistDtoCopyWith<ArtistDto> get copyWith => _$ArtistDtoCopyWithImpl<ArtistDto>(this as ArtistDto, _$identity);

  /// Serializes this ArtistDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArtistDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.albumCount, albumCount) || other.albumCount == albumCount)&&(identical(other.musicBrainzId, musicBrainzId) || other.musicBrainzId == musicBrainzId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,coverArtId,albumCount,musicBrainzId);

@override
String toString() {
  return 'ArtistDto(id: $id, name: $name, coverArtId: $coverArtId, albumCount: $albumCount, musicBrainzId: $musicBrainzId)';
}


}

/// @nodoc
abstract mixin class $ArtistDtoCopyWith<$Res>  {
  factory $ArtistDtoCopyWith(ArtistDto value, $Res Function(ArtistDto) _then) = _$ArtistDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name,@JsonKey(name: 'coverArt') String? coverArtId,@JsonKey(name: 'albumCount') int albumCount, String? musicBrainzId
});




}
/// @nodoc
class _$ArtistDtoCopyWithImpl<$Res>
    implements $ArtistDtoCopyWith<$Res> {
  _$ArtistDtoCopyWithImpl(this._self, this._then);

  final ArtistDto _self;
  final $Res Function(ArtistDto) _then;

/// Create a copy of ArtistDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? coverArtId = freezed,Object? albumCount = null,Object? musicBrainzId = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,albumCount: null == albumCount ? _self.albumCount : albumCount // ignore: cast_nullable_to_non_nullable
as int,musicBrainzId: freezed == musicBrainzId ? _self.musicBrainzId : musicBrainzId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ArtistDto].
extension ArtistDtoPatterns on ArtistDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArtistDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArtistDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArtistDto value)  $default,){
final _that = this;
switch (_that) {
case _ArtistDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArtistDto value)?  $default,){
final _that = this;
switch (_that) {
case _ArtistDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name, @JsonKey(name: 'coverArt')  String? coverArtId, @JsonKey(name: 'albumCount')  int albumCount,  String? musicBrainzId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArtistDto() when $default != null:
return $default(_that.id,_that.name,_that.coverArtId,_that.albumCount,_that.musicBrainzId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name, @JsonKey(name: 'coverArt')  String? coverArtId, @JsonKey(name: 'albumCount')  int albumCount,  String? musicBrainzId)  $default,) {final _that = this;
switch (_that) {
case _ArtistDto():
return $default(_that.id,_that.name,_that.coverArtId,_that.albumCount,_that.musicBrainzId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name, @JsonKey(name: 'coverArt')  String? coverArtId, @JsonKey(name: 'albumCount')  int albumCount,  String? musicBrainzId)?  $default,) {final _that = this;
switch (_that) {
case _ArtistDto() when $default != null:
return $default(_that.id,_that.name,_that.coverArtId,_that.albumCount,_that.musicBrainzId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ArtistDto implements ArtistDto {
  const _ArtistDto({required this.id, required this.name, @JsonKey(name: 'coverArt') this.coverArtId, @JsonKey(name: 'albumCount') this.albumCount = 0, this.musicBrainzId});
  factory _ArtistDto.fromJson(Map<String, dynamic> json) => _$ArtistDtoFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey(name: 'coverArt') final  String? coverArtId;
@override@JsonKey(name: 'albumCount') final  int albumCount;
@override final  String? musicBrainzId;

/// Create a copy of ArtistDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArtistDtoCopyWith<_ArtistDto> get copyWith => __$ArtistDtoCopyWithImpl<_ArtistDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ArtistDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArtistDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.coverArtId, coverArtId) || other.coverArtId == coverArtId)&&(identical(other.albumCount, albumCount) || other.albumCount == albumCount)&&(identical(other.musicBrainzId, musicBrainzId) || other.musicBrainzId == musicBrainzId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,coverArtId,albumCount,musicBrainzId);

@override
String toString() {
  return 'ArtistDto(id: $id, name: $name, coverArtId: $coverArtId, albumCount: $albumCount, musicBrainzId: $musicBrainzId)';
}


}

/// @nodoc
abstract mixin class _$ArtistDtoCopyWith<$Res> implements $ArtistDtoCopyWith<$Res> {
  factory _$ArtistDtoCopyWith(_ArtistDto value, $Res Function(_ArtistDto) _then) = __$ArtistDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name,@JsonKey(name: 'coverArt') String? coverArtId,@JsonKey(name: 'albumCount') int albumCount, String? musicBrainzId
});




}
/// @nodoc
class __$ArtistDtoCopyWithImpl<$Res>
    implements _$ArtistDtoCopyWith<$Res> {
  __$ArtistDtoCopyWithImpl(this._self, this._then);

  final _ArtistDto _self;
  final $Res Function(_ArtistDto) _then;

/// Create a copy of ArtistDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? coverArtId = freezed,Object? albumCount = null,Object? musicBrainzId = freezed,}) {
  return _then(_ArtistDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,coverArtId: freezed == coverArtId ? _self.coverArtId : coverArtId // ignore: cast_nullable_to_non_nullable
as String?,albumCount: null == albumCount ? _self.albumCount : albumCount // ignore: cast_nullable_to_non_nullable
as int,musicBrainzId: freezed == musicBrainzId ? _self.musicBrainzId : musicBrainzId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
