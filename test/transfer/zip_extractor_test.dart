import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/application/transfer/zip_extractor.dart';
import 'package:dapper/domain/models/device_settings.dart';
import 'package:dapper/domain/models/song.dart';

Song _song({
  required String id,
  required String title,
  String? album = 'Piper at the Gates',
  String? artist = 'Pink Floyd',
  String? albumArtist = 'Pink Floyd',
  int? track,
  int? discNumber = 1,
  int? year = 1967,
  String? suffix = 'flac',
}) =>
    Song(
      id: id,
      title: title,
      album: album,
      artist: artist,
      albumArtist: albumArtist,
      track: track,
      discNumber: discNumber,
      year: year,
      suffix: suffix,
    );

/// Builds a real zip on disk with the given (archivePath, payload) entries.
String _buildZip(Directory dir, Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((path, payload) {
    archive.addFile(ArchiveFile(path, payload.length, payload));
  });
  final zipPath = p.join(dir.path, 'test.zip');
  final bytes = ZipEncoder().encode(archive)!;
  File(zipPath).writeAsBytesSync(bytes);
  return zipPath;
}

/// Repeats [pattern] to produce [bytes] of compressible data — enough volume
/// to force the archive package's lazy-decompression path during extraction.
List<int> _bulk(int bytes, [int pattern = 0xAA]) =>
    List<int>.filled(bytes, pattern);

