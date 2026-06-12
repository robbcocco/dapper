import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/domain/models/device_settings.dart';
import 'package:dapper/platform/device_fs.dart';
import 'package:dapper/platform/mtp_client.dart';
import 'package:dapper/platform/mtp_device_fs.dart';

/// In-memory fake. Each node has an objectId, parent, name, isDir, bytes.
/// Mirrors MTP semantics enough for cache + mutex tests.
class _FakeMtpClient extends MtpClient {
  _FakeMtpClient() : super.forTesting();

  int _nextId = 100;
  final Map<int, _Node> nodes = {};
  final Map<String, _PutSession> puts = {};
  final List<String> log = []; // method-call trace

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<List<MtpDevice>> enumerate() async {
    log.add('enumerate');
    return const [];
  }

  @override
  Future<void> openSession(String deviceId) async {
    log.add('openSession:$deviceId');
  }

  @override
  Future<void> closeSession(String deviceId) async {
    log.add('closeSession:$deviceId');
  }

  @override
  Future<List<MtpObject>> list(String deviceId, int parentObjectId) async {
    log.add('list:$parentObjectId');
    final children = nodes.values
        .where((n) => n.parentId == parentObjectId)
        .map((n) => MtpObject(
              objectId: n.id,
              name: n.name,
              isDir: n.isDir,
              size: n.bytes.length,
            ))
        .toList();
    return children;
  }

  @override
  Future<int> mkdir(String deviceId, int parentObjectId, String name) async {
    log.add('mkdir:$parentObjectId/$name');
    final id = _nextId++;
    nodes[id] = _Node(id: id, parentId: parentObjectId, name: name, isDir: true);
    return id;
  }

  @override
  Future<void> delete(String deviceId, int objectId) async {
    log.add('delete:$objectId');
    nodes.removeWhere((id, n) => id == objectId || n.parentId == objectId);
  }

  @override
  Future<int?> freeSpace(String deviceId) async => 1024 * 1024 * 1024;

  @override
  Future<String> putBegin({
    required String deviceId,
    required int parentObjectId,
    required String name,
    required int totalBytes,
  }) async {
    log.add('putBegin:$parentObjectId/$name');
    final streamId = 's${_nextId++}';
    puts[streamId] = _PutSession(parentId: parentObjectId, name: name);
    return streamId;
  }

  @override
  Future<void> putChunk(String streamId, Uint8List bytes) async {
    log.add('putChunk:$streamId:${bytes.length}');
    puts[streamId]!.bytes.addAll(bytes);
  }

  @override
  Future<int> putCommit(String streamId) async {
    log.add('putCommit:$streamId');
    final session = puts.remove(streamId)!;
    final id = _nextId++;
    nodes[id] = _Node(
      id: id,
      parentId: session.parentId,
      name: session.name,
      isDir: false,
      bytes: session.bytes,
    );
    return id;
  }

  @override
  Future<void> putAbort(String streamId) async {
    log.add('putAbort:$streamId');
    puts.remove(streamId);
  }

  @override
  Future<String> getBegin(String deviceId, int objectId) async {
    log.add('getBegin:$objectId');
    return 'g$objectId';
  }

  int _getCursor = 0;
  @override
  Future<Uint8List> getChunk(String streamId, int maxBytes) async {
    final objectId = int.parse(streamId.substring(1));
    final node = nodes[objectId];
    if (node == null) return Uint8List(0);
    final start = _getCursor;
    if (start >= node.bytes.length) {
      _getCursor = 0;
      return Uint8List(0);
    }
    final end = (start + maxBytes).clamp(0, node.bytes.length);
    _getCursor = end;
    return Uint8List.fromList(node.bytes.sublist(start, end));
  }

  @override
  Future<void> getEnd(String streamId) async {
    _getCursor = 0;
    log.add('getEnd:$streamId');
  }
}

class _Node {
  _Node({
    required this.id,
    required this.parentId,
    required this.name,
    required this.isDir,
    List<int>? bytes,
  }) : bytes = bytes ?? [];
  final int id;
  final int parentId;
  final String name;
  final bool isDir;
  final List<int> bytes;
}

class _PutSession {
  _PutSession({required this.parentId, required this.name});
  final int parentId;
  final String name;
  final List<int> bytes = [];
}

