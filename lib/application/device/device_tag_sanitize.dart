import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/device_settings.dart';
import '../transfer/flac_tag_sanitizer.dart';

class TagSanitizeResult {
  const TagSanitizeResult({
    required this.filesScanned,
    required this.filesModified,
    this.errors = const [],
  });
  final int filesScanned;
  final int filesModified;
  final List<String> errors;
}

/// Walks the device music root and runs [sanitizeFlacTags] on every .flac
/// file. Reports how many files actually had their tags rewritten. Safe to
/// re-run — sanitised files no-op on second pass.
Future<TagSanitizeResult> sanitizeDeviceTags(
  DeviceSettings settings, {
  void Function(String)? onProgress,
}) async {
  final root = Directory(settings.resolvedMusicRoot);
  if (!root.existsSync()) {
    return const TagSanitizeResult(filesScanned: 0, filesModified: 0);
  }

  var scanned = 0;
  var modified = 0;
  final errors = <String>[];

  onProgress?.call('Scanning device…');
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name.startsWith('._')) continue;
    if (p.extension(entity.path).toLowerCase() != '.flac') continue;

    scanned++;
    if (scanned % 25 == 0) {
      onProgress?.call('Scanned $scanned files, cleaned $modified…');
    }

    try {
      if (await sanitizeFlacTags(entity.path)) modified++;
    } catch (e) {
      errors.add('${p.basename(entity.path)}: $e');
    }
  }

  onProgress?.call('Done.');
  return TagSanitizeResult(
    filesScanned: scanned,
    filesModified: modified,
    errors: errors,
  );
}
