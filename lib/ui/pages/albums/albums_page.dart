import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/device_settings_notifier.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/album.dart';
import '../../../domain/models/artist.dart';
import '../../../domain/models/connected_device.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/sync_dot.dart';
import 'album_detail_page.dart';
import 'album_info_dialog.dart';

enum AlbumsPageMode { recent, all }

class AlbumsPage extends ConsumerWidget {
  const AlbumsPage({super.key, required this.mode});

  final AlbumsPageMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Album detail takes highest priority.
    final selectedAlbumId = ref.watch(selectedAlbumIdProvider);
    if (selectedAlbumId != null) {
      return AlbumDetailPage(albumId: selectedAlbumId);
    }

    // Artist drill-down only applies in the "all albums" section.
    final selectedArtistId = ref.watch(selectedArtistIdProvider);
    if (mode == AlbumsPageMode.all && selectedArtistId != null) {
      return _ArtistAlbumsView(artistId: selectedArtistId);
    }

    if (mode == AlbumsPageMode.recent) {
      final albums = ref.watch(recentAlbumsProvider);
      return albums.when(
        data: (list) => _AlbumGrid(albums: list),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(recentAlbumsProvider),
        ),
      );
    }

    // All albums — paginated.
    return const _AllAlbumsView();
  }
}

// ── Artist drill-down ─────────────────────────────────────────────────────────

class _ArtistAlbumsView extends ConsumerWidget {
  const _ArtistAlbumsView({required this.artistId});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = ref
        .watch(artistsProvider)
        .valueOrNull
        ?.fold<Artist?>(null, (prev, a) => a.id == artistId ? a : prev);

    final albums = ref.watch(albumsByArtistProvider(artistId));
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header ──────────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 24, 16),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ColorTokens.divider))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                onPressed: () =>
                    ref.read(selectedArtistIdProvider.notifier).state = null,
                color: ColorTokens.textSecondary,
                tooltip: 'All Albums',
              ),
              const SizedBox(width: 8),
              if (artist != null) ...[
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CoverArtImage(
                    coverArtId: artist.coverArtId,
                    size: AppConstants.gridCoverArtSize,
                    borderRadius: 40,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artist.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: ColorTokens.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${artist.albumCount} album${artist.albumCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 12, color: ColorTokens.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(playbackProvider.notifier)
                              .playArtist(artist.id),
                          icon: const Icon(Icons.play_arrow, size: 15),
                          label: const Text('Play All'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ColorTokens.surfaceVariant,
                            foregroundColor: ColorTokens.textPrimary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (devices.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () => _pickAndTransferAll(
                                context, ref, artist.id, devices),
                            icon: const Icon(Icons.download, size: 15),
                            label: const Text('Transfer All'),
                            style: FilledButton.styleFrom(
                              backgroundColor: ColorTokens.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Albums grid ─────────────────────────────────────────────────────────
        Expanded(
          child: albums.when(
            data: (list) => list.isEmpty
                ? const Center(
                    child: Text('No albums',
                        style: TextStyle(color: ColorTokens.textSecondary)))
                : _AlbumGrid(albums: list),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () => ref.invalidate(albumsByArtistProvider(artistId)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndTransferAll(
    BuildContext context,
    WidgetRef ref,
    String artistId,
    List<ConnectedDevice> devices,
  ) async {
    final devicePath = await _pickDevicePath(context, devices);
    if (devicePath == null) return;
    await _transferAll(ref, devicePath, artistId);
  }

  Future<void> _transferAll(WidgetRef ref, String devicePath, String artistId) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final settings = ref.read(deviceSettingsProvider(devicePath));
    final useZip = settings.useZipDownload && !settings.isTranscoding;
    final albums = await repo.getAlbumsByArtist(artistId);
    final queue = ref.read(transferQueueProvider.notifier);
    if (useZip) {
      for (final album in albums) {
        final full = await repo.getAlbum(album.id);
        if (full.songs.isEmpty) continue;
        queue.enqueueZipGroup(full.id, full.songs, devicePath);
      }
      return;
    }
    final allSongs = <Song>[];
    final expectedCounts = <String, int>{};
    for (final album in albums) {
      final full = await repo.getAlbum(album.id);
      allSongs.addAll(full.songs);
      final folder = buildAlbumFolder(album.artist, album.name, album.year, settings);
      if (folder != null) expectedCounts[folder] = full.songCount;
    }
    if (allSongs.isEmpty) return;
    queue.enqueue(allSongs, devicePath,
        expectedAlbumSongCounts: expectedCounts);
  }
}

// ── All albums with infinite scroll ──────────────────────────────────────────

class _AllAlbumsView extends ConsumerStatefulWidget {
  const _AllAlbumsView();

  @override
  ConsumerState<_AllAlbumsView> createState() => _AllAlbumsViewState();
}

class _AllAlbumsViewState extends ConsumerState<_AllAlbumsView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      ref.read(allAlbumsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(allAlbumsProvider);

    if (s.isLoading && s.albums.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.error != null && s.albums.isEmpty) {
      return ErrorRetry(
        error: s.error!,
        onRetry: () => ref.read(allAlbumsProvider.notifier).refresh(),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: AppConstants.albumCardSize + 16,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _AlbumCard(album: s.albums[i]),
              childCount: s.albums.length,
            ),
          ),
        ),
        if (s.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        const SliverToBoxAdapter(
            child: SizedBox(height: AppConstants.scrollBottomInset)),
      ],
    );
  }
}

// ── Static album grid (recent / artist views) ─────────────────────────────────

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.albums});

  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: AppConstants.albumCardSize + 16,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _AlbumCard(album: albums[i]),
              childCount: albums.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(
            child: SizedBox(height: AppConstants.scrollBottomInset)),
      ],
    );
  }
}

