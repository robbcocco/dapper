import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models/device_settings.dart';
import 'device_fs.dart';
import 'disk_space.dart';

/// `dart:io`-backed [DeviceFs] for mounted filesystem volumes.
///
/// Preserves the exact semantics of the pre-abstraction direct calls:
///   - [openAtomicReplace] writes to a sibling `.tmp` then renames over the
///     target (POSIX/NTFS/FAT32 atomic rename guarantee).
///   - [removeSidecar] strips macOS AppleDouble `._*` sidecars and runs
///     `xattr -c` to stop them from being recreated; no-op on other platforms.
///   - [truncate] uses `File.writeAsString('', flush: true)` so DAPs that hold
///     an append-mode handle keep working across the truncate.
class LocalDeviceFs implements DeviceFs {
  LocalDeviceFs(this._devicePath, {required this.maxConcurrentTransfers});

  final String _devicePath;

  @override
  final int maxConcurrentTransfers;

  @override
  DeviceProtocol get protocol => DeviceProtocol.filesystem;

  @override
  Future<bool> exists(String path) async {
    try {
      return await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isDir(String path) async {
    try {
      return await FileSystemEntity.type(path) == FileSystemEntityType.directory;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int?> sizeOf(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> mkdirp(String dir) async {
    await Directory(dir).create(recursive: true);
  }

  @override
  Future<List<DeviceFsEntry>> list(String dir) async {
    final out = <DeviceFsEntry>[];
    final d = Directory(dir);
    if (!await d.exists()) return out;
    try {
      await for (final entity in d.list(followLinks: false)) {
        final isDir = entity is Directory;
        int size = 0;
        DateTime? modified;
        try {
          final stat = await entity.stat();
          modified = stat.modified;
          if (!isDir) size = stat.size;
        } catch (_) {
          // Stat can fail on FUSE / network volumes; surface the entry anyway
          // so the caller doesn't lose visibility.
          size = isDir ? 0 : -1;
        }
        out.add(DeviceFsEntry(
          path: entity.path,
          isDir: isDir,
          size: size,
          modified: modified,
        ));
      }
    } catch (e) {
      dev.log('LocalDeviceFs.list: $dir failed — $e');
    }
    return out;
  }

  @override
  Future<void> delete(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete();
    } else {
      await File(path).delete();
    }
  }

  @override
  Future<void> deleteRecursive(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return;
    await d.delete(recursive: true);
  }

  @override
  Future<WriteHandle> openWrite(String path, {int? totalBytes}) async {
    final file = File(path);
    // Sink ownership transfers to the handle; it closes on close()/abort().
    // ignore: close_sinks
    final sink = file.openWrite();
    return _SinkWriteHandle(sink: sink, targetPath: path);
  }

  @override
  Future<Stream<List<int>>> openRead(String path) async {
    return File(path).openRead();
  }

  @override
  Future<WriteHandle> openAtomicReplace(String path, {int? totalBytes}) async {
    final tmpPath = '$path.tmp';
    // Sink ownership transfers to the handle; it closes on close()/abort().
    // ignore: close_sinks
    final sink = File(tmpPath).openWrite();
    return _AtomicWriteHandle(
      sink: sink,
      tmpPath: tmpPath,
      targetPath: path,
    );
  }

  @override
  Future<void> truncate(String path) async {
    try {
      await File(path).writeAsString('', flush: true);
    } catch (e) {
      dev.log('LocalDeviceFs.truncate: $path failed — $e');
    }
  }

  /// macOS sidecar removal mirrors `device_manifest.removeMacOSSidecar` from
  /// before the abstraction landed. Non-macOS platforms get a no-op.
  @override
  Future<void> removeSidecar(String filePath) async {
    if (!Platform.isMacOS) return;
    final sidecar =
        File(p.join(p.dirname(filePath), '._${p.basename(filePath)}'));
    if (await sidecar.exists()) {
      try {
        await sidecar.delete();
      } catch (e) {
        dev.log('LocalDeviceFs.removeSidecar: could not delete '
            '${sidecar.path} — $e');
      }
    }
    try {
      final result = await Process.run('xattr', ['-c', filePath]);
      if (result.exitCode != 0) {
        // Common on read-only volumes; without this the OS will recreate the
        // sidecar next time the file is read.
        dev.log('LocalDeviceFs.removeSidecar: xattr -c $filePath exited '
            '${result.exitCode}: ${result.stderr}');
      }
    } catch (e) {
      dev.log('LocalDeviceFs.removeSidecar: failed to invoke xattr on '
          '$filePath — $e');
    }
  }

  @override
  Future<int?> freeBytes() => freeBytesAt(_devicePath);

  @override
  String resolveMusicRoot(DeviceSettings settings) {
    final trimmed = settings.musicRootFolder.trim();
    if (trimmed.isEmpty) return settings.devicePath;
    final parts = p.split(trimmed.replaceAll('\\', '/'))
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (parts.isEmpty) return settings.devicePath;
    return p.joinAll([settings.devicePath, ...parts]);
  }

  @override
  Future<void> dispose() async {}
}

class _SinkWriteHandle implements WriteHandle {
  _SinkWriteHandle({required this.sink, required this.targetPath});

  final IOSink sink;
  final String targetPath;
  bool _closed = false;

  @override
  Future<void> write(List<int> chunk) async {
    sink.add(chunk);
    await sink.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await sink.flush();
    await sink.close();
  }

  @override
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    try {
      await sink.close();
    } catch (_) {}
    try {
      final f = File(targetPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

class _AtomicWriteHandle implements WriteHandle {
  _AtomicWriteHandle({
    required this.sink,
    required this.tmpPath,
    required this.targetPath,
  });

  final IOSink sink;
  final String tmpPath;
  final String targetPath;
  bool _closed = false;

  @override
  Future<void> write(List<int> chunk) async {
    sink.add(chunk);
    await sink.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await sink.flush();
    await sink.close();
    await File(tmpPath).rename(targetPath);
  }

  @override
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    try {
      await sink.close();
    } catch (_) {}
    try {
      final f = File(tmpPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Writes [text] as UTF-8 via [WriteHandle]. Convenience helper used by
/// manifest / playlist writers so callers don't repeat the open-write-close
/// dance for small text files.
Future<void> writeStringViaHandle(WriteHandle handle, String text) async {
  await handle.write(utf8.encode(text));
  await handle.close();
}
