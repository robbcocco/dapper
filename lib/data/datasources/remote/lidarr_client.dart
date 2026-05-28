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
