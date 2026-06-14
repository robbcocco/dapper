import 'package:freezed_annotation/freezed_annotation.dart';
import 'song.dart';

part 'playlist.freezed.dart';

@freezed
abstract class Playlist with _$Playlist {
  const factory Playlist({
    required String id,
    required String name,
    String? comment,
    String? coverArtId,
    @Default(0) int songCount,
    @Default(0) int duration,
    @Default([]) List<Song> songs,
  }) = _Playlist;
}
