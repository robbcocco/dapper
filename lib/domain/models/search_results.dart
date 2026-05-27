import 'album.dart';
import 'artist.dart';
import 'song.dart';

class SearchResults {
  const SearchResults({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  final List<Artist> artists;
  final List<Album> albums;
  final List<Song> songs;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}
