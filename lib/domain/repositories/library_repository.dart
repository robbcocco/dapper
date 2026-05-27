import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/search_results.dart';
import '../models/song.dart';

abstract interface class LibraryRepository {
  Future<List<Artist>> getArtists();
  Future<List<Album>> getAlbumsByArtist(String artistId);
  Future<Album> getAlbum(String albumId);
  Future<List<Album>> getRecentAlbums({int size = 20, int offset = 0});
  Future<List<Album>> getAllAlbums({int size = 500, int offset = 0});
  Future<List<Song>> getAllSongs({int count = 500, int offset = 0});
  Future<List<Playlist>> getPlaylists();
  Future<Playlist> getPlaylist(String playlistId);
  Future<Playlist> createPlaylist(String name, {List<String> songIds});
  Future<void> updatePlaylist(
    String id, {
    String? name,
    List<String> songIdsToAdd,
    List<int> songIndexesToRemove,
  });
  Future<void> deletePlaylist(String id);
  Future<List<Song>> search(String query);
  Future<SearchResults> searchAll(String query);
  Future<void> star(String songId);
  Future<void> unstar(String songId);
  Future<Set<String>> getStarredSongIds();
  Uri coverArtUri(String coverArtId, {int size = 256});
  Uri streamUri(String songId);
  Uri downloadUri(String songId);
}
