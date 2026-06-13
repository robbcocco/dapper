import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/device_settings.dart';
import '../transfer/flac_tag_sanitizer.dart';

// One cache file per device music root. Maps relative path → mtime (ms since
// epoch) at the moment that file was last sanitised + shrunk. On subsequent
// runs the walker skips any file whose mtime hasn't moved past the cached
// value — turning a 15-minute repeat clean into a quick filesystem walk.
const _kCleanCacheFilename = '.dapper-clean.json';

// Number of files processed in flight. CPU-bound image decode + USB writes
// both prefer a small fan-out; past ~4 the gains plateau and USB write
// contention pushes wall time back up.
const _kConcurrency = 4;

class TagSanitizeResult {
  const TagSanitizeResult({
    required this.filesScanned,
    required this.filesSkipped,
    required this.filesModified,
    required this.coversShrunk,
    required this.bytesFreed,
    this.errors = const [],
  });
  final int filesScanned;
  final int filesSkipped;
  final int filesModified;
  final int coversShrunk;
  final int bytesFreed;
  final List<String> errors;
}

/// Walks the device music root and runs [sanitizeFlacTags] +
/// [shrinkFlacEmbeddedPicture] on every .flac file. Two optimisations make
/// repeat runs cheap on large libraries:
///
///  * **Mtime cache**: `.dapper-clean.json` at the music root records when
///    each file was last processed. Files whose mtime hasn't moved past the
///    cached value are skipped without opening them.
///  * **Concurrent processing**: pending files are dispatched through a
///    small semaphore so 4 files clean in parallel — main bottleneck on a
///    3 k-song scan is per-file isolate spawn + USB writes, both of which
///    benefit linearly up to about 4-way fan-out.
Future<TagSanitizeResult> sanitizeDeviceTags(
  DeviceSettings settings, {
  void Function(String)? onProgress,
}) async {
  final root = Directory(settings.resolvedMusicRoot);
  if (!root.existsSync()) {
    return const TagSanitizeResult(
      filesScanned: 0,
      filesSkipped: 0,
      filesModified: 0,
      coversShrunk: 0,
      bytesFreed: 0,
    );
  }

  // Phase 1: discover FLACs.
  onProgress?.call('Scanning device…');
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name.startsWith('._')) continue;
    if (p.extension(entity.path).toLowerCase() != '.flac') continue;
    files.add(entity);
  }

  // Phase 2: load clean cache.
  final cacheFile = File(p.join(root.path, _kCleanCacheFilename));
  final cache = <String, int>{};
  if (await cacheFile.exists()) {
    try {
      final raw = jsonDecode(await cacheFile.readAsString());
      if (raw is Map) {
        raw.forEach((k, v) {
          if (k is String && v is int) cache[k] = v;
        });
      }
    } catch (_) {}
  }

  // Phase 3: split into pending / already-clean.
  final pending = <File>[];
  for (final f in files) {
    final key = p.relative(f.path, from: root.path);
    final cached = cache[key];
    if (cached == null) {
      pending.add(f);
      continue;
    }
    final mtime = f.statSync().modified.millisecondsSinceEpoch;
    if (mtime <= cached) continue; // already cleaned
    pending.add(f);
  }

  final skipped = files.length - pending.length;
  onProgress?.call('${pending.length} files to process'
      '${skipped > 0 ? ' ($skipped cached)' : ''}…');

  var modified = 0;
  var coversShrunk = 0;
  var bytesFreed = 0;
  final errors = <String>[];

  // Phase 4: parallel process.
  final sem = _Semaphore(_kConcurrency);
  var done = 0;
  await Future.wait(pending.map((entity) => sem.run(() async {
        try {
          final tagsChanged = settings.autoCleanMetadata
              ? await sanitizeFlacTags(entity.path)
              : false;
          final sizeBefore = entity.lengthSync();
          final picShrunk = settings.autoShrinkCoverArt
              ? await shrinkFlacEmbeddedPicture(entity.path)
              : false;
          if (picShrunk) {
            coversShrunk++;
            final sizeAfter = entity.lengthSync();
            if (sizeAfter < sizeBefore) bytesFreed += sizeBefore - sizeAfter;
          }
          if (tagsChanged || picShrunk) modified++;
          final key = p.relative(entity.path, from: root.path);
          cache[key] = entity.statSync().modified.millisecondsSinceEpoch;
        } catch (e) {
          errors.add('${p.basename(entity.path)}: $e');
        } finally {
          done++;
          if (done % 25 == 0) {
            onProgress?.call('Processed $done / ${pending.length}…');
          }
        }
      })));

  // Phase 5: persist cache.
  try {
    await cacheFile.writeAsString(jsonEncode(cache), flush: true);
  } catch (e) {
    errors.add('$_kCleanCacheFilename: $e');
  }

  onProgress?.call('Done.');
  return TagSanitizeResult(
    filesScanned: files.length,
    filesSkipped: skipped,
    filesModified: modified,
    coversShrunk: coversShrunk,
    bytesFreed: bytesFreed,
    errors: errors,
  );
}

// Coroutine semaphore: gates concurrent task fan-out without bringing in a
// dependency. Dart is single-threaded inside an isolate so the shared counter
// can't race across awaits.
class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _running = 0;
  final _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= _max) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }
}
