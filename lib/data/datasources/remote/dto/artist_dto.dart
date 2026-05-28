import 'package:freezed_annotation/freezed_annotation.dart';

part 'artist_dto.freezed.dart';
part 'artist_dto.g.dart';

@freezed
class ArtistDto with _$ArtistDto {
  const factory ArtistDto({
    required String id,
    required String name,
    @JsonKey(name: 'coverArt') String? coverArtId,
    @JsonKey(name: 'albumCount') @Default(0) int albumCount,
    String? musicBrainzId,
  }) = _ArtistDto;

  factory ArtistDto.fromJson(Map<String, dynamic> json) =>
      _$ArtistDtoFromJson(json);
}
