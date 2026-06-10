import '../../domain/models/album.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/repositories/library_repository.dart';
import 'transfer_path_resolver.dart';

/// Summary of a library-vs-device diff. Each entry in [unsynced] is an album
/// the library knows about that is either absent or only partially synced to
/// the device.
class LibrarySyncPlan {
  const LibrarySyncPlan({
    required this.albumsScanned,
    required this.unsynced,
  });
  final int albumsScanned;
  final List<UnsyncedAlbum> unsynced;

  int get missingSongs =>
      unsynced.fold(0, (a, b) => a + b.album.songCount);
  int get missingAlbums => unsynced.length;
}

class UnsyncedAlbum {
  const UnsyncedAlbum({required this.album, required this.status});
  final Album album;
  final AlbumSyncStatus status;
}

/// Paginates `/rest/getAlbumList2` until exhausted, classifying each album
/// against the on-device manifest cache and returning every album that isn't
/// fully synced. Skips folder structures where per-album sync can't be
/// determined (flat, artistOnly) — those return an empty plan.
///
/// The manifest cache (`folderExistsCached` + `readManifest`) means the
/// per-album check is mostly RAM-cheap after the first hit; the bottleneck
/// is server pagination.
Future<LibrarySyncPlan> buildLibrarySyncPlan(
  LibraryRepository repo,
  DeviceSettings settings, {
  int pageSize = 500,
  void Function(int scanned, int totalIfKnown)? onProgress,
}) async {
  // Per-album sync state is only computable for structures that produce a
  // distinct folder per album.
  if (settings.folderStructure == FolderStructure.flat ||
      settings.folderStructure == FolderStructure.artistOnly) {
    return const LibrarySyncPlan(albumsScanned: 0, unsynced: []);
  }
  // Custom template only yields a per-album folder when it references {album}.
  if (settings.folderStructure == FolderStructure.custom &&
      !settings.customFolderTemplate.contains('{album}')) {
    return const LibrarySyncPlan(albumsScanned: 0, unsynced: []);
  }

  final unsynced = <UnsyncedAlbum>[];
  var offset = 0;
  var scanned = 0;
  while (true) {
    final page = await repo.getAllAlbums(size: pageSize, offset: offset);
    if (page.isEmpty) break;
    for (final album in page) {
      scanned++;
      final status = albumSyncOnDevice(
        album.artist,
        album.name,
        album.year,
        album.songCount,
        settings,
      );
      if (status != AlbumSyncStatus.full) {
        unsynced.add(UnsyncedAlbum(album: album, status: status));
      }
    }
    onProgress?.call(scanned, -1);
    if (page.length < pageSize) break;
    offset += pageSize;
  }
  return LibrarySyncPlan(albumsScanned: scanned, unsynced: unsynced);
}
