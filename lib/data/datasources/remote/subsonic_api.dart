import '../../../core/constants/api_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../domain/models/genre.dart';
import '../../../domain/models/lyrics.dart';
import '../../datasources/remote/dto/album_dto.dart';
import '../../datasources/remote/dto/artist_dto.dart';
import '../../datasources/remote/dto/playlist_dto.dart';
import '../../datasources/remote/dto/song_dto.dart';
import 'subsonic_client.dart';

class SubsonicApi {
  SubsonicApi(this._client);

  final SubsonicClient _client;

  // Cover-art URIs are requested on every CoverArtImage rebuild — hundreds of
  // times per second during scrolling / transfer progress ticks. Memoise by
  // (coverArtId, size). Subsonic auth tokens are md5(password+salt) and don't
  // expire server-side, so the cached URI stays valid until this SubsonicApi
  // instance is replaced (which happens automatically on credential change
  // because subsonicApiProvider rebuilds with the new client).
  final Map<String, Uri> _coverArtUriCache = {};

  Future<bool> ping() async {
    final response = await _client.get(ApiConstants.ping);
    return response['status'] == 'ok';
  }

  Future<List<ArtistDto>> getArtists() async {
    final response = await _client.get(ApiConstants.getArtists);
    final artists = response['artists'] as Map<String, dynamic>?;
    final indices = artists?['index'] as List<dynamic>? ?? const [];
    final result = <ArtistDto>[];
    for (final index in indices) {
      if (index is! Map<String, dynamic>) continue;
      final entries = index['artist'] as List<dynamic>? ?? const [];
      for (final e in entries) {
        if (e is Map<String, dynamic>) result.add(ArtistDto.fromJson(e));
      }
    }
    return result;
  }

  Future<List<AlbumDto>> getAlbumsByArtist(String artistId) async {
    final response = await _client.get(
      ApiConstants.getArtist,
      params: {'id': artistId},
    );
    final artist = response['artist'] as Map<String, dynamic>?;
    final albums = artist?['album'] as List<dynamic>? ?? const [];
    return albums
        .whereType<Map<String, dynamic>>()
        .map(AlbumDto.fromJson)
        .toList();
  }

  Future<AlbumDto> getAlbum(String albumId) async {
    final response = await _client.get(
      ApiConstants.getAlbum,
      params: {'id': albumId},
    );
    final album = response['album'];
    if (album is! Map<String, dynamic>) {
      throw const SubsonicException('Unexpected album payload', code: 0);
    }
    return AlbumDto.fromJson(album);
  }

  Future<List<AlbumDto>> getRecentAlbums({int size = 20, int offset = 0}) async {
    final response = await _client.get(
      ApiConstants.getAlbumList2,
      params: {'type': 'newest', 'size': size, 'offset': offset},
    );
    final list = response['albumList2'] as Map<String, dynamic>?;
    final albums = list?['album'] as List<dynamic>? ?? const [];
    return albums
        .whereType<Map<String, dynamic>>()
        .map(AlbumDto.fromJson)
        .toList();
  }

  Future<List<AlbumDto>> getAllAlbums({int size = 500, int offset = 0}) async {
    final response = await _client.get(
      ApiConstants.getAlbumList2,
      params: {'type': 'alphabeticalByName', 'size': size, 'offset': offset},
    );
    final list = response['albumList2'] as Map<String, dynamic>?;
    final albums = list?['album'] as List<dynamic>? ?? const [];
    return albums
        .whereType<Map<String, dynamic>>()
        .map(AlbumDto.fromJson)
        .toList();
  }

