import 'package:dio/dio.dart';

import '../../../domain/models/lidarr_models.dart';

class LidarrClient {
  LidarrClient({required String baseUrl, required String apiKey})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
            headers: {'X-Api-Key': apiKey},
            // Without these, an unreachable or slow Lidarr leaves every
            // FutureProvider (artist list, discography, releases) hanging on
            // the OS TCP timeout — the UI shows a spinner that never resolves.
            // connectTimeout fast-fails an unreachable host; receiveTimeout is
            // generous because interactive indexer searches (searchReleases)
            // legitimately take up to a minute with many indexers.
            connectTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );

  final Dio _dio;

  /// Exposed for tests (swap the HTTP adapter / inspect interceptors).
  Dio get dio => _dio;

  /// Closes the underlying Dio instance. Called by the provider when this
  /// client is replaced (instance switch / sign-out) so the connection pool
  /// is released and in-flight requests are cancelled.
  void dispose() => _dio.close(force: true);

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
    int? metadataProfileId,
  }) async {
    // Lidarr rejects POST /artist without a metadataProfileId (> 0). Most users
    // never think about it, so default to the instance's first configured
    // profile when the caller doesn't specify one.
    final metaId = metadataProfileId ?? await _defaultMetadataProfileId();
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/v1/artist',
      data: {
        'foreignArtistId': mbid,
        'artistName': name,
        'monitored': true,
        'rootFolderPath': rootFolderPath,
        'qualityProfileId': qualityProfileId,
        'metadataProfileId': ?metaId,
        'addOptions': {'monitor': 'all', 'searchForMissingAlbums': false},
      },
    );
    return LidarrArtist.fromJson(resp.data!);
  }

  // Cached across adds within this client's lifetime — profiles don't change
  // mid-session and the client is rebuilt on instance/credential change.
  int? _cachedMetadataProfileId;

  /// First metadata profile id on the instance, used as a sensible default
  /// when adding an artist/album (Lidarr requires one). Returns null only when
  /// the instance somehow has none or the request fails.
  Future<int?> _defaultMetadataProfileId() async {
    if (_cachedMetadataProfileId != null) return _cachedMetadataProfileId;
    try {
      final resp = await _dio.get<List<dynamic>>('/api/v1/metadataprofile');
      for (final e in (resp.data ?? const [])) {
        if (e is Map<String, dynamic>) {
          final id = e['id'];
          if (id is int && id > 0) return _cachedMetadataProfileId = id;
        }
      }
    } catch (_) {
      // Non-fatal — the add attempt will surface any error to the user.
    }
    return null;
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
    // When the album's artist isn't in Lidarr yet it gets created here, and
    // Lidarr requires a metadataProfileId (> 0) for that. The lookup payload
    // usually carries 0, so fill in a real one.
    final existingMeta = artist['metadataProfileId'];
    if (existingMeta is! int || existingMeta <= 0) {
      final metaId = await _defaultMetadataProfileId();
      if (metaId != null) artist['metadataProfileId'] = metaId;
    }
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
