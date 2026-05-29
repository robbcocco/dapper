import '../../domain/models/album.dart';
import '../../domain/models/artist.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/search_results.dart';
import '../../domain/models/song.dart';
import '../../domain/repositories/library_repository.dart';
import '../datasources/remote/dto/album_dto.dart';
import '../datasources/remote/dto/artist_dto.dart';
import '../datasources/remote/dto/playlist_dto.dart';
import '../datasources/remote/dto/song_dto.dart';
import '../datasources/remote/subsonic_api.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl(this._api);

  final SubsonicApi _api;

  // Session-scope LRU for getAlbum. Most callers go through albumProvider
  // (a Riverpod FutureProvider.family) which already memoises, but a few
  // direct callers — playArtist iterating an artist's albums in particular —
  // bypass Riverpod and would otherwise re-fetch on every invocation. Cache
  // dies with this repository instance, which is replaced on credential
  // change, so we never serve cross-server data.
  static const _albumCacheCap = 50;
  final Map<String, Album> _albumCache = {};

  @override
  Future<List<Artist>> getArtists() async {
    final dtos = await _api.getArtists();
    return dtos.map(_mapArtist).toList();
  }

  @override
  Future<List<Album>> getAlbumsByArtist(String artistId) async {
    final dtos = await _api.getAlbumsByArtist(artistId);
    return dtos.map((d) => _mapAlbum(d)).toList();
  }

  @override
  Future<Album> getAlbum(String albumId) async {
    // LRU promote-on-read using Dart's LinkedHashMap insertion-order semantics.
    final cached = _albumCache.remove(albumId);
    if (cached != null) {
      _albumCache[albumId] = cached;
      return cached;
    }
    final dto = await _api.getAlbum(albumId);
    final album = _mapAlbum(dto);
    if (_albumCache.length >= _albumCacheCap) {
      _albumCache.remove(_albumCache.keys.first);
    }
    _albumCache[albumId] = album;
    return album;
  }

  @override
  Future<List<Album>> getRecentAlbums({int size = 20, int offset = 0}) async {
    final dtos = await _api.getRecentAlbums(size: size, offset: offset);
    return dtos.map((d) => _mapAlbum(d)).toList();
  }

  @override
  Future<List<Album>> getAllAlbums({int size = 500, int offset = 0}) async {
    final dtos = await _api.getAllAlbums(size: size, offset: offset);
    return dtos.map((d) => _mapAlbum(d)).toList();
  }

  @override
  Future<List<Playlist>> getPlaylists() async {
    final dtos = await _api.getPlaylists();
    return dtos.map(_mapPlaylist).toList();
  }

  @override
  Future<Playlist> getPlaylist(String playlistId) async {
    final dto = await _api.getPlaylist(playlistId);
    return _mapPlaylist(dto);
  }

  @override
  Future<List<Song>> getAllSongs({int count = 500, int offset = 0}) async {
    final dtos = await _api.getAllSongs(count: count, offset: offset);
    return dtos.map(_mapSong).toList();
  }

  @override
  Future<Playlist> createPlaylist(String name,
      {List<String> songIds = const []}) async {
    final dto = await _api.createPlaylist(name, songIds);
    return _mapPlaylist(dto);
  }

  @override
  Future<void> updatePlaylist(
    String id, {
    String? name,
    List<String> songIdsToAdd = const [],
    List<int> songIndexesToRemove = const [],
  }) =>
      _api.updatePlaylist(
        id,
        name: name,
        songIdsToAdd: songIdsToAdd,
        songIndexesToRemove: songIndexesToRemove,
      );

  @override
  Future<void> deletePlaylist(String id) => _api.deletePlaylist(id);

  @override
  Future<List<Song>> search(String query) async {
    final dtos = await _api.search(query);
    return dtos.map(_mapSong).toList();
  }

  @override
  Future<SearchResults> searchAll(String query) async {
    final r = await _api.searchAll(query);
    return SearchResults(
      artists: r.artists.map(_mapArtist).toList(),
      albums: r.albums.map((d) => _mapAlbum(d)).toList(),
      songs: r.songs.map(_mapSong).toList(),
    );
  }

  @override
  Future<void> star(String songId) => _api.star(songId);

  @override
  Future<void> unstar(String songId) => _api.unstar(songId);

  @override
  Future<Set<String>> getStarredSongIds() => _api.getStarredSongIds();

  @override
  Uri coverArtUri(String coverArtId, {int size = 256}) =>
      _api.coverArtUri(coverArtId, size: size);

  @override
  Uri streamUri(String songId) => _api.streamUri(songId);

  @override
  Uri downloadUri(String songId) => _api.downloadUri(songId);

  Artist _mapArtist(ArtistDto d) => Artist(
        id: d.id,
        name: d.name,
        coverArtId: d.coverArtId,
        albumCount: d.albumCount,
        musicBrainzId: d.musicBrainzId,
      );

  Album _mapAlbum(AlbumDto d) => Album(
        id: d.id,
        name: d.name,
        artistId: d.artistId,
        artist: d.artist,
        coverArtId: d.coverArtId,
        year: d.year,
        genre: d.genre,
        songCount: d.songCount,
        duration: d.duration,
        songs: d.songs.map((s) => _mapSong(s, fallbackAlbumArtist: d.artist)).toList(),
      );

  Song _mapSong(SongDto d, {String? fallbackAlbumArtist}) => Song(
        id: d.id,
        title: d.title,
        albumId: d.albumId,
        artistId: d.artistId,
        album: d.album,
        artist: d.artist,
        duration: d.duration,
        bitRate: d.bitRate,
        contentType: d.contentType,
        suffix: d.suffix,
        size: d.size,
        coverArtId: d.coverArtId,
        track: d.track,
        discNumber: d.discNumber,
        year: d.year,
        genre: d.genre,
        albumArtist: d.albumArtist ?? fallbackAlbumArtist,
      );

  Playlist _mapPlaylist(PlaylistDto d) => Playlist(
        id: d.id,
        name: d.name,
        comment: d.comment,
        coverArtId: d.coverArtId,
        songCount: d.songCount,
        duration: d.duration,
        songs: d.songs.map(_mapSong).toList(),
      );
}
