import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/device_settings.dart';
import '../library/library_notifier.dart';
import '../providers/providers.dart';
import '../transfer/device_manifest.dart';
import '../transfer/transfer_path_resolver.dart';
import 'device_settings_notifier.dart';

/// Device-wide album sync status keyed by absolute album-folder path, computed
/// off the render path so album cards do an O(1) map lookup instead of
/// synchronous filesystem I/O inside build().
///
/// Uses async `File`/`Directory` APIs (which yield to the event loop) rather
/// than a background isolate: no Freezed marshalling, and the walk never blocks
/// a frame. Album cards fall back to the synchronous [albumSyncOnDevice] while
/// this map is still resolving, so behaviour is never worse — only faster once
/// it's ready.
final albumFolderSyncProvider =
    FutureProvider<Map<String, AlbumSyncStatus>>((ref) async {
  final device = ref.watch(selectedDeviceProvider);
  if (device == null) return const {};
  final settings = ref.watch(deviceSettingsProvider(device.path));

  // Only artist/album layouts produce a per-album folder to key on. Other
  // structures fall through to the card's synchronous path (which returns
  // absent for them anyway).
  if (settings.folderStructure != FolderStructure.artistAlbum &&
      settings.folderStructure != FolderStructure.artistAlbumYear) {
    return const {};
  }

  // Recompute whenever a transfer writes a manifest.
  ref.watch(manifestRevisionProvider);

  // Library album counts keyed by the folder each resolves to — the "expected"
  // fallback for manifests that predate expectedSongCount.
  final albums = ref.watch(allAlbumsProvider).albums;
  final folderExpected = <String, int>{};
  for (final a in albums) {
    final folder = buildAlbumFolder(a.artist, a.name, a.year, settings);
    if (folder != null) folderExpected[folder] = a.songCount;
  }

  // Debounce: a burst of completions collapses into a single walk.
  await Future.delayed(const Duration(milliseconds: 400));

  return _scan(settings.resolvedMusicRoot, folderExpected);
});

/// Walks `<root>/<artist>/<album>` and returns each album folder's sync status.
/// [folderExpected] supplies the library song count per folder as the fallback
/// "expected" when a manifest lacks its own count.
@visibleForTesting
Future<Map<String, AlbumSyncStatus>> scanAlbumFolders(
        String root, Map<String, int> folderExpected) =>
    _scan(root, folderExpected);

Future<Map<String, AlbumSyncStatus>> _scan(
    String root, Map<String, int> folderExpected) async {
  final result = <String, AlbumSyncStatus>{};
  final rootDir = Directory(root);
  if (!await rootDir.exists()) return result;
  try {
    await for (final artist in rootDir.list(followLinks: false)) {
      if (artist is! Directory) continue;
      try {
        await for (final albumDir in artist.list(followLinks: false)) {
          if (albumDir is! Directory) continue;
          final status = await _folderStatus(
              albumDir, folderExpected[albumDir.path]);
          if (status != null) result[albumDir.path] = status;
        }
      } catch (_) {/* permission / unplug mid-scan */}
    }
  } catch (_) {/* device pulled, etc. */}
  return result;
}

Future<AlbumSyncStatus?> _folderStatus(
    Directory folder, int? expectedFallback) async {
  final manifestFile = File(p.join(folder.path, kManifestFilename));
  if (await manifestFile.exists()) {
    try {
      final m = AlbumManifest.fromJson(
          jsonDecode(await manifestFile.readAsString())
              as Map<String, dynamic>);
      final count = m.songs.length;
      if (count == 0) return null;
      final expected = m.expectedSongCount ?? expectedFallback ?? 0;
      return (expected > 0 && count >= expected)
          ? AlbumSyncStatus.full
          : AlbumSyncStatus.partial;
    } catch (_) {/* corrupt manifest — fall back to counting files */}
  }
  var fileCount = 0;
  try {
    await for (final f in folder.list(followLinks: false)) {
      if (f is File && isAudioFile(f)) fileCount++;
    }
  } catch (_) {}
  if (fileCount == 0) return null;
  final expected = expectedFallback ?? 0;
  return (expected > 0 && fileCount >= expected)
      ? AlbumSyncStatus.full
      : AlbumSyncStatus.partial;
}
