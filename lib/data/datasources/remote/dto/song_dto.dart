import 'package:freezed_annotation/freezed_annotation.dart';

part 'song_dto.freezed.dart';
part 'song_dto.g.dart';

@freezed
abstract class SongDto with _$SongDto {
  const factory SongDto({
    required String id,
    required String title,
    @JsonKey(name: 'albumId') String? albumId,
    @JsonKey(name: 'artistId') String? artistId,
    String? album,
    String? artist,
    int? duration,
    int? bitRate,
    String? contentType,
    String? suffix,
    int? size,
    @JsonKey(name: 'coverArt') String? coverArtId,
    int? track,
    @JsonKey(name: 'discNumber') int? discNumber,
    int? year,
    String? genre,
    @JsonKey(name: 'albumArtist') String? albumArtist,
    // Subsonic `userRating` (1-5) — present only when the user has rated.
    @JsonKey(name: 'userRating') int? userRating,
  }) = _SongDto;

  factory SongDto.fromJson(Map<String, dynamic> json) =>
      _$SongDtoFromJson(json);
}
