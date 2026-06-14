import 'package:freezed_annotation/freezed_annotation.dart';
import 'song_dto.dart';

part 'playlist_dto.freezed.dart';
part 'playlist_dto.g.dart';

@freezed
abstract class PlaylistDto with _$PlaylistDto {
  const factory PlaylistDto({
    required String id,
    required String name,
    String? comment,
    @JsonKey(name: 'coverArt') String? coverArtId,
    @JsonKey(name: 'songCount') @Default(0) int songCount,
    @Default(0) int duration,
    @JsonKey(name: 'entry') @Default([]) List<SongDto> songs,
  }) = _PlaylistDto;

  factory PlaylistDto.fromJson(Map<String, dynamic> json) =>
      _$PlaylistDtoFromJson(json);
}
