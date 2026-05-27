import 'package:freezed_annotation/freezed_annotation.dart';
import 'song.dart';

part 'album.freezed.dart';

@freezed
class Album with _$Album {
  const factory Album({
    required String id,
    required String name,
    String? artistId,
    String? artist,
    String? coverArtId,
    int? year,
    String? genre,
    @Default(0) int songCount,
    @Default(0) int duration,
    @Default([]) List<Song> songs,
  }) = _Album;
}
