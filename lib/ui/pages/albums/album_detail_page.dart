import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/device_settings_notifier.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/connected_device.dart';
import '../../../domain/models/device_settings.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/song_row.dart';

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
                albumId: albumId,
                name: a.name,
                artist: a.artist,
                year: a.year,
                coverArtId: a.coverArtId,
                songCount: a.songCount,
                songs: a.songs,
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
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
  const _AlbumHeader({
    required this.albumId,
    required this.name,
    required this.artist,
    required this.year,
    required this.coverArtId,
    required this.songCount,
    required this.songs,
    required this.onBack,
  });

  final String albumId;
  final String name;
  final String? artist;
  final int? year;
  final String? coverArtId;
  final int songCount;
  final List<Song> songs;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];

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
                coverArtId: coverArtId, size: 240, borderRadius: 8),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ColorTokens.textPrimary,
                  ),
                ),
                if (artist != null)
                  Text(artist!,
                      style: const TextStyle(
                          fontSize: 14, color: ColorTokens.accent)),
                const SizedBox(height: 4),
                Text(
                  [if (year != null) '$year', '$songCount songs'].join(' · '),
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
          songs,
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
    final isQueued = queue.any((t) =>
        t.song.id == song.id &&
        (t.status == TransferStatus.queued ||
            t.status == TransferStatus.inProgress));

    final device = ref.watch(selectedDeviceProvider);
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    final isOnDevice = settings != null && songExistsOnDevice(song, settings);

    Widget? trailing;
    if (isQueued) {
      trailing = const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.download, size: 12, color: ColorTokens.accent),
      );
    } else if (isOnDevice) {
      trailing = const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.check_circle, size: 12, color: Colors.green),
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
      onGetInfo: () => showSongMetadataDialog(context, ref, song),
    );
  }
}