  Future<List<PlaylistDto>> getPlaylists() async {
    final response = await _client.get(ApiConstants.getPlaylists);
    final playlists = response['playlists'] as Map<String, dynamic>?;
    final list = playlists?['playlist'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(PlaylistDto.fromJson)
        .toList();
  }

  Future<PlaylistDto> getPlaylist(String playlistId) async {
    final response = await _client.get(
      ApiConstants.getPlaylist,
      params: {'id': playlistId},
    );
    final playlist = response['playlist'];
    if (playlist is! Map<String, dynamic>) {
      throw const SubsonicException('Unexpected playlist payload', code: 0);
    }
    return PlaylistDto.fromJson(playlist);
  }

  Future<
      ({
        List<ArtistDto> artists,
        List<AlbumDto> albums,
        List<SongDto> songs,
      })> searchAll(String query) async {
    final response = await _client.get(
      ApiConstants.search3,
      params: {
        'query': query,
        'artistCount': 10,
        'albumCount': 10,
        'songCount': 30,
      },
    );
    final results = response['searchResult3'] as Map<String, dynamic>?;
    final artistList = results?['artist'] as List<dynamic>? ?? const [];
    final albumList = results?['album'] as List<dynamic>? ?? const [];
    final songList = results?['song'] as List<dynamic>? ?? const [];
    return (
      artists: artistList
          .whereType<Map<String, dynamic>>()
          .map(ArtistDto.fromJson)
          .toList(),
      albums: albumList
          .whereType<Map<String, dynamic>>()
          .map(AlbumDto.fromJson)
          .toList(),
      songs: songList
          .whereType<Map<String, dynamic>>()
          .map(SongDto.fromJson)
          .toList(),
    );
  }

  Future<List<SongDto>> search(String query) async {
    final response = await _client.get(
      ApiConstants.search3,
      params: {
        'query': query,
        'artistCount': 0,
        'albumCount': 0,
        'songCount': 50,
      },
    );
    final results = response['searchResult3'] as Map<String, dynamic>?;
    final songs = results?['song'] as List<dynamic>? ?? const [];
    return songs
        .whereType<Map<String, dynamic>>()
        .map(SongDto.fromJson)
        .toList();
  }

  Future<List<SongDto>> getAllSongs({int count = 500, int offset = 0}) async {
    final response = await _client.get(
      ApiConstants.search3,
      params: {
        'query': '',
        'artistCount': 0,
        'albumCount': 0,
        'songCount': count,
        'songOffset': offset,
      },
    );
    final results = response['searchResult3'] as Map<String, dynamic>?;
    final songs = results?['song'] as List<dynamic>? ?? const [];
    return songs
        .whereType<Map<String, dynamic>>()
        .map(SongDto.fromJson)
        .toList();
  }

  // ── Playlist management ───────────────────────────────────────────────────

  Future<PlaylistDto> createPlaylist(String name, List<String> songIds) async {
    final params = <String, dynamic>{'name': name};
    if (songIds.isNotEmpty) params['songId'] = songIds;
    final response =
        await _client.get(ApiConstants.createPlaylist, params: params);
    final playlist = response['playlist'];
    if (playlist is! Map<String, dynamic>) {
      throw const SubsonicException('createPlaylist returned no playlist',
          code: 0);
    }
    return PlaylistDto.fromJson(playlist);
  }

  Future<void> updatePlaylist(
    String id, {
    String? name,
    List<String> songIdsToAdd = const [],
    List<int> songIndexesToRemove = const [],
  }) async {
    final params = <String, dynamic>{'playlistId': id};
    if (name != null) params['name'] = name;
    if (songIdsToAdd.isNotEmpty) params['songIdToAdd'] = songIdsToAdd;
    if (songIndexesToRemove.isNotEmpty) {
      params['songIndexToRemove'] = songIndexesToRemove;
    }
    await _client.get(ApiConstants.updatePlaylist, params: params);
  }

  Future<void> deletePlaylist(String id) async {
    await _client.get(ApiConstants.deletePlaylist, params: {'id': id});
  }

  // ── Genres ────────────────────────────────────────────────────────────────

  Future<List<Genre>> getGenres() async {
    final response = await _client.get(ApiConstants.getGenres);
    final genres = response['genres'] as Map<String, dynamic>?;
    final list = genres?['genre'] as List<dynamic>? ?? const [];
    final result = <Genre>[];
    for (final raw in list) {
      if (raw is! Map<String, dynamic>) continue;
      // Subsonic uses `value` for the name; sometimes seen as `name` in
      // older forks.
      final name = (raw['value'] ?? raw['name']) as String?;
      if (name == null || name.isEmpty) continue;
      result.add(Genre(
        name: name,
        songCount: (raw['songCount'] as int?) ?? 0,
        albumCount: (raw['albumCount'] as int?) ?? 0,
      ));
    }
    return result;
  }

  Future<List<AlbumDto>> getAlbumsByGenre(String genre,
      {int size = 500, int offset = 0}) async {
    final response = await _client.get(
      ApiConstants.getAlbumList2,
      params: {
        'type': 'byGenre',
        'genre': genre,
        'size': size,
        'offset': offset,
      },
    );
    final list = response['albumList2'] as Map<String, dynamic>?;
    final albums = list?['album'] as List<dynamic>? ?? const [];
    return albums
        .whereType<Map<String, dynamic>>()
        .map(AlbumDto.fromJson)
        .toList();
  }

  // ── Lyrics ────────────────────────────────────────────────────────────────

  /// Fetches lyrics for [songId]. Returns null when the server has none.
  /// Handles both the modern structured response (with synced timestamps)
  /// and older Subsonic forks that return a flat newline-joined string.
  Future<Lyrics?> getLyrics(String songId) async {
    final response =
        await _client.get(ApiConstants.getLyricsBySongId, params: {'id': songId});

    final list = response['lyricsList'] as Map<String, dynamic>?;
    final structured = list?['structuredLyrics'] as List<dynamic>?;
    if (structured != null && structured.isNotEmpty) {
      final first = structured.first as Map<String, dynamic>;
      final lineList = first['line'] as List<dynamic>? ?? const [];
      final synced = first['synced'] == true;
      final lines = <LyricsLine>[];
      for (final raw in lineList) {
        if (raw is! Map<String, dynamic>) continue;
        final value = raw['value'];
        if (value is! String) continue;
        final start = raw['start'];
        lines.add(LyricsLine(
          text: value,
          start: synced && start is int && start >= 0
              ? Duration(milliseconds: start)
              : null,
        ));
      }
      if (lines.isEmpty) return null;
      return Lyrics(
        lines: lines,
        synced: synced,
        lang: first['lang'] as String?,
      );
    }

    // Legacy fallback: { "lyrics": { "value": "Line 1\nLine 2..." } }
    final legacy = response['lyrics'] as Map<String, dynamic>?;
    final flat = legacy?['value'] as String?;
    if (flat == null || flat.trim().isEmpty) return null;
    final lines = flat
        .split('\n')
        .map((l) => LyricsLine(text: l))
        .toList();
    return Lyrics(lines: lines, synced: false);
  }

  // ── Ratings ───────────────────────────────────────────────────────────────

  /// Sets the user rating for [id] (which can be a song, album, or artist).
  /// Rating is 1-5 stars; pass 0 to clear an existing rating.
  Future<void> setRating(String id, int rating) async {
    assert(rating >= 0 && rating <= 5, 'rating must be 0-5');
    await _client.get(ApiConstants.setRating, params: {
      'id': id,
      'rating': rating,
    });
  }

  // ── Scrobbling ────────────────────────────────────────────────────────────

  /// Sends a scrobble to Subsonic. The server forwards to Last.fm /
  /// ListenBrainz when configured. Two modes per the Subsonic spec:
  ///   - submission=false → "now playing" ping (track has just started).
  ///   - submission=true  → full scrobble (track has been played enough).
  Future<void> scrobble(String songId, {bool submission = true}) async {
    await _client.get(ApiConstants.scrobble, params: {
      'id': songId,
      'submission': submission,
    });
  }

  // ── Starring ──────────────────────────────────────────────────────────────

  Future<void> star(String id) async {
    await _client.get(ApiConstants.star, params: {'id': id});
  }

  Future<void> unstar(String id) async {
    await _client.get(ApiConstants.unstar, params: {'id': id});
  }

  Future<Set<String>> getStarredSongIds() async {
    final response = await _client.get(ApiConstants.getStarred2);
    final starred = response['starred2'] as Map<String, dynamic>?;
    final songs = starred?['song'] as List<dynamic>? ?? const [];
    final ids = <String>{};
    for (final e in songs) {
      if (e is Map<String, dynamic>) {
        final id = e['id'];
        if (id is String) ids.add(id);
      }
    }
    return ids;
  }

  Uri coverArtUri(String coverArtId, {int size = 256}) {
    final key = '$coverArtId|$size';
    return _coverArtUriCache[key] ??= _client
        .buildUri(ApiConstants.getCoverArt, {'id': coverArtId, 'size': size});
  }

  Uri streamUri(String songId) =>
      _client.buildUri(ApiConstants.stream, {'id': songId});

  /// URL used by the transfer engine. When [format] is null we hit
  /// `/rest/download` so the server delivers the file untouched. When a
  /// format is supplied we hit `/rest/stream`, which is the Subsonic spec's
  /// transcoding endpoint and accepts `maxBitRate` + `format` query params.
  Uri transferUri(String songId, {String? format, int? maxBitRate}) {
    if (format == null) {
      return _client.buildUri(ApiConstants.download, {'id': songId});
    }
    return _client.buildUri(ApiConstants.stream, {
      'id': songId,
      'format': format,
      if (maxBitRate != null && maxBitRate > 0) 'maxBitRate': maxBitRate,
    });
  }
}
