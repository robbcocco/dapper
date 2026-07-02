import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Thin abstraction over secret-key storage. Exists so we can transparently
/// fall back from macOS Keychain (which fails with errSecMissingEntitlement
/// -34018 in some signing / translocation states) to an on-disk JSON file.
///
/// Read/write/delete semantics match `FlutterSecureStorage` for ease of swap.
abstract class CredentialStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

/// Backed by the OS keychain via `flutter_secure_storage`.
class KeychainCredentialStore implements CredentialStore {
  KeychainCredentialStore(this._inner);
  final FlutterSecureStorage _inner;

  @override
  Future<String?> read({required String key}) => _inner.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _inner.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _inner.delete(key: key);

  @override
  Future<void> deleteAll() => _inner.deleteAll();
}

/// JSON-file backed store. Writes atomically (tmp + rename) and locks the
/// file at mode 600 on POSIX so other users on the machine can't read it.
class FileCredentialStore implements CredentialStore {
  FileCredentialStore(this._filePath);
  final String _filePath;

  Map<String, String>? _cache;
  // Serialises read-modify-write so concurrent writes don't drop entries.
  Future<void> _chain = Future.value();

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final file = File(_filePath);
    if (!await file.exists()) {
      return _cache = <String, String>{};
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _cache = <String, String>{};
      return _cache = {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } catch (e) {
      dev.log('FileCredentialStore: failed to parse $_filePath — $e');
      return _cache = <String, String>{};
    }
  }

  Future<void> _persist() async {
    final tmp = File('$_filePath.tmp');
    await tmp.writeAsString(jsonEncode(_cache), flush: true);
    // Mode 600 — user-only read/write — matches the protection level the
    // keychain would have provided for the same secrets. Applied to the tmp
    // file BEFORE the rename so the target is never momentarily world-readable
    // (rename preserves the source's permissions) and a crash between the two
    // steps can't leave a 644 secrets file behind.
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', tmp.path]);
      } catch (e) {
        dev.log('FileCredentialStore: chmod failed for $_filePath — $e');
      }
    }
    await tmp.rename(_filePath);
  }

  // Each operation appends to the chain so we never read a half-written file.
  Future<T> _serialised<T>(Future<T> Function() body) {
    final next = _chain.then((_) => body());
    _chain = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<String?> read({required String key}) =>
      _serialised(() async => (await _load())[key]);

  @override
  Future<void> write({required String key, required String? value}) =>
      _serialised(() async {
        final m = await _load();
        if (value == null) {
          m.remove(key);
        } else {
          m[key] = value;
        }
        await _persist();
      });

  @override
  Future<void> delete({required String key}) =>
      _serialised(() async {
        final m = await _load();
        m.remove(key);
        await _persist();
      });

  @override
  Future<void> deleteAll() => _serialised(() async {
        _cache = <String, String>{};
        await _persist();
      });
}

/// Tries [primary] first; on a keychain entitlement / missing-credential
/// error, switches permanently to [fallback] for the rest of the session and
/// logs once so the failure is visible in `log stream`.
///
/// This is specifically built for the macOS Keychain `-34018
/// errSecMissingEntitlement` case but treats any `PlatformException` from
/// `flutter_secure_storage` the same way — if the keychain can't be used,
/// the user shouldn't be locked out of saving their server.
class FallbackCredentialStore implements CredentialStore {
  FallbackCredentialStore({required this.primary, required this.fallback});
  final CredentialStore primary;
  final CredentialStore fallback;

  bool _primaryDead = false;

  void _markDead(Object error) {
    if (_primaryDead) return;
    _primaryDead = true;
    dev.log(
        'CredentialStore: primary (keychain) unavailable — switching to file '
        'backend for this session. Cause: $error');
  }

  Future<T> _withFallback<T>(
    Future<T> Function(CredentialStore s) op,
  ) async {
    if (_primaryDead) return op(fallback);
    try {
      return await op(primary);
    } on PlatformException catch (e) {
      _markDead(e);
      return op(fallback);
    } on MissingPluginException catch (e) {
      _markDead(e);
      return op(fallback);
    }
  }

  @override
  Future<String?> read({required String key}) =>
      _withFallback((s) => s.read(key: key));

  @override
  Future<void> write({required String key, required String? value}) =>
      _withFallback((s) => s.write(key: key, value: value));

  @override
  Future<void> delete({required String key}) =>
      _withFallback((s) => s.delete(key: key));

  @override
  Future<void> deleteAll() async {
    // Wipe both so a "reset" really resets, regardless of which backend
    // happens to be active right now.
    try {
      await primary.deleteAll();
    } catch (e) {
      dev.log('CredentialStore: primary.deleteAll failed — $e');
    }
    try {
      await fallback.deleteAll();
    } catch (e) {
      dev.log('CredentialStore: fallback.deleteAll failed — $e');
    }
  }
}

/// Default factory used by the provider. Combines the platform keychain with
/// a file in the app-support directory so credentials survive keychain quirks.
CredentialStore buildDefaultCredentialStore(String appSupportDir) {
  return FallbackCredentialStore(
    primary: KeychainCredentialStore(const FlutterSecureStorage()),
    fallback: FileCredentialStore(p.join(appSupportDir, 'credentials.json')),
  );
}
