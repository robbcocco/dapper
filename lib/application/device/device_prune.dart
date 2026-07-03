import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/repositories/library_repository.dart';
import '../transfer/device_manifest.dart';

class PruneResult {
  const PruneResult({
    required this.songsRemoved,
    required this.bytesFreed,
    this.errors = const [],
  });
  final int songsRemoved;
  final int bytesFreed;
  final List<String> errors;
}

/// Removes files whose song IDs are no longer present in the library.
/// Only meaningful for Artist/Album folder structures (others lack per-album manifests).
Future<PruneResult> pruneDevice(
  DeviceSettings settings,
  LibraryRepository repo, {
  void Function(String)? onProgress,
}) async {
  if (settings.folderStructure == FolderStructure.flat ||
      settings.folderStructure == FolderStructure.artistOnly) {
    return const PruneResult(songsRemoved: 0, bytesFreed: 0);
  }

  // Phase 1: collect all song IDs currently in the library.
  onProgress?.call('Loading library…');
  final librarySongIds = <String>{};
  int offset = 0;
  while (true) {
    final songs = await repo.getAllSongs(count: 500, offset: offset);
    if (songs.isEmpty) break;
    for (final s in songs) {
      librarySongIds.add(s.id);
    }
    offset += songs.length;
    onProgress?.call('Loaded ${librarySongIds.length} songs from library…');
  }

  // Phase 2: walk device manifest folders and prune orphan entries.
  final root = settings.resolvedMusicRoot;
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) {
    return const PruneResult(songsRemoved: 0, bytesFreed: 0);
  }

  int songsRemoved = 0;
  int bytesFreed = 0;
  final errors = <String>[];

  onProgress?.call('Scanning device…');
  for (final artist in rootDir.listSync()) {
    if (artist is! Directory) continue;
    for (final sub in artist.listSync()) {
      if (sub is! Directory) continue;
      onProgress?.call('Checking ${p.basename(sub.path)}…');
      _pruneFolder(
        sub,
        librarySongIds,
        (n) => songsRemoved += n,
        (b) => bytesFreed += b,
        errors,
      );
    }
  }

  return PruneResult(
      songsRemoved: songsRemoved, bytesFreed: bytesFreed, errors: errors);
}

void _pruneFolder(
  Directory folder,
  Set<String> librarySongIds,
  void Function(int) addSongs,
  void Function(int) addBytes,
  List<String> errors,
) {
  final manifest = readManifest(folder.path);
  if (manifest == null || manifest.songs.isEmpty) return;

  final keepSongs =
      manifest.songs.where((s) => librarySongIds.contains(s.id)).toList();
  final orphans =
      manifest.songs.where((s) => !librarySongIds.contains(s.id)).toList();
  if (orphans.isEmpty) return;

  // Files spoken for by songs that remain in the library — NEVER delete these.
  // The title fallback below must not remove a kept song's file just because
  // its name resembles an orphan's title.
  final keepFilenames = keepSongs
      .map((s) => s.filename)
      .whereType<String>()
      .toSet();

  // Cache the audio-file scan: the fallback title-match path used to re-scan
  // the folder once per orphan, which was O(orphans × files). For an album
  // where every song was orphaned this turned into an obvious quadratic.
  List<File>? cachedAudioFiles;
  List<File> audioFiles() => cachedAudioFiles ??=
      folder.listSync().whereType<File>().where(isAudioFile).toList();

  for (final orphan in orphans) {
    File? target;

    if (orphan.filename != null) {
      final candidate = File(p.join(folder.path, orphan.filename));
      if (candidate.existsSync()) target = candidate;
    }

    // Fallback for legacy manifests without a recorded filename. Match on the
    // EXACT title portion (after stripping any leading track/disc number),
    // never a loose substring — otherwise orphan "Live" would delete
    // "Live at Wembley.flac". Files belonging to a kept song are excluded.
    if (target == null) {
      final safeTitle = orphan.title.toSafeFilename();
      if (safeTitle.isNotEmpty) {
        for (final f in audioFiles()) {
          if (keepFilenames.contains(p.basename(f.path))) continue;
          final titlePart =
              _titlePortion(p.basenameWithoutExtension(f.path));
          if (titlePart == safeTitle) {
            target = f;
            break;
          }
        }
      }
    }

    // Only count songs that we actually deleted from disk. A manifest entry
    // whose file is already gone (user wiped it manually, or it never made it
    // to disk) shouldn't pad the "songs removed" total because there was
    // nothing to remove.
    if (target != null && target.existsSync()) {
      try {
        addBytes(target.lengthSync());
        target.deleteSync();
        addSongs(1);
      } catch (e) {
        errors.add('${p.basename(target.path)}: $e');
      }
    }
  }

  // Preserve expectedSongCount so artist sync-status ("full" vs "partial")
  // keeps working after a prune.
  writeManifest(
    folder.path,
    AlbumManifest(
      songs: keepSongs,
      expectedSongCount: manifest.expectedSongCount,
    ),
  );
}

/// Strips a leading track/disc-number prefix ("06 ", "06 - ", "1-06 - ") from
/// a filename base so it can be compared against a bare song title.
String _titlePortion(String baseNoExt) {
  final m = RegExp(r'^\d+(?:-\d+)?(?: - | )').firstMatch(baseNoExt);
  return m != null ? baseNoExt.substring(m.end) : baseNoExt;
}
