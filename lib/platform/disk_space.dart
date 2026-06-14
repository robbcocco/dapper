import 'dart:developer' as dev;
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Best-effort free-space query for the volume containing [path].
///
/// Returns the number of bytes free to the calling process, or null when the
/// platform-specific query fails (unsupported OS, missing path, permission
/// error). Callers should treat null as "skip the precheck" rather than
/// "device is full".
Future<int?> freeBytesAt(String path) async {
  try {
    if (Platform.isMacOS || Platform.isLinux) {
      return await _freeBytesDf(path);
    }
    if (Platform.isWindows) {
      return _freeBytesWindows(path);
    }
  } catch (e) {
    dev.log('freeBytesAt: failed for $path — $e');
  }
  return null;
}

Future<int?> _freeBytesDf(String path) async {
  final result = await Process.run('df', ['-k', path]);
  if (result.exitCode != 0) return null;
  return parseDfOutput(result.stdout as String);
}

/// Parses `df -k` stdout, locating the "Available" column by header rather
/// than positional offset. macOS adds iused/ifree/%iused columns that shifted
/// a naive "from-end" index onto `ifree` — which is 0 on FAT32/exFAT (no
/// inodes), producing a false "device full" report on every SD card / DAP.
///
/// Returns bytes available, or null when the output is malformed or missing
/// an "Available" / "Avail" header.
int? parseDfOutput(String stdout) {
  final lines = stdout.trim().split('\n');
  if (lines.length < 2) return null;

  final headerCols = lines.first.split(RegExp(r'\s+'));
  var availIdx = -1;
  for (var i = 0; i < headerCols.length; i++) {
    final lower = headerCols[i].toLowerCase();
    if (lower == 'available' || lower == 'avail') {
      availIdx = i;
      break;
    }
  }
  if (availIdx < 0) return null;

  final dataCols = lines.last.split(RegExp(r'\s+'));
  if (dataCols.length <= availIdx) return null;
  final available = int.tryParse(dataCols[availIdx]);
  if (available == null) return null;
  return available * 1024;
}

/// Windows: GetDiskFreeSpaceExW(path, freeToCaller, totalBytes, totalFree).
int? _freeBytesWindows(String path) {
  final pathPtr = path.toNativeUtf16();
  final freeToCaller = calloc<Uint64>();
  final totalBytes = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  try {
    final result = GetDiskFreeSpaceEx(
        PCWSTR(pathPtr), freeToCaller, totalBytes, totalFree);
    if (!result.value) return null;
    return freeToCaller.value;
  } finally {
    calloc.free(pathPtr);
    calloc.free(freeToCaller);
    calloc.free(totalBytes);
    calloc.free(totalFree);
  }
}
