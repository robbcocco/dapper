import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/data/datasources/remote/lidarr_client.dart';

/// Routes a couple of Lidarr endpoints to canned JSON so the add flow can run
/// without a network.
class _LidarrFakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) async {
    if (options.path.contains('/metadataprofile')) {
      return ResponseBody.fromString(
        jsonEncode([
          {'id': 3, 'name': 'Standard'},
          {'id': 4, 'name': 'None'},
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (options.method == 'POST' && options.path.contains('/artist')) {
      return ResponseBody.fromString(
        jsonEncode({
          'id': 10,
          'foreignArtistId': 'mbid-x',
          'artistName': 'Test Artist',
          'monitored': true,
          'qualityProfileId': 2,
        }),
        201,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('addArtist includes a resolved metadataProfileId (Lidarr requires it)',
      () async {
    final client = LidarrClient(baseUrl: 'https://lidarr.test', apiKey: 'k');
    Map<String, dynamic>? postedArtist;
    client.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'POST' && o.path.contains('/artist')) {
        postedArtist = Map<String, dynamic>.from(o.data as Map);
      }
      h.next(o);
    }));
    client.dio.httpClientAdapter = _LidarrFakeAdapter();

    final result = await client.addArtist(
      mbid: 'mbid-x',
      name: 'Test Artist',
      rootFolderId: 1,
      rootFolderPath: '/music',
      qualityProfileId: 2,
    );

    expect(result.id, 10);
    expect(postedArtist, isNotNull);
    // The key fix: the POST body must carry a metadataProfileId > 0, taken from
    // the instance's first metadata profile (id 3 above).
    expect(postedArtist!['metadataProfileId'], 3);
    expect(postedArtist!['qualityProfileId'], 2);
    expect(postedArtist!['rootFolderPath'], '/music');
    client.dispose();
  });

  test('an explicit metadataProfileId is respected over the default', () async {
    final client = LidarrClient(baseUrl: 'https://lidarr.test', apiKey: 'k');
    Map<String, dynamic>? postedArtist;
    client.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'POST' && o.path.contains('/artist')) {
        postedArtist = Map<String, dynamic>.from(o.data as Map);
      }
      h.next(o);
    }));
    client.dio.httpClientAdapter = _LidarrFakeAdapter();

    await client.addArtist(
      mbid: 'mbid-x',
      name: 'Test Artist',
      rootFolderId: 1,
      rootFolderPath: '/music',
      qualityProfileId: 2,
      metadataProfileId: 99,
    );

    expect(postedArtist!['metadataProfileId'], 99);
    client.dispose();
  });
}
