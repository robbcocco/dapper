import 'package:dio/dio.dart';

import '../../../domain/models/spotify_track.dart';
import 'spotify_scraper.dart';

/// Public Tidal playlist scraper.
///
/// Tidal's web app is a JS shell — the HTML doesn't carry track data, so
/// we instead hit `api.tidal.com/v1` with a long-lived web-client token
/// that the Tidal web app itself ships in its JS bundle. The token below
/// has been used unauthenticated by a number of community scrapers for
/// years. If Tidal rotates it we surface the failure as a normal
/// [SpotifyScrapeException].
class TidalScraper implements PlaylistScraper {
  TidalScraper({Dio? dio, String? token, String? countryCode})
      : _token = token ?? _kWebToken,
        _countryCode = countryCode ?? 'US',
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.tidal.com/v1',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  // Read-only web-client token bundled in the Tidal web app. Used by
  // anonymous /listen.tidal.com requests for embedded previews.
  static const _kWebToken = 'CzET4vdadNUFQ5JU';

  final Dio _dio;
  final String _token;
  final String _countryCode;

  /// Accepts a bare UUID, a `tidal:playlist:<uuid>` URI, or any
  /// `tidal.com/.../playlist/<uuid>` URL (including the embed and listen
  /// subdomains). Returns null when nothing playlist-shaped is found.
  static String? parsePlaylistId(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final uuid = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
    if (RegExp('^${uuid.pattern}\$').hasMatch(s)) return s.toLowerCase();
    final uri = RegExp(r'tidal:playlist:(' + uuid.pattern + r')')
        .firstMatch(s);
    if (uri != null) return uri.group(1)!.toLowerCase();
    final url = RegExp(
            r'tidal\.com/(?:[a-z\-]+/)?(?:browse/)?playlist/(' +
                uuid.pattern +
                r')')
        .firstMatch(s);
    if (url != null) return url.group(1)!.toLowerCase();
    return null;
  }

  @override
  Future<SpotifyPlaylistData> fetchPlaylist(String idOrUrl) async {
    final id = parsePlaylistId(idOrUrl);
    if (id == null) {
      throw const SpotifyScrapeException(
          'Could not find a Tidal playlist ID in that text.');
    }

    final Map<String, dynamic> meta;
    final List<dynamic> items;
    try {
      final metaResp = await _dio.get<Map<String, dynamic>>(
        '/playlists/$id',
        queryParameters: {'countryCode': _countryCode},
        options: Options(headers: {'X-Tidal-Token': _token}),
      );
      meta = metaResp.data ?? const {};
      // /items is paginated; 100 is Tidal's max per page. Walk pages so big
      // playlists come through in full.
      items = await _fetchAllItems(id);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const SpotifyScrapeException(
            'Tidal denied the request — the public token may have been '
            'rotated. Try updating Dapper.');
      }
      if (status == 404) {
        throw const SpotifyScrapeException(
            'Tidal playlist not found. Make sure the link is public.');
      }
      throw SpotifyScrapeException(
          'Tidal request failed (${status ?? e.type.name}).');
    }

    if (items.isEmpty) {
      throw const SpotifyScrapeException(
          'Tidal returned no tracks for this playlist.');
    }

    final name = (meta['title'] as String?)?.trim().isNotEmpty == true
        ? meta['title'] as String
        : 'Tidal Playlist';

    final tracks = <SpotifyTrack>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final item = raw['item'] as Map<String, dynamic>?;
      if (item == null) continue;
      // Skip videos / mixes — only tracks have a usable title+artist pair.
      final type = (raw['type'] as String?)?.toLowerCase();
      if (type != null && type != 'track') continue;
      final title = (item['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      final artist = _joinArtists(item['artists']);
      final album = (item['album'] as Map<String, dynamic>?)?['title']
          as String?;
      final durSec = item['duration'] as int?;
      tracks.add(SpotifyTrack(
        title: title,
        artist: artist,
        album: album,
        durationMs: durSec != null ? durSec * 1000 : null,
      ));
    }

    if (tracks.isEmpty) {
      throw const SpotifyScrapeException(
          'Could not read any tracks from the Tidal playlist.');
    }

    final advertised = meta['numberOfTracks'] as int? ?? tracks.length;
    return SpotifyPlaylistData(
      name: name,
      tracks: tracks,
      truncated: tracks.length < advertised,
      provider: PlaylistProvider.tidal,
    );
  }

  Future<List<dynamic>> _fetchAllItems(String playlistId) async {
    const pageSize = 100;
    final out = <dynamic>[];
    var offset = 0;
    while (true) {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/playlists/$playlistId/items',
        queryParameters: {
          'countryCode': _countryCode,
          'limit': pageSize,
          'offset': offset,
        },
        options: Options(headers: {'X-Tidal-Token': _token}),
      );
      final body = resp.data ?? const {};
      final page = body['items'] as List<dynamic>? ?? const [];
      out.addAll(page);
      final total = body['totalNumberOfItems'] as int? ?? out.length;
      offset += page.length;
      if (page.isEmpty || offset >= total) break;
      // Hard cap so a misbehaving response can't spin forever.
      if (offset > 5000) break;
    }
    return out;
  }

  String _joinArtists(dynamic raw) {
    if (raw is! List) return '';
    final names = <String>[];
    for (final a in raw) {
      if (a is Map<String, dynamic>) {
        final n = a['name'] as String?;
        if (n != null && n.trim().isNotEmpty) names.add(n.trim());
      }
    }
    return names.join(', ');
  }
}
