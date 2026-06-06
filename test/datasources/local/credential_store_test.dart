import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/data/datasources/local/credential_store.dart';

// In-memory CredentialStore used to stand in for either backend.
class _MemoryStore implements CredentialStore {
  _MemoryStore({this.throwOnEverything});

  final Map<String, String> map = {};
  // When non-null, every operation throws this exception. Lets us simulate the
  // macOS Keychain returning -34018 errSecMissingEntitlement.
  final Object? throwOnEverything;
  int readCalls = 0;
  int writeCalls = 0;
  int deleteAllCalls = 0;

  void _maybeThrow() {
    final t = throwOnEverything;
    if (t != null) throw t;
  }

  @override
  Future<String?> read({required String key}) async {
    readCalls++;
    _maybeThrow();
    return map[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    writeCalls++;
    _maybeThrow();
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    _maybeThrow();
    map.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCalls++;
    _maybeThrow();
    map.clear();
  }
}

void main() {
  group('FileCredentialStore', () {
    late Directory tmp;
    late String filePath;
    late FileCredentialStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dapper_cred_test_');
      filePath = p.join(tmp.path, 'credentials.json');
      store = FileCredentialStore(filePath);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('read returns null when no file exists', () async {
      expect(await store.read(key: 'missing'), isNull);
    });

    test('write then read round-trips', () async {
      await store.write(key: 'k', value: 'v');
      expect(await store.read(key: 'k'), 'v');
    });

    test('write with null value deletes the key', () async {
      await store.write(key: 'k', value: 'v');
      await store.write(key: 'k', value: null);
      expect(await store.read(key: 'k'), isNull);
    });

    test('delete removes the key', () async {
      await store.write(key: 'k', value: 'v');
      await store.delete(key: 'k');
      expect(await store.read(key: 'k'), isNull);
    });

    test('deleteAll clears every entry', () async {
      await store.write(key: 'a', value: '1');
      await store.write(key: 'b', value: '2');
      await store.deleteAll();
      expect(await store.read(key: 'a'), isNull);
      expect(await store.read(key: 'b'), isNull);
    });

    test('persists across instances (different store reading same file)',
        () async {
      await store.write(key: 'k', value: 'v');
      final fresh = FileCredentialStore(filePath);
      expect(await fresh.read(key: 'k'), 'v');
    });

    test('atomic write: no .tmp sibling left dangling after write', () async {
      await store.write(key: 'k', value: 'v');
      expect(File('$filePath.tmp').existsSync(), isFalse);
    });

    test('serialised writes do not drop entries under concurrency', () async {
      // 50 parallel writes — the internal chain must ensure each one is
      // serialised so the final file contains all 50 keys.
      await Future.wait([
        for (var i = 0; i < 50; i++)
          store.write(key: 'k$i', value: 'v$i'),
      ]);
      for (var i = 0; i < 50; i++) {
        expect(await store.read(key: 'k$i'), 'v$i');
      }
    });

    test('treats malformed JSON on disk as empty rather than throwing',
        () async {
      await File(filePath).writeAsString('{not valid json');
      // Read should silently return null and not throw.
      expect(await store.read(key: 'k'), isNull);
      // Subsequent writes should heal the file.
      await store.write(key: 'k', value: 'v');
      expect(await store.read(key: 'k'), 'v');
    });

    test('file on disk is valid JSON object after a write', () async {
      await store.write(key: 'k', value: 'v');
      final raw = File(filePath).readAsStringSync();
      final decoded = jsonDecode(raw);
      expect(decoded, isA<Map>());
      expect((decoded as Map)['k'], 'v');
    });

    // Skip the chmod check on Windows where we don't run the mode change.
    test('on POSIX, written file is mode 600', () async {
      await store.write(key: 'k', value: 'v');
      // FileStat.modeString() may or may not include a leading type byte
      // ("rw-------" vs "-rw-------" depending on Dart version) — check the
      // semantic instead: the last 6 chars (group + other) must all be '-'.
      final mode = File(filePath).statSync().modeString();
      expect(mode.endsWith('------'), isTrue,
          reason: 'group + other bits must be unreadable; got "$mode"');
    }, skip: Platform.isWindows ? 'POSIX mode bits only' : false);
  });

  group('FallbackCredentialStore', () {
    test('uses primary while it works; never touches fallback', () async {
      final primary = _MemoryStore();
      final fallback = _MemoryStore();
      final store =
          FallbackCredentialStore(primary: primary, fallback: fallback);

      await store.write(key: 'k', value: 'v');
      expect(await store.read(key: 'k'), 'v');
      expect(primary.map['k'], 'v');
      expect(fallback.map['k'], isNull);
    });

    test(
        'switches permanently to fallback on PlatformException from primary',
        () async {
      final primary = _MemoryStore(
        throwOnEverything: PlatformException(code: '-34018', message: 'no ent'),
      );
      final fallback = _MemoryStore();
      final store =
          FallbackCredentialStore(primary: primary, fallback: fallback);

      // First write fails on primary → falls back to fallback.
      await store.write(key: 'k', value: 'v');
      expect(primary.writeCalls, 1, reason: 'tried primary once');
      expect(fallback.map['k'], 'v');

      // Second write should NOT hit primary again — it's marked dead.
      await store.write(key: 'k2', value: 'v2');
      expect(primary.writeCalls, 1,
          reason: 'primary stays dead for the rest of the session');
      expect(fallback.map['k2'], 'v2');

      // Reads also go to fallback now without retrying primary.
      expect(await store.read(key: 'k'), 'v');
      expect(primary.readCalls, 0);
    });

    test('also handles MissingPluginException', () async {
      final primary = _MemoryStore(
          throwOnEverything: MissingPluginException('not registered'));
      final fallback = _MemoryStore();
      final store =
          FallbackCredentialStore(primary: primary, fallback: fallback);

      await store.write(key: 'k', value: 'v');
      expect(fallback.map['k'], 'v');
    });

    test('rethrows non-platform errors instead of switching backends',
        () async {
      // A bare Exception is a programming-level mistake, not a credential
      // backend issue — propagate it so the caller sees it.
      final primary =
          _MemoryStore(throwOnEverything: Exception('something else'));
      final fallback = _MemoryStore();
      final store =
          FallbackCredentialStore(primary: primary, fallback: fallback);

      await expectLater(
        store.write(key: 'k', value: 'v'),
        throwsA(isA<Exception>()),
      );
      // Fallback must NOT have been touched.
      expect(fallback.map, isEmpty);
    });

    test('deleteAll wipes both backends, even if one throws', () async {
      final primary = _MemoryStore(
          throwOnEverything: PlatformException(code: '-34018'));
      final fallback = _MemoryStore();
      fallback.map['leftover'] = 'x';

      final store =
          FallbackCredentialStore(primary: primary, fallback: fallback);
      await store.deleteAll();
      // primary.deleteAll throws but is swallowed; fallback must still clear.
      expect(fallback.map, isEmpty);
    });

    test('after the fallback takes over, deleteAll still works', () async {
      final primary = _MemoryStore();
      final fallback = _MemoryStore();
      final store =
          FallbackCredentialStore(primary: primary, fallback: fallback);

      await store.write(key: 'a', value: '1');
      await store.write(key: 'b', value: '2');
      await store.deleteAll();
      expect(primary.map, isEmpty);
      expect(fallback.map, isEmpty);
    });
  });
}
