import 'package:dio/dio.dart';

import '../../../domain/models/lidarr_models.dart';

class LidarrClient {
  LidarrClient({required String baseUrl, required String apiKey})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
            headers: {'X-Api-Key': apiKey},
          ),
        );

  final Dio _dio;

  Future<bool> testConnection() async {
    final resp = await _dio.get<Map<String, dynamic>>('/api/v1/system/status');
    return resp.statusCode == 200;
  }

  Future<List<LidarrArtist>> getArtists() async {
    final resp = await _dio.get<List<dynamic>>('/api/v1/artist');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrArtist.fromJson)
        .toList();
  }

  Future<List<LidarrArtist>> lookupArtists(String term) async {
    final resp = await _dio.get<List<dynamic>>(
      '/api/v1/artist/lookup',
      queryParameters: {'term': term},
    );
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrArtist.fromJson)
        .toList();
  }

  Future<LidarrArtist> addArtist({
    required String mbid,
    required String name,
    required int rootFolderId,
    required String rootFolderPath,
    required int qualityProfileId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/v1/artist',
      data: {
        'foreignArtistId': mbid,
        'artistName': name,
        'monitored': true,
        'rootFolderPath': rootFolderPath,
        'qualityProfileId': qualityProfileId,
        'addOptions': {'monitor': 'all', 'searchForMissingAlbums': false},
      },
    );
    return LidarrArtist.fromJson(resp.data!);
  }

  Future<List<LidarrRootFolder>> getRootFolders() async {
    final resp = await _dio.get<List<dynamic>>('/api/v1/rootfolder');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrRootFolder.fromJson)
        .toList();
  }

  Future<List<LidarrQualityProfile>> getQualityProfiles() async {
    final resp = await _dio.get<List<dynamic>>('/api/v1/qualityprofile');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrQualityProfile.fromJson)
        .toList();
  }

  Future<List<LidarrAlbumLookup>> lookupAlbums(String term) async {
    final resp = await _dio.get<List<dynamic>>(
      '/api/v1/album/lookup',
      queryParameters: {'term': term},
    );
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrAlbumLookup.fromJson)
        .toList();
  }

  /// Adds an album from a lookup result. When the album's artist isn't yet
  /// in Lidarr, the nested artist payload tells Lidarr to create the
  /// artist with the supplied root folder + quality profile in the same
  /// call. [searchOnAdd] triggers an immediate release grab.
  ///
  /// Returns the newly-created album's Lidarr id (or 0 if the response
  /// didn't include one), so callers that want to open the interactive
  /// release picker right after adding can do so without a follow-up
  /// lookup round trip.
  Future<int> addAlbum({
    required LidarrAlbumLookup album,
    required String rootFolderPath,
    required int qualityProfileId,
    bool searchOnAdd = true,
  }) async {
    final payload = Map<String, dynamic>.from(album.raw);
    payload['monitored'] = true;
    payload['addOptions'] = {
      'addType': 'automatic',
      'searchForNewAlbum': searchOnAdd,
    };
    final artist = Map<String, dynamic>.from(
        (payload['artist'] as Map<String, dynamic>?) ?? const {});
    artist['monitored'] = true;
    artist['qualityProfileId'] = qualityProfileId;
    artist['rootFolderPath'] = rootFolderPath;
    artist['addOptions'] = {
      'monitor': 'specificAlbum',
      'searchForMissingAlbums': false,
    };
    payload['artist'] = artist;

    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/v1/album',
      data: payload,
    );
    return (resp.data?['id'] as int?) ?? 0;
  }

  Future<List<LidarrAlbum>> getAlbumsByArtist(int artistId) async {
    final resp = await _dio.get<List<dynamic>>(
      '/api/v1/album',
      queryParameters: {'artistId': artistId},
    );
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrAlbum.fromJson)
        .toList();
  }

  Future<void> triggerArtistSearch(int artistId) async {
    await _dio.post<void>(
      '/api/v1/command',
      data: {'name': 'ArtistSearch', 'artistId': artistId},
    );
  }

  Future<void> triggerAlbumSearch(int albumId) async {
    await _dio.post<void>(
      '/api/v1/command',
      data: {'name': 'AlbumSearch', 'albumIds': [albumId]},
    );
  }

  Future<List<LidarrRelease>> searchReleases(int albumId) async {
    final resp = await _dio.get<List<dynamic>>(
      '/api/v1/release',
      queryParameters: {'albumId': albumId},
    );
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrRelease.fromJson)
        .toList();
  }

  Future<void> grabRelease(Map<String, dynamic> releaseJson) async {
    await _dio.post<void>('/api/v1/release', data: releaseJson);
  }

  Future<List<LidarrCustomFilter>> getCustomFilters() async {
    final resp = await _dio.get<List<dynamic>>('/api/v1/customfilter');
    return (resp.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(LidarrCustomFilter.fromJson)
        .where((f) => f.label.isNotEmpty)
        .toList();
  }
}
