// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SongDtoImpl _$$SongDtoImplFromJson(Map<String, dynamic> json) =>
    _$SongDtoImpl(
      id: json['id'] as String,
      title: json['title'] as String,
      albumId: json['albumId'] as String?,
      artistId: json['artistId'] as String?,
      album: json['album'] as String?,
      artist: json['artist'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      bitRate: (json['bitRate'] as num?)?.toInt(),
      contentType: json['contentType'] as String?,
      suffix: json['suffix'] as String?,
      size: (json['size'] as num?)?.toInt(),
      coverArtId: json['coverArt'] as String?,
      track: (json['track'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      genre: json['genre'] as String?,
      albumArtist: json['albumArtist'] as String?,
      userRating: (json['userRating'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$SongDtoImplToJson(_$SongDtoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'albumId': instance.albumId,
      'artistId': instance.artistId,
      'album': instance.album,
      'artist': instance.artist,
      'duration': instance.duration,
      'bitRate': instance.bitRate,
      'contentType': instance.contentType,
      'suffix': instance.suffix,
      'size': instance.size,
      'coverArt': instance.coverArtId,
      'track': instance.track,
      'discNumber': instance.discNumber,
      'year': instance.year,
      'genre': instance.genre,
      'albumArtist': instance.albumArtist,
      'userRating': instance.userRating,
    };
