import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../domain/models/musicbrainz_result.dart';

class MusicBrainzClient {
  static final _mbDio = Dio(BaseOptions(
    baseUrl: 'https://musicbrainz.org',
    headers: {
      'User-Agent': 'Dapper/1.0 (github.com/dapper-music)',
      'Accept': 'application/json',
    },
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static final _caDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Future<List<MbReleaseGroup>> searchReleaseGroups(
    String albumName,
    String? artistName,
  ) async {
    final parts = ['release:"${_esc(albumName)}"'];
    if (artistName != null && artistName.isNotEmpty) {
      parts.add('artist:"${_esc(artistName)}"');
    }
    return _queryReleaseGroups(parts.join(' AND '));
  }

  Future<List<MbReleaseGroup>> searchByText(String query) =>
      _queryReleaseGroups(query);

  Future<List<MbReleaseGroup>> _queryReleaseGroups(String query) async {
    try {
      final resp = await _mbDio.get<Map<String, dynamic>>(
        '/ws/2/release-group',
        queryParameters: {
          'query': query,
          'fmt': 'json',
          'limit': 6,
        },
      );
      final groups = resp.data!['release-groups'] as List<dynamic>? ?? [];
      return groups
          .map((e) => MbReleaseGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      dev.log('MusicBrainzClient: release-group query failed — $e');
      return [];
    }
  }

  Future<Uint8List?> fetchCoverArt(String mbid) async {
    try {
      final resp = await _caDio.get<List<int>>(
        'https://coverartarchive.org/release-group/$mbid/front',
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );
      if (resp.data == null) return null;
      return Uint8List.fromList(resp.data!);
    } catch (e) {
      dev.log('MusicBrainzClient: cover-art fetch for $mbid failed — $e');
      return null;
    }
  }

  String _esc(String s) => s
      .replaceAll('"', '\\"')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');
}
