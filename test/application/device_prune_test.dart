import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/application/device/device_prune.dart';
import 'package:dapper/application/transfer/device_manifest.dart';
import 'package:dapper/domain/models/device_settings.dart';
import 'package:dapper/domain/models/song.dart';
import 'package:dapper/domain/repositories/library_repository.dart';

/// Minimal LibraryRepository whose only real method is getAllSongs; everything
/// else throws via noSuchMethod (prune never touches them).
class _FakeRepo implements LibraryRepository {
  _FakeRepo(this.songs);
  final List<Song> songs;

  @override
  Future<List<Song>> getAllSongs({int count = 500, int offset = 0}) async =>
      offset >= songs.length ? [] : songs.skip(offset).take(count).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  setUp(() {
    clearDeviceCaches();
    tmp = Directory.systemTemp.createTempSync('prune_test_');
  });
  tearDown(() {
    clearDeviceCaches();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('title fallback never deletes a kept song whose name contains the '
      'orphan title', () async {
    final albumDir = Directory(p.join(tmp.path, 'Artist', 'Album'))
      ..createSync(recursive: true);
    final orphanFile = File(p.join(albumDir.path, 'Live.flac'))
      ..writeAsStringSync('x');
    final keptFile = File(p.join(albumDir.path, 'Live at Wembley.flac'))
      ..writeAsStringSync('xy');

    // Legacy manifest: no `filename` recorded, so prune falls back to title
    // matching. "Live" (orphan) must not delete "Live at Wembley" (kept).
    writeManifest(
      albumDir.path,
      const AlbumManifest(songs: [
        ManifestSong(id: 'orphan', title: 'Live'),
        ManifestSong(id: 'keep', title: 'Live at Wembley'),
      ], expectedSongCount: 2),
    );

    final settings = DeviceSettings(
      devicePath: tmp.path,
      folderStructure: FolderStructure.artistAlbum,
    );
    // Library still has the kept song; the orphan is gone.
    final repo = _FakeRepo([const Song(id: 'keep', title: 'Live at Wembley')]);

    final result = await pruneDevice(settings, repo);

    expect(keptFile.existsSync(), isTrue, reason: 'kept file must survive');
    expect(orphanFile.existsSync(), isFalse, reason: 'orphan file removed');
    expect(result.songsRemoved, 1);

    // Manifest keeps only the surviving song and preserves expectedSongCount.
    clearDeviceCaches();
    final after = readManifest(albumDir.path)!;
    expect(after.songs.map((s) => s.id), ['keep']);
    expect(after.expectedSongCount, 2);
  });
}
