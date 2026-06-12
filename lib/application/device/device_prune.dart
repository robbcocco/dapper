import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/repositories/library_repository.dart';
import '../../platform/device_fs.dart';
import '../transfer/device_manifest.dart';

const _kAudioExtensions = {
  '.mp3', '.flac', '.m4a', '.aac', '.ogg', '.wav',
  '.opus', '.wma', '.ape', '.aiff', '.dsf', '.dff',
};

bool _isAudioEntry(DeviceFsEntry entry) {
  final name = p.basename(entry.path);
  if (name.startsWith('._')) return false;
  return _kAudioExtensions.contains(p.extension(entry.path).toLowerCase());
}

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
  LibraryRepository repo,
  DeviceFs fs, {
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
  final root = fs.resolveMusicRoot(settings);
  if (!await fs.isDir(root)) {
    return const PruneResult(songsRemoved: 0, bytesFreed: 0);
  }

  int songsRemoved = 0;
  int bytesFreed = 0;
  final errors = <String>[];

  onProgress?.call('Scanning device…');
  for (final artist in await fs.list(root)) {
    if (!artist.isDir) continue;
    for (final sub in await fs.list(artist.path)) {
      if (!sub.isDir) continue;
      onProgress?.call('Checking ${p.basename(sub.path)}…');
      final folderResult = await _pruneFolder(sub.path, librarySongIds, fs);
      songsRemoved += folderResult.songsRemoved;
      bytesFreed += folderResult.bytesFreed;
      errors.addAll(folderResult.errors);
    }
  }

  return PruneResult(
      songsRemoved: songsRemoved, bytesFreed: bytesFreed, errors: errors);
}

Future<PruneResult> _pruneFolder(
  String folderPath,
  Set<String> librarySongIds,
  DeviceFs fs,
) async {
  final manifest = readManifest(folderPath);
  if (manifest == null || manifest.songs.isEmpty) {
    return const PruneResult(songsRemoved: 0, bytesFreed: 0);
  }

  final orphans =
      manifest.songs.where((s) => !librarySongIds.contains(s.id)).toList();
  if (orphans.isEmpty) {
    return const PruneResult(songsRemoved: 0, bytesFreed: 0);
  }

  // Cache the audio-file scan: the fallback title-match path used to re-scan
  // the folder once per orphan, which was O(orphans × files). For an album
  // where every song was orphaned this turned into an obvious quadratic.
  List<DeviceFsEntry>? cachedAudioFiles;
  Future<List<DeviceFsEntry>> audioFiles() async {
    if (cachedAudioFiles != null) return cachedAudioFiles!;
    final all = await fs.list(folderPath);
    cachedAudioFiles =
        all.where((e) => !e.isDir && _isAudioEntry(e)).toList();
    return cachedAudioFiles!;
  }

  int songsRemoved = 0;
  int bytesFreed = 0;
  final errors = <String>[];

  for (final orphan in orphans) {
    String? targetPath;

    if (orphan.filename != null) {
      final candidate = p.join(folderPath, orphan.filename);
      if (await fs.exists(candidate)) targetPath = candidate;
    }

    if (targetPath == null) {
      final safeTitle = orphan.title.toSafeFilename();
      for (final f in await audioFiles()) {
        if (p.basenameWithoutExtension(f.path).contains(safeTitle)) {
          targetPath = f.path;
          break;
        }
      }
    }

    // Only count songs that we actually deleted from disk. A manifest entry
    // whose file is already gone (user wiped it manually, or it never made it
    // to disk) shouldn't pad the "songs removed" total because there was
    // nothing to remove.
    if (targetPath != null && await fs.exists(targetPath)) {
      try {
        final size = await fs.sizeOf(targetPath) ?? 0;
        await fs.delete(targetPath);
        bytesFreed += size;
        songsRemoved++;
      } catch (e) {
        errors.add('${p.basename(targetPath)}: $e');
      }
    }
  }

  final keepSongs =
      manifest.songs.where((s) => librarySongIds.contains(s.id)).toList();
  await writeManifestAsync(
      folderPath, AlbumManifest(songs: keepSongs), fs);

  return PruneResult(
      songsRemoved: songsRemoved, bytesFreed: bytesFreed, errors: errors);
}
