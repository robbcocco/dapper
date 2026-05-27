// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PlaylistDtoImpl _$$PlaylistDtoImplFromJson(Map<String, dynamic> json) =>
    _$PlaylistDtoImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      comment: json['comment'] as String?,
      coverArtId: json['coverArt'] as String?,
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      songs:
          (json['entry'] as List<dynamic>?)
              ?.map((e) => SongDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$PlaylistDtoImplToJson(_$PlaylistDtoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'comment': instance.comment,
      'coverArt': instance.coverArtId,
      'songCount': instance.songCount,
      'duration': instance.duration,
      'entry': instance.songs,
    };
