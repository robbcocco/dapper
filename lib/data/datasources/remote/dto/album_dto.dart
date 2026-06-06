import 'package:freezed_annotation/freezed_annotation.dart';
import 'song_dto.dart';

part 'album_dto.freezed.dart';
part 'album_dto.g.dart';

@freezed
class AlbumDto with _$AlbumDto {
  const factory AlbumDto({
    required String id,
    required String name,
    @JsonKey(name: 'artistId') String? artistId,
    String? artist,
    @JsonKey(name: 'coverArt') String? coverArtId,
    int? year,
    String? genre,
    @JsonKey(name: 'songCount') @Default(0) int songCount,
    @Default(0) int duration,
    @JsonKey(name: 'song') @Default([]) List<SongDto> songs,
    @JsonKey(name: 'userRating') int? userRating,
  }) = _AlbumDto;

  factory AlbumDto.fromJson(Map<String, dynamic> json) =>
      _$AlbumDtoFromJson(json);
}
