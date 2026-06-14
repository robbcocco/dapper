import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import '../../../domain/models/spotify_track.dart';
import 'tidal_scraper.dart';

/// Abstract scraper interface — one impl per upstream playlist provider.
/// Implementations throw [SpotifyScrapeException] (kept under the legacy
/// name) for any user-actionable parse / network failure.
abstract class PlaylistScraper {
  Future<SpotifyPlaylistData> fetchPlaylist(String idOrUrl);

  /// Returns the first scraper that recognises [input] (URL or bare id),
  /// or null when no provider matches.
  static PlaylistScraper? detect(String input) {
    if (SpotifyScraper.parsePlaylistId(input) != null) {
      return SpotifyScraper();
    }
    if (TidalScraper.parsePlaylistId(input) != null) {
      return TidalScraper();
    }
    return null;
  }
}

/// Scrapes a public Spotify playlist via the unauthenticated embed page.
///
/// The embed page (`open.spotify.com/embed/playlist/{id}`) returns server-
/// rendered HTML with a `<script id="__NEXT_DATA__">` blob containing the
/// playlist metadata + track list. There is no documented API contract, so
/// the parser tolerates several shapes and any change on Spotify's side
/// surfaces as a [SpotifyScrapeException] rather than a silent failure.
class SpotifyScraper implements PlaylistScraper {
  SpotifyScraper({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              followRedirects: true,
              headers: {
                // The embed page short-circuits to a stub when the UA looks
                // like a bot. A normal-browser UA gets the full payload.
                'User-Agent':
                    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                        'AppleWebKit/537.36 (KHTML, like Gecko) '
                        'Chrome/124.0 Safari/537.36',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            ));

  final Dio _dio;

  /// Extracts the playlist ID from either a full Spotify URL or a raw ID.
  /// Returns null if nothing usable is found.
  static String? parsePlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    // Bare ID: 22 chars of base62.
    final bareId = RegExp(r'^[A-Za-z0-9]{22}$');
    if (bareId.hasMatch(trimmed)) return trimmed;
    // spotify:playlist:<id>
    final uri =
        RegExp(r'spotify:playlist:([A-Za-z0-9]{22})').firstMatch(trimmed);
    if (uri != null) return uri.group(1);
    // open.spotify.com/playlist/<id> (with optional locale prefix + query).
    final url =
        RegExp(r'open\.spotify\.com/(?:[a-z\-]+/)?(?:embed/)?playlist/([A-Za-z0-9]{22})')
            .firstMatch(trimmed);
    if (url != null) return url.group(1);
    return null;
  }

