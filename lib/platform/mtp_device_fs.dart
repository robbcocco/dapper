import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../domain/models/device_settings.dart';
import 'device_fs.dart';
import 'mtp_client.dart';

/// MTP-backed [DeviceFs].
///
/// MTP devices have no path namespace; objects are identified by 32-bit ints.
/// This impl caches path↔objectId so the caller can continue to use
/// path strings everywhere (e.g. `mtp://<id>/Music/Artist/Album/01.flac`).
///
/// Per-device session is single-threaded. A [_putMutex] serialises in-flight
/// writes so the native side never sees overlapping `putBegin`/`putChunk`
/// pairs for the same device.
///
/// `devicePath` is `"mtp://<deviceId>"`. Methods that take a path strip the
/// scheme + device-id prefix to get the synthetic absolute path used by the
/// path↔objectId cache.
///
/// **Concurrency cap**: MTP forces 1 in-flight write per device. The
/// transfer engine reads this via [maxConcurrentTransfers].
///
/// **Atomicity**: MTP has no rename. [openAtomicReplace] deletes any
/// existing object at the target path before opening a new write — the best
/// approximation available. Callers tolerant of a brief absence (manifests)
/// are fine; anything that strictly requires atomicity over MTP needs a
/// different design.
class MtpDeviceFs implements DeviceFs {
  MtpDeviceFs({
    required MtpClient client,
    required this.devicePath,
    // ignore: prefer_initializing_formals — field is private, public param is named.
  }) : _client = client {
    final scheme = '$_kScheme://';
    if (!devicePath.startsWith(scheme)) {
      throw ArgumentError(
          'MtpDeviceFs devicePath must start with $scheme — got $devicePath');
    }
    _deviceId = devicePath.substring(scheme.length);
  }

  static const String _kScheme = 'mtp';

  final MtpClient _client;
  final String devicePath;
  late final String _deviceId;

  /// Path → objectId. Built lazily by [_resolve].
  /// Root (`"/"`) is special-cased to id 0.
  final Map<String, int> _objectIdByPath = {'/': 0};
  final _putMutex = _Mutex();
  bool _disposed = false;
  bool _sessionOpen = false;

  @override
  DeviceProtocol get protocol => DeviceProtocol.mtp;

  @override
  int get maxConcurrentTransfers => 1;

  // ── Public API ──────────────────────────────────────────────────────────

  @override
  Future<bool> exists(String path) async {
    final norm = _strip(path);
    if (norm == '/') return true;
    if (_objectIdByPath.containsKey(norm)) return true;
    final id = await _resolve(norm);
    return id != null;
  }

  @override
  Future<bool> isDir(String path) async {
    final norm = _strip(path);
    if (norm == '/') return true;
    final parent = p.posix.dirname(norm);
    final name = p.posix.basename(norm);
    await _ensureSession();
    final parentId = await _resolve(parent);
    if (parentId == null) return false;
    try {
      final children = await _client.list(_deviceId, parentId);
      final hit = children.where((o) => o.name == name).firstOrNull;
      return hit?.isDir ?? false;
    } catch (e) {
      dev.log('MtpDeviceFs.isDir: $path failed — $e');
      return false;
    }
  }