// ── Album card ────────────────────────────────────────────────────────────────

class _AlbumCard extends ConsumerWidget {
  const _AlbumCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    final albumSync = settings != null
        ? albumSyncOnDevice(album.artist, album.name, album.year, album.songCount, settings)
        : AlbumSyncStatus.absent;
    // Watch only this album's transfer status. Without .select() every status
    // change anywhere in the queue rebuilds every visible album card (and
    // re-runs albumSyncOnDevice on each).
    final (isActive, isQueued) = ref.watch(
      transferQueueProvider.select((q) {
        var active = false;
        var queued = false;
        for (final t in q) {
          if (t.song.albumId != album.id) continue;
          if (t.status == TransferStatus.inProgress) {
            active = true;
            break;
          }
          if (t.status == TransferStatus.queued) queued = true;
        }
        return (active, !active && queued);
      }),
    );
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];

    return GestureDetector(
      onTap: () =>
          ref.read(selectedAlbumIdProvider.notifier).state = album.id,
      onSecondaryTapUp: (d) => _showMenu(context, ref, devices, d.globalPosition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CoverArtImage(
                    coverArtId: album.coverArtId,
                    size: AppConstants.gridCoverArtSize,
                    borderRadius: 6,
                  ),
                ),
                if (isActive || isQueued)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: SyncDot(
                      color: Colors.blue.withValues(alpha: 0.85),
                      pulse: isActive,
                      size: 10,
                    ),
                  )
                else if (albumSync == AlbumSyncStatus.full)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: SyncDot(
                      color: Colors.green.withValues(alpha: 0.85),
                      size: 10,
                    ),
                  )
                else if (albumSync == AlbumSyncStatus.partial)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: SyncDot(
                      color: Colors.orange.withValues(alpha: 0.85),
                      size: 10,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: ColorTokens.textPrimary,
            ),
          ),
          if (album.artist != null)
            Text(
              album.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: ColorTokens.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  void _showMenu(
    BuildContext context,
    WidgetRef ref,
    List<ConnectedDevice> devices,
    Offset pos,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: ColorTokens.surface,
      items: [
        const PopupMenuItem(
          value: 'open',
          child: _CardMenuItem(icon: Icons.album_outlined, label: 'Open Album'),
        ),
        for (final d in devices)
          PopupMenuItem(
            value: 'transfer:${d.path}',
            child: _CardMenuItem(
                icon: Icons.download,
                label: devices.length == 1
                    ? 'Transfer Album'
                    : 'Transfer to ${d.label}'),
          ),
        const PopupMenuItem(
          value: 'playlist',
          child: _CardMenuItem(icon: Icons.playlist_add, label: 'Add to Playlist'),
        ),
        const PopupMenuItem(
          value: 'info',
          child: _CardMenuItem(icon: Icons.info_outline, label: 'Get Info'),
        ),
      ],
    );
    if (!context.mounted) return;

    if (result == 'open') {
      ref.read(selectedAlbumIdProvider.notifier).state = album.id;
      return;
    }

    if (result == 'info') {
      final full = await ref.read(albumProvider(album.id).future);
      if (full == null || !context.mounted) return;
      unawaited(AlbumInfoDialog.show(context, full));
      return;
    }

    if (result != null && result.startsWith('transfer:')) {
      final devicePath = result.substring(9);
      final full = await ref.read(albumProvider(album.id).future);
      if (full == null || !context.mounted) return;
      final repo = ref.read(libraryRepositoryProvider);
      if (repo == null) return;
      final settings = ref.read(deviceSettingsProvider(devicePath));
      final queue = ref.read(transferQueueProvider.notifier);
      if (settings.useZipDownload && !settings.isTranscoding) {
        queue.enqueueZipGroup(full.id, full.songs, devicePath);
      } else {
        final folder = buildAlbumFolder(
            album.artist, album.name, album.year, settings);
        final expectedCounts =
            folder != null ? {folder: full.songCount} : null;
        queue.enqueue(full.songs, devicePath,
            expectedAlbumSongCounts: expectedCounts);
      }
    } else if (result == 'playlist') {
      final full = await ref.read(albumProvider(album.id).future);
      if (full == null || !context.mounted) return;
      unawaited(showAddToPlaylistDialog(
          context, ref, full.songs.map((s) => s.id).toList()));
    }
  }
}

// Returns the chosen device path, or null if cancelled / no devices.
// Shows a picker dialog when multiple devices are connected.
Future<String?> _pickDevicePath(
  BuildContext context,
  List<ConnectedDevice> devices,
) async {
  if (devices.isEmpty) return null;
  if (devices.length == 1) return devices.first.path;
  final result = await showDialog<ConnectedDevice>(
    context: context,
    builder: (_) => SimpleDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Choose device',
          style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
      children: devices
          .map((d) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, d),
                child: Text(d.label,
                    style: const TextStyle(
                        color: ColorTokens.textPrimary, fontSize: 13)),
              ))
          .toList(),
    ),
  );
  return result?.path;
}

class _CardMenuItem extends StatelessWidget {
  const _CardMenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ColorTokens.textPrimary),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: ColorTokens.textPrimary)),
      ],
    );
  }
}