  @override
  Future<SpotifyPlaylistData> fetchPlaylist(String idOrUrl) async {
    final id = parsePlaylistId(idOrUrl);
    if (id == null) {
      throw const SpotifyScrapeException(
          'Could not find a Spotify playlist ID in that text.');
    }

    final Response<String> resp;
    try {
      resp = await _dio.get<String>(
        'https://open.spotify.com/embed/playlist/$id',
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw SpotifyScrapeException(
          'Spotify request failed (${e.response?.statusCode ?? e.type.name}).');
    }

    final html = resp.data;
    if (html == null || html.isEmpty) {
      throw const SpotifyScrapeException('Empty response from Spotify.');
    }

    return _parse(html);
  }

  SpotifyPlaylistData _parse(String html) {
    final match = RegExp(
            r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>',
            dotAll: true)
        .firstMatch(html);
    if (match == null) {
      throw const SpotifyScrapeException(
          'Spotify changed its embed format — could not find playlist data. '
          'Try again later or paste a different playlist.');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(match.group(1)!);
    } catch (e) {
      throw const SpotifyScrapeException(
          'Spotify returned malformed playlist data.');
    }

    final entity = _navigateToEntity(decoded);
    if (entity == null) {
      dev.log('SpotifyScraper: entity not found in payload.');
      throw const SpotifyScrapeException(
          'Spotify did not include any track data for this playlist. '
          'It may be private, region-locked, or removed.');
    }

    final name = (entity['name'] ?? entity['title'] ?? 'Spotify Playlist')
        .toString();

    final rawTracks = _extractTrackList(entity);
    if (rawTracks.isEmpty) {
      throw const SpotifyScrapeException(
          'Playlist is empty (or its tracks are not visible without login).');
    }

    final tracks = <SpotifyTrack>[];
    for (final raw in rawTracks) {
      if (raw is! Map<String, dynamic>) continue;
      final title = _pickString(raw, ['title', 'name']);
      if (title == null || title.isEmpty) continue;
      final artist = _extractArtist(raw);
      tracks.add(SpotifyTrack(
        title: title,
        artist: artist,
        durationMs: _pickInt(raw, ['duration', 'durationMs', 'duration_ms']),
      ));
    }

    if (tracks.isEmpty) {
      throw const SpotifyScrapeException(
          'Could not read any tracks from the playlist.');
    }

    // Spotify embed caps at 100 — flag so UI can warn the user.
    final advertisedCount = _pickInt(entity, ['trackCount']) ?? tracks.length;
    final truncated = tracks.length < advertisedCount;

    return SpotifyPlaylistData(
      name: name,
      tracks: tracks,
      truncated: truncated,
      provider: PlaylistProvider.spotify,
    );
  }

  Map<String, dynamic>? _navigateToEntity(dynamic root) {
    if (root is! Map<String, dynamic>) return null;
    // Walk a couple of known paths; fall back to a depth-limited search for
    // any nested object that looks like the entity (has trackList or
    // audioItems).
    final paths = <List<String>>[
      ['props', 'pageProps', 'state', 'data', 'entity'],
      ['props', 'pageProps', 'initialState', 'data', 'entity'],
      ['props', 'pageProps', 'entity'],
    ];
    for (final path in paths) {
      final hit = _walk(root, path);
      if (hit is Map<String, dynamic> && _looksLikeEntity(hit)) return hit;
    }
    return _searchEntity(root, 0);
  }

  dynamic _walk(dynamic node, List<String> path) {
    var cur = node;
    for (final key in path) {
      if (cur is! Map<String, dynamic>) return null;
      cur = cur[key];
      if (cur == null) return null;
    }
    return cur;
  }

  bool _looksLikeEntity(Map<String, dynamic> m) =>
      m.containsKey('trackList') ||
      m.containsKey('audioItems') ||
      m.containsKey('tracks');

  Map<String, dynamic>? _searchEntity(dynamic node, int depth) {
    if (depth > 6) return null;
    if (node is Map<String, dynamic>) {
      if (_looksLikeEntity(node)) return node;
      for (final v in node.values) {
        final hit = _searchEntity(v, depth + 1);
        if (hit != null) return hit;
      }
    } else if (node is List) {
      for (final v in node) {
        final hit = _searchEntity(v, depth + 1);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  List<dynamic> _extractTrackList(Map<String, dynamic> entity) {
    final tracks = entity['trackList'] ?? entity['audioItems'];
    if (tracks is List) return tracks;
    final maybe = entity['tracks'];
    if (maybe is List) return maybe;
    if (maybe is Map<String, dynamic>) {
      final items = maybe['items'];
      if (items is List) return items;
    }
    return const [];
  }

  String _extractArtist(Map<String, dynamic> raw) {
    // Embed typically uses `subtitle` for a comma-joined artist string.
    final subtitle = _pickString(raw, ['subtitle', 'artist']);
    if (subtitle != null && subtitle.isNotEmpty) return subtitle;
    // Structured shape: artists: [{name: ...}, ...]
    final artists = raw['artists'];
    if (artists is List) {
      final names = <String>[];
      for (final a in artists) {
        if (a is Map<String, dynamic>) {
          final n = _pickString(a, ['name']);
          if (n != null) names.add(n);
        } else if (a is String) {
          names.add(a);
        }
      }
      if (names.isNotEmpty) return names.join(', ');
    }
    return '';
  }

  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  int? _pickInt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v);
        if (n != null) return n;
      }
    }
    return null;
  }
}

class SpotifyScrapeException implements Exception {
  const SpotifyScrapeException(this.message);
  final String message;

  @override
  String toString() => message;
}
