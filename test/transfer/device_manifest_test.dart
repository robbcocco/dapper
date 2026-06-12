import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/application/transfer/device_manifest.dart';
import 'package:dapper/domain/models/song.dart';
import 'package:dapper/platform/local_device_fs.dart';

Song _song({String id = 's1', String title = 'Title'}) =>
    Song(id: id, title: title, album: 'Alb', artist: 'Art');

void main() {
  late Directory tmp;
  late LocalDeviceFs fs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dapper_manifest_test_');
    fs = LocalDeviceFs(tmp.path, maxConcurrentTransfers: 1);
    // Each test starts with a clean in-memory cache so we never inherit
    // state from another test's run.
    clearDeviceCaches();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('isAudioFile', () {
    test('matches common audio extensions case-insensitively', () {
      expect(isAudioFile(File('/x/foo.mp3')), isTrue);
      expect(isAudioFile(File('/x/foo.MP3')), isTrue);
      expect(isAudioFile(File('/x/foo.flac')), isTrue);
      expect(isAudioFile(File('/x/foo.opus')), isTrue);
    });

    test('rejects AppleDouble sidecars', () {
      // The OS-written ._foo.mp3 starts with ._ — must not be classified as
      // audio even though its extension is .mp3.
      expect(isAudioFile(File('/x/._foo.mp3')), isFalse);
    });

    test('rejects non-audio extensions', () {
      expect(isAudioFile(File('/x/cover.jpg')), isFalse);
      expect(isAudioFile(File('/x/notes.txt')), isFalse);
      expect(isAudioFile(File('/x/no-ext')), isFalse);
    });
  });

  group('isPlaylistFile', () {
    test('matches m3u and m3u8', () {
      expect(isPlaylistFile(File('/x/p.m3u')), isTrue);
      expect(isPlaylistFile(File('/x/p.M3U8')), isTrue);
    });

    test('rejects audio + sidecars', () {
      expect(isPlaylistFile(File('/x/foo.mp3')), isFalse);
      expect(isPlaylistFile(File('/x/._a.m3u')), isFalse);
    });
  });

  group('AlbumManifest JSON', () {
    test('round-trips songs + expectedSongCount', () {
      const m = AlbumManifest(
        songs: [
          ManifestSong(
              id: 's1',
              title: 'T1',
              artist: 'A',
              album: 'B',
              filename: '01.mp3'),
          ManifestSong(id: 's2', title: 'T2'),
        ],
        expectedSongCount: 5,
      );
      final raw = jsonEncode(m.toJson());
      final back = AlbumManifest.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      expect(back.songs.length, 2);
      expect(back.songs[0].id, 's1');
      expect(back.songs[0].filename, '01.mp3');
      expect(back.songs[1].artist, isNull);
      expect(back.expectedSongCount, 5);
    });

    test('omits null optional fields from toJson output', () {
      const m = AlbumManifest(
        songs: [ManifestSong(id: 's', title: 'T')],
      );
      final json = m.toJson();
      final s = (json['songs'] as List).first as Map<String, dynamic>;
      // Optional fields should not be present rather than serialized as null —
      // keeps the manifest file small and human-readable.
      expect(s.containsKey('artist'), isFalse);
      expect(s.containsKey('album'), isFalse);
      expect(s.containsKey('filename'), isFalse);
    });

    test('treats a non-list songs field as empty', () {
      final m =
          AlbumManifest.fromJson({'version': 1, 'songs': 'not-a-list'});
      expect(m.songs, isEmpty);
    });
  });

  group('readManifest', () {
    test('returns null when the file does not exist', () {
      expect(readManifest(tmp.path), isNull);
    });

    test('returns null on malformed JSON without throwing', () async {
      await File(p.join(tmp.path, '.dapper.json'))
          .writeAsString('{not valid json');
      expect(readManifest(tmp.path), isNull);
    });

    test('parses a valid manifest', () async {
      await File(p.join(tmp.path, '.dapper.json')).writeAsString(jsonEncode({
        'version': 1,
        'songs': [
          {'id': 'x', 'title': 'X'},
        ],
      }));
      final m = readManifest(tmp.path);
      expect(m, isNotNull);
      expect(m!.songs.single.id, 'x');
    });
  });

  group('writeManifest', () {
    test('writes JSON to .dapper.json', () {
      writeManifest(
        tmp.path,
        const AlbumManifest(
          songs: [ManifestSong(id: 's', title: 'T')],
        ),
      );
      final raw = File(p.join(tmp.path, '.dapper.json')).readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['version'], 1);
    });

    test('overwrites an existing manifest', () {
      writeManifest(tmp.path,
          const AlbumManifest(songs: [ManifestSong(id: 'a', title: 'A')]));
      writeManifest(tmp.path,
          const AlbumManifest(songs: [ManifestSong(id: 'b', title: 'B')]));
      final m = readManifest(tmp.path)!;
      expect(m.songs.single.id, 'b');
    });

    test('does not leave a stray .tmp file behind (atomic rename)', () {
      writeManifest(tmp.path,
          const AlbumManifest(songs: [ManifestSong(id: 's', title: 'T')]));
      final tmpFile = File(p.join(tmp.path, '.dapper.json.tmp'));
      expect(tmpFile.existsSync(), isFalse,
          reason: 'tmp file must be renamed away, never left dangling');
    });
  });

  group('addSongToManifest', () {
    test('creates a new manifest when none exists', () {
      addSongToManifest(tmp.path, _song(),
          filename: '01.mp3', expectedSongCount: 3);
      final m = readManifest(tmp.path)!;
      expect(m.songs.single.id, 's1');
      expect(m.songs.single.filename, '01.mp3');
      expect(m.expectedSongCount, 3);
    });

    test('replaces an existing entry for the same song id (idempotent)', () {
      addSongToManifest(tmp.path, _song(id: 's1', title: 'old'),
          filename: 'old.mp3');
      addSongToManifest(tmp.path, _song(id: 's1', title: 'new'),
          filename: 'new.mp3');
      final m = readManifest(tmp.path)!;
      expect(m.songs.length, 1);
      expect(m.songs.single.title, 'new');
      expect(m.songs.single.filename, 'new.mp3');
    });

    test('appends additional songs', () {
      addSongToManifest(tmp.path, _song(id: 'a'));
      addSongToManifest(tmp.path, _song(id: 'b'));
      addSongToManifest(tmp.path, _song(id: 'c'));
      final m = readManifest(tmp.path)!;
      expect(m.songs.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('preserves expectedSongCount across writes when not overridden', () {
      addSongToManifest(tmp.path, _song(id: 'a'), expectedSongCount: 4);
      addSongToManifest(tmp.path, _song(id: 'b')); // no count this time
      final m = readManifest(tmp.path)!;
      expect(m.expectedSongCount, 4);
    });

    test('lets a new expectedSongCount override an old one', () {
      addSongToManifest(tmp.path, _song(id: 'a'), expectedSongCount: 4);
      addSongToManifest(tmp.path, _song(id: 'b'), expectedSongCount: 99);
      final m = readManifest(tmp.path)!;
      expect(m.expectedSongCount, 99);
    });
  });

  group('addSongToManifestAsync', () {
    test('matches the sync version end to end', () async {
      await addSongToManifestAsync(tmp.path, _song(id: 'a'), fs,
          filename: 'a.mp3', expectedSongCount: 2);
      await addSongToManifestAsync(tmp.path, _song(id: 'b'), fs,
          filename: 'b.mp3');
      final m = readManifest(tmp.path)!;
      expect(m.songs.map((s) => s.id), ['a', 'b']);
      expect(m.expectedSongCount, 2);
    });

    test('survives concurrent calls when they are externally serialised',
        () async {
      // Mirrors what TransferQueueNotifier does via _manifestFutures — chain
      // writes per folder.  This test confirms that *with* that chaining the
      // file ends up consistent.
      Future<void> chain = Future.value();
      for (var i = 0; i < 10; i++) {
        chain = chain.then((_) =>
            addSongToManifestAsync(tmp.path, _song(id: 's$i'), fs));
      }
      await chain;
      final m = readManifest(tmp.path)!;
      expect(m.songs.length, 10);
    });
  });

  group('manifest cache', () {
    test('subsequent readManifest is served from in-memory cache', () async {
      writeManifest(tmp.path,
          const AlbumManifest(songs: [ManifestSong(id: 'a', title: 'A')]));
      // Mutate the file out-of-band — cache should still return the old value.
      await File(p.join(tmp.path, '.dapper.json')).writeAsString(jsonEncode({
        'version': 1,
        'songs': [
          {'id': 'b', 'title': 'B'}
        ],
      }));
      expect(readManifest(tmp.path)!.songs.single.id, 'a');
    });

    test('clearDeviceCaches forces a fresh disk read', () async {
      writeManifest(tmp.path,
          const AlbumManifest(songs: [ManifestSong(id: 'a', title: 'A')]));
      await File(p.join(tmp.path, '.dapper.json')).writeAsString(jsonEncode({
        'version': 1,
        'songs': [
          {'id': 'b', 'title': 'B'}
        ],
      }));
      clearDeviceCaches();
      expect(readManifest(tmp.path)!.songs.single.id, 'b');
    });

    test('write through cache: addSongToManifest reflects in next read '
        'without disk roundtrip', () {
      addSongToManifest(tmp.path, _song(id: 'a'));
      // No clearDeviceCaches — must still see the new entry via cache.
      expect(readManifest(tmp.path)!.songs.single.id, 'a');
    });

    test('caches negative lookup (file does not exist)', () {
      // First read: file missing → cached as null.
      expect(readManifest(tmp.path), isNull);
      // Create the file *behind* the cache — second read should still be null
      // until clearDeviceCaches() is called.
      File(p.join(tmp.path, '.dapper.json')).writeAsStringSync(jsonEncode({
        'version': 1,
        'songs': [
          {'id': 'a', 'title': 'A'}
        ],
      }));
      expect(readManifest(tmp.path), isNull);
      clearDeviceCaches();
      expect(readManifest(tmp.path)!.songs.single.id, 'a');
    });
  });

  group('folderExistsCached', () {
    test('returns true for an existing folder and caches the result', () async {
      final exists = folderExistsCached(tmp.path);
      expect(exists, isTrue);

      // Delete behind the cache: second call should still return true.
      await tmp.delete(recursive: true);
      expect(folderExistsCached(tmp.path), isTrue);
    });

    test('returns false for a missing folder', () {
      final fake = p.join(tmp.path, 'does-not-exist');
      expect(folderExistsCached(fake), isFalse);
    });

    test('writeManifest marks the folder as existing in the cache', () {
      // Even if folderExistsCached was never called for this path before,
      // a successful writeManifest implies the folder exists now.
      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      writeManifest(sub.path,
          const AlbumManifest(songs: [ManifestSong(id: 's', title: 'T')]));
      expect(folderExistsCached(sub.path), isTrue);
    });
  });
}
