import '../../../core/constants/api_constants.dart';
import '../../../core/errors/app_exception.dart';
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

  Uri downloadUri(String songId) =>
      _client.buildUri(ApiConstants.download, {'id': songId});
}
