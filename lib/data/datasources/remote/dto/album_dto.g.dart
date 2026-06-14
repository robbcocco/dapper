// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AlbumDto _$AlbumDtoFromJson(Map<String, dynamic> json) => _AlbumDto(
  id: json['id'] as String,
  name: json['name'] as String,
  artistId: json['artistId'] as String?,
  artist: json['artist'] as String?,
  coverArtId: json['coverArt'] as String?,
  year: (json['year'] as num?)?.toInt(),
  genre: json['genre'] as String?,
  songCount: (json['songCount'] as num?)?.toInt() ?? 0,
  duration: (json['duration'] as num?)?.toInt() ?? 0,
  songs:
      (json['song'] as List<dynamic>?)
          ?.map((e) => SongDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  userRating: (json['userRating'] as num?)?.toInt(),
);

Map<String, dynamic> _$AlbumDtoToJson(_AlbumDto instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'artistId': instance.artistId,
  'artist': instance.artist,
  'coverArt': instance.coverArtId,
  'year': instance.year,
  'genre': instance.genre,
  'songCount': instance.songCount,
  'duration': instance.duration,
  'song': instance.songs,
  'userRating': instance.userRating,
};
