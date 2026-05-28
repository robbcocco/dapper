// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'artist_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ArtistDtoImpl _$$ArtistDtoImplFromJson(Map<String, dynamic> json) =>
    _$ArtistDtoImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      coverArtId: json['coverArt'] as String?,
      albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
      musicBrainzId: json['musicBrainzId'] as String?,
    );

Map<String, dynamic> _$$ArtistDtoImplToJson(_$ArtistDtoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'coverArt': instance.coverArtId,
      'albumCount': instance.albumCount,
      'musicBrainzId': instance.musicBrainzId,
    };
