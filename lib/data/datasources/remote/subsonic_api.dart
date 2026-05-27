import '../../../core/constants/api_constants.dart';
import '../../datasources/remote/dto/album_dto.dart';
import '../../datasources/remote/dto/artist_dto.dart';
import '../../datasources/remote/dto/playlist_dto.dart';
import '../../datasources/remote/dto/song_dto.dart';
import 'subsonic_client.dart';

class SubsonicApi {
  SubsonicApi(this._client);

  final SubsonicClient _client;

  Future<bool> ping() async {
    final response = await _client.get(ApiConstants.ping);
    return response['status'] == 'ok';
  }

  Future<List<ArtistDto>> getArtists() async {
    final response = await _client.get(ApiConstants.getArtists);
    final artists = response['artists'] as Map<String, dynamic>;
    final indices = artists['index'] as List<dynamic>? ?? [];
    final result = <ArtistDto>[];
    for (final index in indices) {
      final entries = (index as Map<String, dynamic>)['artist'] as List<dynamic>? ?? [];
      result.addAll(
        entries.map((e) => ArtistDto.fromJson(e as Map<String, dynamic>)),
      );
    }
    return result;
  }

  Future<List<AlbumDto>> getAlbumsByArtist(String artistId) async {
    final response = await _client.get(
      ApiConstants.getArtist,
      params: {'id': artistId},
    );
    final artist = response['artist'] as Map<String, dynamic>;
    final albums = artist['album'] as List<dynamic>? ?? [];
    return albums
        .map((e) => AlbumDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AlbumDto> getAlbum(String albumId) async {
    final response = await _client.get(
      ApiConstants.getAlbum,
      params: {'id': albumId},
    );
    return AlbumDto.fromJson(response['album'] as Map<String, dynamic>);
  }

  Future<List<AlbumDto>> getRecentAlbums({int size = 20, int offset = 0}) async {
    final response = await _client.get(
      ApiConstants.getAlbumList2,
      params: {'type': 'newest', 'size': size, 'offset': offset},
    );
    final list = response['albumList2'] as Map<String, dynamic>;
    final albums = list['album'] as List<dynamic>? ?? [];
    return albums
        .map((e) => AlbumDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AlbumDto>> getAllAlbums({int size = 500, int offset = 0}) async {
    final response = await _client.get(
      ApiConstants.getAlbumList2,
      params: {'type': 'alphabeticalByName', 'size': size, 'offset': offset},
    );
    final list = response['albumList2'] as Map<String, dynamic>;
    final albums = list['album'] as List<dynamic>? ?? [];
    return albums
        .map((e) => AlbumDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PlaylistDto>> getPlaylists() async {
    final response = await _client.get(ApiConstants.getPlaylists);
    final playlists = response['playlists'] as Map<String, dynamic>;
    final list = playlists['playlist'] as List<dynamic>? ?? [];
    return list
        .map((e) => PlaylistDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlaylistDto> getPlaylist(String playlistId) async {
    final response = await _client.get(
      ApiConstants.getPlaylist,
      params: {'id': playlistId},
    );
    return PlaylistDto.fromJson(response['playlist'] as Map<String, dynamic>);
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
    final results = response['searchResult3'] as Map<String, dynamic>;
    final artistList = results['artist'] as List<dynamic>? ?? [];
    final albumList = results['album'] as List<dynamic>? ?? [];
    final songList = results['song'] as List<dynamic>? ?? [];
    return (
      artists: artistList
          .map((e) => ArtistDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      albums: albumList
          .map((e) => AlbumDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      songs: songList
          .map((e) => SongDto.fromJson(e as Map<String, dynamic>))
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
    final results = response['searchResult3'] as Map<String, dynamic>;
    final songs = results['song'] as List<dynamic>? ?? [];
    return songs
        .map((e) => SongDto.fromJson(e as Map<String, dynamic>))
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
    final results = response['searchResult3'] as Map<String, dynamic>;
    final songs = results['song'] as List<dynamic>? ?? [];
    return songs.map((e) => SongDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ── Playlist management ───────────────────────────────────────────────────

  Future<PlaylistDto> createPlaylist(String name, List<String> songIds) async {
    final params = <String, dynamic>{'name': name};
    if (songIds.isNotEmpty) params['songId'] = songIds;
    final response =
        await _client.get(ApiConstants.createPlaylist, params: params);
    return PlaylistDto.fromJson(response['playlist'] as Map<String, dynamic>);
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
    final starred = response['starred2'] as Map<String, dynamic>? ?? {};
    final songs = starred['song'] as List<dynamic>? ?? [];
    return songs
        .map((e) => (e as Map<String, dynamic>)['id'] as String)
        .toSet();
  }

  Uri coverArtUri(String coverArtId, {int size = 256}) =>
      _client.buildUri(ApiConstants.getCoverArt, {'id': coverArtId, 'size': size});

  Uri streamUri(String songId) =>
      _client.buildUri(ApiConstants.stream, {'id': songId});

  Uri downloadUri(String songId) =>
      _client.buildUri(ApiConstants.download, {'id': songId});
}
