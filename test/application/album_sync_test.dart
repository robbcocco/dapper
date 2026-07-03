import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/application/device/album_sync_provider.dart';
import 'package:dapper/application/transfer/transfer_path_resolver.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('albumsync_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory album(String artist, String name) =>
      Directory(p.join(root.path, artist, name))..createSync(recursive: true);

  void writeManifest(Directory dir, List<String> ids, {int? expected}) {
    File(p.join(dir.path, '.dapper.json')).writeAsStringSync(jsonEncode({
      'version': 1,
      'expectedSongCount': ?expected,
      'songs': [for (final id in ids) {'id': id, 'title': id}],
    }));
  }

  test('manifest with expectedSongCount → full when complete', () async {
    final dir = album('Artist', 'Full Album');
    writeManifest(dir, ['a', 'b', 'c'], expected: 3);
    final map = await scanAlbumFolders(root.path, const {});
    expect(map[dir.path], AlbumSyncStatus.full);
  });

  test('manifest with fewer than expected → partial', () async {
    final dir = album('Artist', 'Partial Album');
    writeManifest(dir, ['a', 'b'], expected: 5);
    final map = await scanAlbumFolders(root.path, const {});
    expect(map[dir.path], AlbumSyncStatus.partial);
  });

  test('manifest without expectedSongCount falls back to library count',
      () async {
    final dir = album('Artist', 'Legacy Album');
    writeManifest(dir, ['a', 'b', 'c']); // no expectedSongCount
    // Library says the album has 3 songs → full.
    final map = await scanAlbumFolders(root.path, {dir.path: 3});
    expect(map[dir.path], AlbumSyncStatus.full);
    // With a higher library count it's partial.
    final map2 = await scanAlbumFolders(root.path, {dir.path: 6});
    expect(map2[dir.path], AlbumSyncStatus.partial);
  });

  test('no-manifest folder counts audio files against the library count',
      () async {
    final dir = album('Artist', 'Externally Managed');
    File(p.join(dir.path, '01 One.flac')).writeAsStringSync('x');
    File(p.join(dir.path, '02 Two.flac')).writeAsStringSync('x');
    final map = await scanAlbumFolders(root.path, {dir.path: 2});
    expect(map[dir.path], AlbumSyncStatus.full);
  });

  test('empty album folder is absent (not in the map)', () async {
    final dir = album('Artist', 'Empty');
    final map = await scanAlbumFolders(root.path, const {});
    expect(map.containsKey(dir.path), isFalse);
  });

  test('missing root yields an empty map without throwing', () async {
    final map = await scanAlbumFolders(
        p.join(root.path, 'does-not-exist'), const {});
    expect(map, isEmpty);
  });
}