  @override
  Future<int?> sizeOf(String path) async {
    final norm = _strip(path);
    final parent = p.posix.dirname(norm);
    final name = p.posix.basename(norm);
    await _ensureSession();
    final parentId = await _resolve(parent);
    if (parentId == null) return null;
    try {
      final children = await _client.list(_deviceId, parentId);
      final hit = children.where((o) => o.name == name).firstOrNull;
      return hit?.size;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> mkdirp(String dir) async {
    final norm = _strip(dir);
    if (norm == '/') return;
    await _ensureSession();
    final parts = norm.split('/').where((s) => s.isNotEmpty).toList();
    var parentId = 0;
    var soFar = '';
    for (final part in parts) {
      soFar = '$soFar/$part';
      final cached = _objectIdByPath[soFar];
      if (cached != null) {
        parentId = cached;
        continue;
      }
      try {
        final children = await _client.list(_deviceId, parentId);
        final hit = children.where((o) => o.name == part).firstOrNull;
        if (hit != null) {
          parentId = hit.objectId;
          _objectIdByPath[soFar] = parentId;
          continue;
        }
        parentId = await _client.mkdir(_deviceId, parentId, part);
        _objectIdByPath[soFar] = parentId;
      } catch (e) {
        dev.log('MtpDeviceFs.mkdirp: $dir failed at $soFar — $e');
        rethrow;
      }
    }
  }

  @override
  Future<List<DeviceFsEntry>> list(String dir) async {
    final norm = _strip(dir);
    await _ensureSession();
    final dirId = await _resolve(norm);
    if (dirId == null) return const [];
    try {
      final children = await _client.list(_deviceId, dirId);
      final out = <DeviceFsEntry>[];
      for (final c in children) {
        final childPath = norm == '/' ? '/${c.name}' : '$norm/${c.name}';
        _objectIdByPath[childPath] = c.objectId;
        out.add(DeviceFsEntry(
          path: '$_kScheme://$_deviceId$childPath',
          isDir: c.isDir,
          size: c.size,
          modified: c.modifiedMillis != null
              ? DateTime.fromMillisecondsSinceEpoch(c.modifiedMillis!)
              : null,
        ));
      }
      return out;
    } catch (e) {
      dev.log('MtpDeviceFs.list: $dir failed — $e');
      return const [];
    }
  }

  @override
  Future<void> delete(String path) async {
    final norm = _strip(path);
    await _ensureSession();
    final id = await _resolve(norm);
    if (id == null) return;
    try {
      await _client.delete(_deviceId, id);
    } finally {
      _invalidatePath(norm);
    }
  }

  @override
  Future<void> deleteRecursive(String dir) async {
    // MTP delete on a folder removes it + contents (per WPD; libmtp varies).
    // For libmtp builds that don't recurse, the native side will walk.
    await delete(dir);
  }

  @override
  Future<WriteHandle> openWrite(String path, {int? totalBytes}) async {
    final norm = _strip(path);
    final parent = p.posix.dirname(norm);
    final name = p.posix.basename(norm);
    await _ensureSession();
    await mkdirp('$_kScheme://$_deviceId$parent');
    final parentId = await _resolve(parent);
    if (parentId == null) {
      throw StateError('MtpDeviceFs.openWrite: parent missing — $parent');
    }
    await _putMutex.acquire();
    try {
      final streamId = await _client.putBegin(
        deviceId: _deviceId,
        parentObjectId: parentId,
        name: name,
        totalBytes: totalBytes ?? 0,
      );
      return _MtpWriteHandle(
        client: _client,
        streamId: streamId,
        targetPath: norm,
        onCommit: (objectId) {
          _objectIdByPath[norm] = objectId;
          _putMutex.release();
        },
        onAbort: () {
          _invalidatePath(norm);
          _putMutex.release();
        },
      );
    } catch (e) {
      _putMutex.release();
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> openRead(String path) async {
    final norm = _strip(path);
    await _ensureSession();
    final id = await _resolve(norm);
    if (id == null) {
      throw StateError('MtpDeviceFs.openRead: missing $path');
    }
    final streamId = await _client.getBegin(_deviceId, id);
    return _readStream(streamId);
  }

  Stream<List<int>> _readStream(String streamId) async* {
    try {
      while (true) {
        final chunk = await _client.getChunk(streamId, 64 * 1024);
        if (chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await _client.getEnd(streamId);
    }
  }

  @override
  Future<WriteHandle> openAtomicReplace(String path, {int? totalBytes}) async {
    final norm = _strip(path);
    final existing = await _resolve(norm);
    if (existing != null) {
      try {
        await _client.delete(_deviceId, existing);
      } catch (_) {/* fall through; openWrite may still succeed */}
      _invalidatePath(norm);
    }
    return openWrite(path, totalBytes: totalBytes);
  }

  @override
  Future<void> truncate(String path) async {
    final norm = _strip(path);
    final existing = await _resolve(norm);
    if (existing != null) {
      try {
        await _client.delete(_deviceId, existing);
      } catch (_) {}
      _invalidatePath(norm);
    }
    // Create an empty object so the inode-equivalent reappears for devices
    // that re-open the same path on next session.
    final handle = await openWrite(path, totalBytes: 0);
    await handle.write(const <int>[]);
    await handle.close();
  }

  /// MTP devices materialise no AppleDouble sidecars. No-op.
  @override
  Future<void> removeSidecar(String filePath) async {}

  @override
  Future<int?> freeBytes() async {
    try {
      return await _client.freeSpace(_deviceId);
    } catch (_) {
      return null;
    }
  }

  /// MTP paths use forward-slash POSIX joining inside the synthetic
  /// device-id-scoped namespace. The `mtp://<id>` prefix is preserved so
  /// the result can be passed back into other DeviceFs methods.
  @override
  String resolveMusicRoot(DeviceSettings settings) {
    final trimmed = settings.musicRootFolder.trim();
    if (trimmed.isEmpty) return settings.devicePath;
    final parts = trimmed
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (parts.isEmpty) return settings.devicePath;
    return '${settings.devicePath}/${parts.join('/')}';
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_sessionOpen) {
      try {
        await _client.closeSession(_deviceId);
      } catch (_) {}
      _sessionOpen = false;
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<void> _ensureSession() async {
    if (_sessionOpen || _disposed) return;
    await _client.openSession(_deviceId);
    _sessionOpen = true;
  }

  /// Strips `mtp://<id>` from [pathOrUri] and returns the synthetic absolute
  /// path inside the device's namespace. Always begins with `/`.
  String _strip(String pathOrUri) {
    final prefix = '$_kScheme://$_deviceId';
    var rest = pathOrUri.startsWith(prefix)
        ? pathOrUri.substring(prefix.length)
        : pathOrUri;
    if (rest.isEmpty) return '/';
    if (!rest.startsWith('/')) rest = '/$rest';
    // Normalise double slashes that creep in via callers concatenating
    // paths manually.
    rest = rest.replaceAll(RegExp('/+'), '/');
    if (rest.length > 1 && rest.endsWith('/')) {
      rest = rest.substring(0, rest.length - 1);
    }
    return rest;
  }

  Future<int?> _resolve(String path) async {
    final cached = _objectIdByPath[path];
    if (cached != null) return cached;
    if (path == '/') return 0;
    final parent = p.posix.dirname(path);
    final parentId = await _resolve(parent);
    if (parentId == null) return null;
    try {
      final children = await _client.list(_deviceId, parentId);
      for (final c in children) {
        final childPath = parent == '/' ? '/${c.name}' : '$parent/${c.name}';
        _objectIdByPath[childPath] = c.objectId;
      }
      return _objectIdByPath[path];
    } catch (e) {
      dev.log('MtpDeviceFs._resolve: $path failed — $e');
      return null;
    }
  }

  /// Drops [path] and all descendants from the cache. Cheap enough to call
  /// after any mutation — MTP devices are small enough that the cache fits
  /// in memory comfortably.
  void _invalidatePath(String path) {
    _objectIdByPath.remove(path);
    final prefix = '$path/';
    _objectIdByPath.removeWhere((k, _) => k.startsWith(prefix));
  }
}

class _MtpWriteHandle implements WriteHandle {
  _MtpWriteHandle({
    required this.client,
    required this.streamId,
    required this.targetPath,
    required this.onCommit,
    required this.onAbort,
  });

  final MtpClient client;
  final String streamId;
  final String targetPath;
  final void Function(int objectId) onCommit;
  final void Function() onAbort;
  bool _done = false;

  @override
  Future<void> write(List<int> chunk) async {
    if (_done) throw StateError('_MtpWriteHandle.write after done');
    if (chunk.isEmpty) return;
    await client.putChunk(
        streamId, chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
  }

  @override
  Future<void> close() async {
    if (_done) return;
    _done = true;
    final id = await client.putCommit(streamId);
    onCommit(id);
  }

  @override
  Future<void> abort() async {
    if (_done) return;
    _done = true;
    try {
      await client.putAbort(streamId);
    } finally {
      onAbort();
    }
  }
}

/// Single-slot mutex. Used to serialise MTP writes per device.
class _Mutex {
  Completer<void>? _pending;

  Future<void> acquire() async {
    while (_pending != null) {
      await _pending!.future;
    }
    _pending = Completer<void>();
  }

  void release() {
    final c = _pending;
    _pending = null;
    if (c != null && !c.isCompleted) c.complete();
  }
}