void main() {
  late _FakeMtpClient fake;
  late MtpDeviceFs fs;

  setUp(() {
    fake = _FakeMtpClient();
    fs = MtpDeviceFs(client: fake, devicePath: 'mtp://dev1');
  });

  group('constructor', () {
    test('throws on non-mtp devicePath', () {
      expect(
        () => MtpDeviceFs(client: fake, devicePath: '/Volumes/Foo'),
        throwsArgumentError,
      );
    });

    test('reports mtp protocol + concurrency=1', () {
      expect(fs.protocol, DeviceProtocol.mtp);
      expect(fs.maxConcurrentTransfers, 1);
    });
  });

  group('mkdirp', () {
    test('creates nested dirs incrementally', () async {
      await fs.mkdirp('mtp://dev1/Music/Artist/Album');
      // Three mkdir calls, one per missing segment.
      final mkdirs = fake.log.where((l) => l.startsWith('mkdir:')).toList();
      expect(mkdirs, [
        'mkdir:0/Music',
        'mkdir:100/Artist', // 100 = first mkdir id
        'mkdir:101/Album', // 101 = second mkdir id
      ]);
    });

    test('idempotent when dirs already exist', () async {
      await fs.mkdirp('mtp://dev1/Music');
      fake.log.clear();
      await fs.mkdirp('mtp://dev1/Music');
      // Cached → no mkdir issued.
      expect(fake.log.where((l) => l.startsWith('mkdir:')), isEmpty);
    });
  });

  group('exists / isDir / list', () {
    test('list of empty dir returns []', () async {
      final entries = await fs.list('mtp://dev1');
      expect(entries, isEmpty);
    });

    test('list populates path↔objectId cache', () async {
      await fs.mkdirp('mtp://dev1/Music');
      fake.log.clear();
      // Manually probe Music; cached.
      expect(await fs.exists('mtp://dev1/Music'), isTrue);
      // No fresh list issued because mkdirp populated the cache.
      expect(fake.log.where((l) => l.startsWith('list:')), isEmpty);
    });

    test('isDir true for directory entries', () async {
      await fs.mkdirp('mtp://dev1/Sub');
      expect(await fs.isDir('mtp://dev1/Sub'), isTrue);
    });
  });

  group('openWrite', () {
    test('happy path: putBegin → putChunk → putCommit', () async {
      final handle = await fs.openWrite('mtp://dev1/song.flac');
      await handle.write([1, 2, 3]);
      await handle.write([4, 5]);
      await handle.close();
      expect(fake.puts, isEmpty);
      final found = fake.nodes.values
          .firstWhere((n) => n.name == 'song.flac');
      expect(found.bytes, [1, 2, 3, 4, 5]);
    });

    test('abort issues putAbort and invalidates cache', () async {
      final handle = await fs.openWrite('mtp://dev1/song.flac');
      await handle.write([7, 7]);
      await handle.abort();
      expect(fake.log, contains(matches(RegExp(r'^putAbort:'))));
      // File should not be cached → exists returns false (no node materialised).
      expect(await fs.exists('mtp://dev1/song.flac'), isFalse);
    });

    test('serialises overlapping writes (per-device mutex)', () async {
      final completionOrder = <String>[];
      final h1Future = fs.openWrite('mtp://dev1/a.flac').then((h) async {
        await h.write([1]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await h.close();
        completionOrder.add('a');
      });
      // Kick off second write while first is in flight.
      final h2Future = fs.openWrite('mtp://dev1/b.flac').then((h) async {
        await h.write([2]);
        await h.close();
        completionOrder.add('b');
      });
      await Future.wait([h1Future, h2Future]);
      // Mutex orders them: a completes before b opens its putBegin.
      expect(completionOrder, ['a', 'b']);
    });
  });

  group('openAtomicReplace', () {
    test('deletes existing then writes new bytes', () async {
      // First write creates a file.
      final h1 = await fs.openWrite('mtp://dev1/manifest.json');
      await h1.write([1]);
      await h1.close();
      fake.log.clear();
      // Atomic replace.
      final h2 = await fs.openAtomicReplace('mtp://dev1/manifest.json');
      await h2.write([2, 2]);
      await h2.close();
      expect(fake.log.any((l) => l.startsWith('delete:')), isTrue);
      final found = fake.nodes.values
          .where((n) => n.name == 'manifest.json' && !n.isDir)
          .toList();
      expect(found, hasLength(1));
      expect(found.single.bytes, [2, 2]);
    });
  });

  group('truncate', () {
    test('deletes the object and creates an empty one', () async {
      final h = await fs.openWrite('mtp://dev1/log');
      await h.write([9, 9, 9]);
      await h.close();
      fake.log.clear();
      await fs.truncate('mtp://dev1/log');
      // Result: one new empty node with name 'log'.
      final logs = fake.nodes.values.where((n) => n.name == 'log').toList();
      expect(logs, hasLength(1));
      expect(logs.single.bytes, isEmpty);
    });
  });

  group('removeSidecar', () {
    test('is a no-op (MTP devices materialise no AppleDouble sidecars)',
        () async {
      await fs.removeSidecar('mtp://dev1/foo.mp3');
      expect(fake.log, isEmpty);
    });
  });

  group('resolveMusicRoot', () {
    test('empty subfolder returns the devicePath', () {
      const s = DeviceSettings(devicePath: 'mtp://dev1', musicRootFolder: '');
      expect(fs.resolveMusicRoot(s), 'mtp://dev1');
    });

    test('joins with forward slashes inside the synthetic namespace', () {
      const s = DeviceSettings(
          devicePath: 'mtp://dev1', musicRootFolder: 'Music/FLAC');
      expect(fs.resolveMusicRoot(s), 'mtp://dev1/Music/FLAC');
    });

    test('normalises Windows backslashes', () {
      const s = DeviceSettings(
          devicePath: 'mtp://dev1', musicRootFolder: r'Music\FLAC');
      expect(fs.resolveMusicRoot(s), 'mtp://dev1/Music/FLAC');
    });
  });

  group('dispose', () {
    test('closes the open session', () async {
      await fs.mkdirp('mtp://dev1/x');
      fake.log.clear();
      await fs.dispose();
      expect(fake.log, contains('closeSession:dev1'));
    });

    test('repeated dispose is a no-op', () async {
      await fs.dispose();
      fake.log.clear();
      await fs.dispose();
      expect(fake.log, isEmpty);
    });
  });

  group('freeBytes', () {
    test('forwards to client.freeSpace', () async {
      expect(await fs.freeBytes(), 1024 * 1024 * 1024);
    });
  });

  group('openRead', () {
    test('streams file bytes through getChunk', () async {
      final h = await fs.openWrite('mtp://dev1/song.flac');
      await h.write([1, 2, 3, 4, 5, 6, 7, 8]);
      await h.close();
      final stream = await fs.openRead('mtp://dev1/song.flac');
      final out = <int>[];
      await for (final chunk in stream) {
        out.addAll(chunk);
      }
      expect(out, [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });
}
