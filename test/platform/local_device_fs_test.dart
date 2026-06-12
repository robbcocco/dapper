import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/domain/models/device_settings.dart';
import 'package:dapper/platform/device_fs.dart';
import 'package:dapper/platform/local_device_fs.dart';

void main() {
  late Directory tmp;
  late LocalDeviceFs fs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_device_fs_test_');
    fs = LocalDeviceFs(tmp.path, maxConcurrentTransfers: 4);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('protocol + concurrency', () {
    test('reports filesystem protocol', () {
      expect(fs.protocol, DeviceProtocol.filesystem);
    });

    test('returns configured concurrency', () {
      expect(fs.maxConcurrentTransfers, 4);
    });
  });

  group('exists / isDir', () {
    test('exists is false for missing path', () async {
      expect(await fs.exists(p.join(tmp.path, 'nope')), isFalse);
    });

    test('exists is true for a file', () async {
      final f = File(p.join(tmp.path, 'a.txt'));
      await f.writeAsString('hi');
      expect(await fs.exists(f.path), isTrue);
      expect(await fs.isDir(f.path), isFalse);
    });

    test('isDir is true for a directory', () async {
      final d = Directory(p.join(tmp.path, 'sub'));
      await d.create();
      expect(await fs.isDir(d.path), isTrue);
    });
  });

  group('sizeOf', () {
    test('returns null for missing', () async {
      expect(await fs.sizeOf(p.join(tmp.path, 'nope')), isNull);
    });

    test('returns byte length for present file', () async {
      final f = File(p.join(tmp.path, 'a.txt'));
      await f.writeAsString('hello');
      expect(await fs.sizeOf(f.path), 5);
    });
  });

  group('mkdirp / list', () {
    test('mkdirp creates nested parents', () async {
      final target = p.join(tmp.path, 'a', 'b', 'c');
      await fs.mkdirp(target);
      expect(Directory(target).existsSync(), isTrue);
    });

    test('mkdirp on existing dir is a no-op', () async {
      final target = p.join(tmp.path, 'a');
      await fs.mkdirp(target);
      await fs.mkdirp(target); // should not throw
      expect(Directory(target).existsSync(), isTrue);
    });

    test('list returns empty for missing dir', () async {
      expect(await fs.list(p.join(tmp.path, 'nope')), isEmpty);
    });

    test('list distinguishes files vs dirs and reports sizes', () async {
      await fs.mkdirp(p.join(tmp.path, 'sub'));
      await File(p.join(tmp.path, 'a.txt')).writeAsString('hello');
      final entries = await fs.list(tmp.path);
      expect(entries, hasLength(2));
      final sub = entries.firstWhere((e) => p.basename(e.path) == 'sub');
      final f = entries.firstWhere((e) => p.basename(e.path) == 'a.txt');
      expect(sub.isDir, isTrue);
      expect(f.isDir, isFalse);
      expect(f.size, 5);
    });
  });

  group('delete / deleteRecursive', () {
    test('delete removes a file', () async {
      final path = p.join(tmp.path, 'x.txt');
      await File(path).writeAsString('h');
      await fs.delete(path);
      expect(File(path).existsSync(), isFalse);
    });

    test('delete on missing path is a no-op', () async {
      await fs.delete(p.join(tmp.path, 'missing')); // does not throw
    });

    test('deleteRecursive removes a populated dir', () async {
      final root = Directory(p.join(tmp.path, 'tree'));
      await root.create();
      await File(p.join(root.path, 'a.txt')).writeAsString('a');
      await Directory(p.join(root.path, 'sub')).create();
      await File(p.join(root.path, 'sub', 'b.txt')).writeAsString('b');
      await fs.deleteRecursive(root.path);
      expect(root.existsSync(), isFalse);
    });
  });

  group('openWrite / openRead', () {
    test('write then read round-trips bytes', () async {
      final path = p.join(tmp.path, 'out.bin');
      final h = await fs.openWrite(path);
      await h.write([1, 2, 3]);
      await h.write([4, 5]);
      await h.close();
      final read = await fs.openRead(path);
      final bytes = <int>[];
      await for (final chunk in read) {
        bytes.addAll(chunk);
      }
      expect(bytes, [1, 2, 3, 4, 5]);
    });

    test('abort deletes the partial file', () async {
      final path = p.join(tmp.path, 'partial.bin');
      final h = await fs.openWrite(path);
      await h.write([9, 9]);
      await h.abort();
      expect(File(path).existsSync(), isFalse);
    });

    test('close after close is a no-op', () async {
      final path = p.join(tmp.path, 'idem.bin');
      final h = await fs.openWrite(path);
      await h.write([1]);
      await h.close();
      await h.close(); // should not throw
    });
  });

  group('openAtomicReplace', () {
    test('writes via .tmp then renames over target', () async {
      final target = p.join(tmp.path, 'manifest.json');
      await File(target).writeAsString('OLD');
      final h = await fs.openAtomicReplace(target);
      await h.write(utf8.encode('NEW'));
      // Tmp must exist before close; target unchanged until rename.
      expect(File('$target.tmp').existsSync(), isTrue);
      expect(await File(target).readAsString(), 'OLD');
      await h.close();
      expect(File('$target.tmp').existsSync(), isFalse);
      expect(await File(target).readAsString(), 'NEW');
    });

    test('abort cleans up tmp and leaves original intact', () async {
      final target = p.join(tmp.path, 'manifest.json');
      await File(target).writeAsString('OLD');
      final h = await fs.openAtomicReplace(target);
      await h.write(utf8.encode('PARTIAL'));
      await h.abort();
      expect(File('$target.tmp').existsSync(), isFalse);
      expect(await File(target).readAsString(), 'OLD');
    });
  });

  group('truncate', () {
    test('empties the file without deleting it', () async {
      final path = p.join(tmp.path, 'log');
      await File(path).writeAsString('header\nrow\n');
      await fs.truncate(path);
      expect(File(path).existsSync(), isTrue);
      expect(await File(path).readAsString(), '');
    });
  });

  group('removeSidecar', () {
    test('no-throw on missing sidecar', () async {
      final target = p.join(tmp.path, 'song.mp3');
      await File(target).writeAsString('audio');
      await fs.removeSidecar(target); // no-throw across platforms
      expect(File(target).existsSync(), isTrue);
    });
  });

  group('resolveMusicRoot', () {
    test('empty musicRootFolder returns devicePath', () {
      const s = DeviceSettings(devicePath: '/Volumes/X', musicRootFolder: '');
      expect(fs.resolveMusicRoot(s), '/Volumes/X');
    });

    test('joins simple subfolder', () {
      const s =
          DeviceSettings(devicePath: '/Volumes/X', musicRootFolder: 'Music');
      expect(fs.resolveMusicRoot(s), p.join('/Volumes/X', 'Music'));
    });

    test('normalises backslash to forward slash for nested', () {
      const s = DeviceSettings(
          devicePath: '/Volumes/X', musicRootFolder: 'Music\\FLAC');
      expect(fs.resolveMusicRoot(s), p.join('/Volumes/X', 'Music', 'FLAC'));
    });
  });
}
