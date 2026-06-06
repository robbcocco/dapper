import 'package:freezed_annotation/freezed_annotation.dart';

part 'song.freezed.dart';

@freezed
class Song with _$Song {
  const factory Song({
    required String id,
    required String title,
    String? albumId,
    String? artistId,
    String? album,
    String? artist,
    int? duration,
    int? bitRate,
    String? contentType,
    String? suffix,
    int? size,
    String? coverArtId,
    int? track,
    int? discNumber,
    int? year,
    String? genre,
    String? albumArtist,
    int? userRating,
  }) = _Song;
}
