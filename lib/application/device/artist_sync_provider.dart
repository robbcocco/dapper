import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/transfer_task.dart';
import '../library/library_notifier.dart';
import '../providers/providers.dart';
import '../transfer/device_manifest.dart';
import 'device_settings_notifier.dart';

enum ArtistSyncStatus { full, partial }

/// Computes device sync status for every artist in the library.
/// Returned as a map of artistId → status; absent means not on device.
///
/// Runs as a FutureProvider so the filesystem scan executes in a background
/// isolate, keeping the UI thread free even on slow USB/SD-card devices where
/// directory listing can take tens of milliseconds per call.
///
/// A 500 ms delay before scanning acts as a debounce: parallel downloads that
/// complete within 500 ms of each other collapse into a single scan.
final artistSyncProvider = FutureProvider<Map<String, ArtistSyncStatus>>((ref) async {
  final device = ref.watch(selectedDeviceProvider);
  if (device == null) return {};

  final settings = ref.watch(deviceSettingsProvider(device.path));
  final artists = ref.watch(artistsProvider).valueOrNull ?? [];
  if (artists.isEmpty) return {};

  // Recompute whenever a transfer to this device completes.
  ref.watch(transferQueueProvider.select(
    (q) => q
        .where((t) =>
            t.devicePath == device.path &&
            t.status == TransferStatus.completed)
        .length,
  ));

  // Build folderPath → songCount from loaded albums so we can verify "full".
  final loadedAlbums = ref.watch(allAlbumsProvider).albums;
  final folderSongCount = <String, int>{};
  for (final album in loadedAlbums) {
    final folder = _albumFolder(album.artist, album.name, album.year, settings);
    if (folder != null) folderSongCount[folder] = album.songCount;
  }

  // Debounce: Riverpod restarts this computation each time a dependency
  // changes, so rapid completions from parallel downloads only trigger one
  // scan after 500 ms of quiet instead of one scan per completion.
  await Future.delayed(const Duration(milliseconds: 500));

  // Snapshot all data before handing off to the isolate.
  final root = settings.resolvedMusicRoot;
  final folderStructure = settings.folderStructure;
  final artistData = artists
      .map((a) => (id: a.id, name: a.name, albumCount: a.albumCount))
      .toList();
  final songCountSnapshot = Map<String, int>.from(folderSongCount);

  return Isolate.run(() => _runScan(
        root: root,
        folderStructure: folderStructure,
        artists: artistData,
        folderSongCount: songCountSnapshot,
      ));
});

/// Synchronous filesystem scan — runs in a background isolate.
Map<String, ArtistSyncStatus> _runScan({
  required String root,
  required FolderStructure folderStructure,
  required List<({String id, String name, int albumCount})> artists,
  required Map<String, int> folderSongCount,
}) {
  final result = <String, ArtistSyncStatus>{};

  switch (folderStructure) {
    case FolderStructure.artistAlbum:
    case FolderStructure.artistAlbumYear:
      for (final artist in artists) {
        final artistDir =
            Directory(p.join(root, artist.name.toSafeFilename()));
        if (!artistDir.existsSync()) continue;

        int greenCount = 0;
        int anyCount = 0;

        for (final sub in artistDir.listSync().whereType<Directory>()) {
          final manifest = readManifest(sub.path);
          final audioFiles =
              sub.listSync().whereType<File>().where(isAudioFile).toList();
          final count =
              manifest != null ? manifest.songs.length : audioFiles.length;
          if (count == 0) continue;
          anyCount++;

          // Prefer expectedSongCount baked into the manifest (written at
          // transfer time), then fall back to the paginated album cache.
          final expected =
              manifest?.expectedSongCount ?? folderSongCount[sub.path];

          if (expected != null) {
            if (count >= expected) greenCount++;
          } else if (manifest != null && manifest.songs.isNotEmpty) {
            if (manifest.songs.length >= audioFiles.length) greenCount++;
          }
        }

        if (anyCount == 0) continue;
        if (greenCount >= artist.albumCount && artist.albumCount > 0) {
          result[artist.id] = ArtistSyncStatus.full;
        } else {
          result[artist.id] = ArtistSyncStatus.partial;
        }
      }

    case FolderStructure.artistOnly:
      for (final artist in artists) {
        final artistDir =
            Directory(p.join(root, artist.name.toSafeFilename()));
        if (!artistDir.existsSync()) continue;
        if (artistDir.listSync().any((e) => e is File)) {
          result[artist.id] = ArtistSyncStatus.partial;
        }
      }

    case FolderStructure.flat:
    case FolderStructure.custom:
      // Custom templates can route songs anywhere; no reliable artist-folder
      // shortcut. Sync status falls back to the per-album manifest scan
      // performed by the regular albumSyncOnDevice path.
      break;
  }

  return result;
}

String? _albumFolder(
    String? albumArtist, String albumName, int? year, DeviceSettings settings) {
  if (settings.folderStructure == FolderStructure.flat ||
      settings.folderStructure == FolderStructure.artistOnly) {
    return null;
  }
  final artist = (albumArtist ?? 'Unknown Artist').toSafeFilename();
  final rawAlbum = albumName.toSafeFilename();
  final forceYear = settings.folderStructure == FolderStructure.artistAlbumYear;
  final addYear =
      (forceYear || settings.includeYear) && year != null && year > 0;
  final albumFolder = addYear ? '$year - $rawAlbum' : rawAlbum;
  return p.join(settings.resolvedMusicRoot, artist, albumFolder);
}
