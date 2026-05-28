import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/device_settings.dart';
import '../library/library_notifier.dart';
import '../providers/providers.dart';
import '../transfer/transfer_path_resolver.dart';
import 'device_settings_notifier.dart';

enum ArtistSyncStatus { full, partial }

/// Computes device sync status for every artist in the library.
/// Returned as a map of artistId → status; absent means not on device.
/// Runs in a Riverpod [Provider] so it is memoized and only recomputed
/// when device settings, the album list, or the artist list change —
/// never on unrelated widget rebuilds.
final artistSyncProvider = Provider<Map<String, ArtistSyncStatus>>((ref) {
  final device = ref.watch(selectedDeviceProvider);
  if (device == null) return {};

  final settings = ref.watch(deviceSettingsProvider(device.path));
  final artists = ref.watch(artistsProvider).valueOrNull ?? [];
  final loadedAlbums = ref.watch(allAlbumsProvider).albums;

  if (loadedAlbums.isEmpty) return {};

  final result = <String, ArtistSyncStatus>{};

  switch (settings.folderStructure) {
    case FolderStructure.artistAlbum:
    case FolderStructure.artistAlbumYear:
      final albumCount = {for (final a in artists) a.id: a.albumCount};
      final byArtist = <String, List<dynamic>>{};
      for (final album in loadedAlbums) {
        if (album.artistId != null) {
          (byArtist[album.artistId!] ??= []).add(album);
        }
      }
      for (final entry in byArtist.entries) {
        final expected = albumCount[entry.key] ?? 0;
        final onDevice = entry.value
            .where((a) => albumExistsOnDevice(a.artist, a.name, a.year, settings))
            .length;
        if (onDevice == expected && expected > 0) {
          result[entry.key] = ArtistSyncStatus.full;
        } else if (onDevice > 0) {
          result[entry.key] = ArtistSyncStatus.partial;
        }
      }

    case FolderStructure.artistOnly:
      for (final artist in artists) {
        if (artistFolderExistsOnDevice(artist.name, settings)) {
          result[artist.id] = ArtistSyncStatus.partial;
        }
      }

    case FolderStructure.flat:
      break; // No per-artist folder, no dots.
  }

  return result;
});