void main() {
  group('extractAlbumZip', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('dapper_zip_test_');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('writes matched entries to per-song target paths', () async {
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);

      final songs = [
        _song(id: 's1', title: 'Astronomy Domine', track: 1),
        _song(id: 's2', title: 'Lucifer Sam', track: 2),
      ];
      final zip = _buildZip(tmp, {
        'Pink Floyd/Piper/01 - Astronomy Domine.flac': List.filled(10, 0x41),
        'Pink Floyd/Piper/02 - Lucifer Sam.flac': List.filled(20, 0x42),
      });

      final result = await extractAlbumZip(
        zipPath: zip,
        expectedSongs: songs,
        settings: settings,
      );

      expect(result.matchedSongIds, {'s1', 's2'});
      expect(result.skipped, isEmpty);
      expect(result.extracted.length, 2);

      final byId = {for (final e in result.extracted) e.songId: e};
      final f1 = File(byId['s1']!.targetPath);
      final f2 = File(byId['s2']!.targetPath);
      expect(f1.existsSync(), isTrue);
      expect(f2.existsSync(), isTrue);
      expect(f1.lengthSync(), 10);
      expect(f2.lengthSync(), 20);

      // Paths follow Artist/Album/track-title.ext layout.
      expect(f1.path.endsWith('Pink Floyd/Piper at the Gates/1-01 - Astronomy Domine.flac'),
          isTrue, reason: f1.path);
    });

    test('skips entries that do not match any expected song', () async {
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);
      final songs = [_song(id: 's1', title: 'Astronomy Domine', track: 1)];
      final zip = _buildZip(tmp, {
        'Album/01 - Astronomy Domine.flac': List.filled(5, 0x00),
        'Album/99 - Bonus Track Nobody Knows.flac': List.filled(5, 0x00),
      });

      final result = await extractAlbumZip(
        zipPath: zip,
        expectedSongs: songs,
        settings: settings,
      );

      expect(result.matchedSongIds, {'s1'});
      expect(result.skipped.length, 1);
      expect(result.skipped.first, contains('99 - Bonus Track'));
    });

    test('refuses entries that contain parent traversal', () async {
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);
      final songs = [_song(id: 's1', title: 'X', track: 1)];
      final zip = _buildZip(tmp, {
        '../escapes/01 - X.flac': List.filled(5, 0x00),
      });

      final result = await extractAlbumZip(
        zipPath: zip,
        expectedSongs: songs,
        settings: settings,
      );
      expect(result.matchedSongIds, isEmpty);
      expect(result.skipped.first, startsWith('parent traversal'));
    });

    test('honours overwriteExisting=false', () async {
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);
      final songs = [_song(id: 's1', title: 'X', track: 1)];

      // Pre-create target file. Layout: device/Pink Floyd/Piper at the Gates/1-01 - X.flac
      final existing = File(p.join(device.path, 'Pink Floyd',
          'Piper at the Gates', '1-01 - X.flac'));
      existing.parent.createSync(recursive: true);
      existing.writeAsStringSync('OLD');

      final zip = _buildZip(tmp, {
        'Album/01 - X.flac': List.filled(50, 0x55),
      });

      final result = await extractAlbumZip(
        zipPath: zip,
        expectedSongs: songs,
        settings: settings,
      );

      expect(result.matchedSongIds, {'s1'});
      expect(existing.readAsStringSync(), 'OLD',
          reason: 'overwriteExisting=false should preserve existing file');
    });

    test('respects isCancelled between entries', () async {
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);
      final songs = [
        _song(id: 's1', title: 'A', track: 1),
        _song(id: 's2', title: 'B', track: 2),
        _song(id: 's3', title: 'C', track: 3),
      ];
      final zip = _buildZip(tmp, {
        'X/01 - A.flac': List.filled(5, 0x01),
        'X/02 - B.flac': List.filled(5, 0x02),
        'X/03 - C.flac': List.filled(5, 0x03),
      });

      // Cancel after the first match lands.
      var landed = 0;
      bool cancel() {
        if (landed >= 1) return true;
        landed++; // increment per check call so we don't trip on iteration 0
        return false;
      }

      final result = await extractAlbumZip(
        zipPath: zip,
        expectedSongs: songs,
        settings: settings,
        isCancelled: cancel,
      );
      expect(result.matchedSongIds.length, lessThan(songs.length));
    });

    test('writes large compressed entries (lazy decompression path)', () async {
      // Regression: zip_extractor used to close InputFileStream before the
      // entry-iteration loop ran. Tiny fixture payloads got eagerly decoded
      // by decodeBuffer and survived; real-world multi-MB FLACs hit the
      // lazy-decompression path and every writeContent threw. This test
      // forces that path with ~256 KiB of compressible data per entry.
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);
      final songs = [
        _song(id: 's1', title: 'A', track: 1),
        _song(id: 's2', title: 'B', track: 2),
      ];
      final zip = _buildZip(tmp, {
        'X/01 - A.flac': _bulk(256 * 1024, 0xAA),
        'X/02 - B.flac': _bulk(256 * 1024, 0x55),
      });

      final result = await extractAlbumZip(
        zipPath: zip,
        expectedSongs: songs,
        settings: settings,
      );
      expect(result.matchedSongIds, {'s1', 's2'},
          reason: 'skipped: ${result.skipped}');
      final byId = {for (final e in result.extracted) e.songId: e};
      expect(File(byId['s1']!.targetPath).lengthSync(), 256 * 1024);
      expect(File(byId['s2']!.targetPath).lengthSync(), 256 * 1024);
    });

    test('marshalled entry round-trips through compute', () async {
      // Regression: previously the engine passed Freezed Song/DeviceSettings
      // through Isolate.run as a captured closure and the runtime rejected
      // it with "Illegal argument in isolate". The marshalled entry sends
      // only primitives, and `compute` uses a top-level function reference
      // (no closure transfer) so it survives Flutter's AOT macOS builds.
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);
      final songs = [
        _song(id: 's1', title: 'A', track: 1),
        _song(id: 's2', title: 'B', track: 2),
      ];
      final zip = _buildZip(tmp, {
        'X/01 - A.flac': _bulk(32 * 1024, 0x11),
        'X/02 - B.flac': _bulk(32 * 1024, 0x22),
      });

      final args = <String, dynamic>{
        'zipPath': zip,
        'songs': [for (final s in songs) songToMap(s)],
        'settings': settingsToMap(settings),
        'removeMacosSidecars': false,
      };

      final raw = await compute(extractAlbumZipMarshalled, args);
      final extracted = (raw['extracted'] as List).cast<Map>();
      final ids = extracted.map((m) => m['songId']).toSet();
      expect(ids, {'s1', 's2'});
    });

    test('computes expectedCount per album folder', () async {
      // Artist-zip case: two albums, two songs each → engine should write 2
      // into one folder's expectedCount and 1 into the other.
      final device = Directory(p.join(tmp.path, 'device'))..createSync();
      final settings = DeviceSettings(devicePath: device.path);
      final songs = [
        _song(id: 'a1', title: 'A1', album: 'A', track: 1),
        _song(id: 'a2', title: 'A2', album: 'A', track: 2),
        _song(id: 'b1', title: 'B1', album: 'B', track: 1),
      ];
      final zip = _buildZip(tmp, {
        'Pink Floyd/A/01 - A1.flac': List.filled(3, 0),
        'Pink Floyd/A/02 - A2.flac': List.filled(3, 0),
        'Pink Floyd/B/01 - B1.flac': List.filled(3, 0),
      });

      final result = await extractAlbumZip(
        zipPath: zip,
        expectedSongs: songs,
        settings: settings,
      );
      final byFolder = <String, int?>{};
      for (final item in result.extracted) {
        byFolder[p.dirname(item.targetPath)] = item.expectedCount;
      }
      expect(byFolder.length, 2);
      final aFolder = byFolder.keys.firstWhere((k) => k.endsWith('/A'));
      final bFolder = byFolder.keys.firstWhere((k) => k.endsWith('/B'));
      expect(byFolder[aFolder], 2);
      expect(byFolder[bFolder], 1);
    });
  });
}
