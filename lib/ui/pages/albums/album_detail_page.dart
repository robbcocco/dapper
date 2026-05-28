import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../application/device/device_settings_notifier.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/album.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/song_row.dart';
import '../../widgets/sync_dot.dart';
import 'album_info_dialog.dart';

class AlbumDetailPage extends ConsumerWidget {
  const AlbumDetailPage({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumProvider(albumId));

    return album.when(
      data: (a) {
        if (a == null) return const SizedBox.shrink();
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _AlbumHeader(
                album: a,
                onBack: () =>
                    ref.read(selectedAlbumIdProvider.notifier).state = null,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _AlbumSongRow(
                  song: a.songs[i],
                  allSongs: a.songs,
                  index: i,
                ),
                childCount: a.songs.length,
              ),
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: AppConstants.scrollBottomInset)),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

// ── Album header ──────────────────────────────────────────────────────────────

class _AlbumHeader extends ConsumerWidget {
  const _AlbumHeader({required this.album, required this.onBack});

  final Album album;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];
    final songs = album.songs;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            onPressed: onBack,
            color: ColorTokens.textSecondary,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            height: 120,
            child: CoverArtImage(
                coverArtId: album.coverArtId, size: 240, borderRadius: 8),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ColorTokens.textPrimary,
                  ),
                ),
                if (album.artist != null)
                  Text(album.artist!,
                      style: const TextStyle(
                          fontSize: 14, color: ColorTokens.accent)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (album.year != null) '${album.year}',
                    '${album.songCount} songs',
                  ].join(' · '),
                  style: const TextStyle(
                      fontSize: 12, color: ColorTokens.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Play button
                    if (songs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilledButton.icon(
                          onPressed: () => ref
                              .read(playbackProvider.notifier)
                              .playSong(songs.first,
                                  queue: songs, index: 0),
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Play'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ColorTokens.surfaceVariant,
                            foregroundColor: ColorTokens.textPrimary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    // Transfer button
                    FilledButton.icon(
                      onPressed: songs.isEmpty || device == null
                          ? null
                          : () => _enqueueAll(ref, device.path),
                      icon: const Icon(Icons.download, size: 16),
                      label: Text(
                        devices.isEmpty
                            ? 'No device connected'
                            : device == null
                                ? 'Select a device'
                                : 'Transfer',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: ColorTokens.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Add to playlist
                    IconButton(
                      icon: const Icon(Icons.playlist_add, size: 20),
                      color: ColorTokens.textSecondary,
                      tooltip: 'Add album to playlist',
                      onPressed: songs.isEmpty
                          ? null
                          : () => showAddToPlaylistDialog(
                              context, ref, songs.map((s) => s.id).toList()),
                    ),
                    // Get Info
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 20),
                      color: ColorTokens.textSecondary,
                      tooltip: 'Get Info',
                      onPressed: () =>
                          AlbumInfoDialog.show(context, album),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _enqueueAll(WidgetRef ref, String devicePath) {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    ref.read(transferQueueProvider.notifier).enqueue(
          album.songs,
          devicePath,
          (id) => repo.downloadUri(id),
        );
  }
}

// ── Song row ──────────────────────────────────────────────────────────────────

class _AlbumSongRow extends ConsumerWidget {
  const _AlbumSongRow({
    required this.song,
    required this.allSongs,
    required this.index,
  });

  final Song song;
  final List<Song> allSongs;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(transferQueueProvider);
    final isActive = queue.any((t) =>
        t.song.id == song.id && t.status == TransferStatus.inProgress);
    final isQueued = !isActive &&
        queue.any((t) =>
            t.song.id == song.id && t.status == TransferStatus.queued);

    final device = ref.watch(selectedDeviceProvider);
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    final isOnDevice = settings != null && songExistsOnDevice(song, settings);

    Widget? trailing;
    if (isActive || isQueued) {
      trailing = Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SyncDot(
          color: Colors.blue.withValues(alpha: 0.85),
          pulse: isActive,
        ),
      );
    } else if (isOnDevice) {
      trailing = Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SyncDot(color: Colors.green.withValues(alpha: 0.85)),
      );
    }

    return SongRow(
      song: song,
      trailing: trailing,
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playSong(song, queue: allSongs, index: index),
      onAddToPlaylist: () =>
          showAddToPlaylistDialog(context, ref, [song.id]),
      onGetInfo: () => showSongMetadataDialog(context, song),
    );
  }
}

