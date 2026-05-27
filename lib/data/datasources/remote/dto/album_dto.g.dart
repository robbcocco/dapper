// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AlbumDtoImpl _$$AlbumDtoImplFromJson(Map<String, dynamic> json) =>
    _$AlbumDtoImpl(
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
    );

Map<String, dynamic> _$$AlbumDtoImplToJson(_$AlbumDtoImpl instance) =>
    <String, dynamic>{
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
    };
