import '../models/album.dart';
import '../models/artist.dart';
import '../models/genre.dart';
import '../models/lyrics.dart';
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
  /// Sets the user rating (0-5) for a song, album, or artist. 0 clears it.
  Future<void> setRating(String id, int rating);
  /// Notifies the server about playback. [submission] = false is the
  /// "now playing" ping fired when a track starts; [submission] = true is
  /// the full scrobble fired once the listen threshold is reached.
  /// [time] is the absolute moment the play occurred — pass null for "now"
  /// (live scrobbles) or a past DateTime for backfilled scrobbles imported
  /// from device logs. Supported since Subsonic 1.8.0.
  Future<void> scrobble(String songId, {bool submission = true, DateTime? time});
  /// Returns lyrics for [songId], or null if the server has none.
  Future<Lyrics?> getLyrics(String songId);
  Future<List<Genre>> getGenres();
  Future<List<Album>> getAlbumsByGenre(String genre,
      {int size = 500, int offset = 0});
  Uri coverArtUri(String coverArtId, {int size = 256});
  Uri streamUri(String songId);
  /// Transfer-engine URL: original-quality download (via /rest/download) when
  /// [format] is null, otherwise a transcoded stream via /rest/stream with
  /// the given `maxBitRate` and `format` parameters.
  Uri transferUri(String songId, {String? format, int? maxBitRate});

  /// Bulk download URL: returns a zip of originals when [id] points to an
  /// album, artist, or playlist. No transcoding options supported.
  Uri zipUri(String id);
}
