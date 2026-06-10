import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../application/device/device_settings_notifier.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/library/song_selection_notifier.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/album.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/select_all_shortcut.dart';
import '../../widgets/selection_action_bar.dart';
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
        // Reset selection when navigating between albums.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(songSelectionProvider.notifier).setScope('album:${a.id}');
        });
        return SelectAllShortcut(
          scopeKey: 'album:${a.id}',
          allSongs: a.songs,
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _AlbumHeader(
                      album: a,
                      onBack: () => ref
                          .read(selectedAlbumIdProvider.notifier)
                          .state = null,
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _AlbumSongRow(
                        song: a.songs[i],
                        allSongs: a.songs,
                        index: i,
                        scopeKey: 'album:${a.id}',
                      ),
                      childCount: a.songs.length,
                    ),
                  ),
                  const SliverToBoxAdapter(
                      child: SizedBox(
                          height: AppConstants.scrollBottomInset)),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SelectionActionBar(
                  scopeKey: 'album:${a.id}',
                  allSongs: a.songs,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(albumProvider(albumId)),
      ),
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
    final settings = ref.read(deviceSettingsProvider(devicePath));
    // Use bulk zip when enabled AND not transcoding (zip endpoint serves
    // originals only). All other cases fall through to per-song.
    if (settings.useZipDownload && !settings.isTranscoding) {
      ref.read(transferQueueProvider.notifier).enqueueZipGroup(
            album.id,
            album.songs,
            devicePath,
          );
      return;
    }
    final folder = buildAlbumFolder(album.artist, album.name, album.year, settings);
    final expectedCounts = folder != null ? {folder: album.songCount} : null;
    ref.read(transferQueueProvider.notifier).enqueue(
          album.songs,
          devicePath,
          expectedAlbumSongCounts: expectedCounts,
        );
  }
}

// ── Song row ──────────────────────────────────────────────────────────────────

class _AlbumSongRow extends ConsumerWidget {
  const _AlbumSongRow({
    required this.song,
    required this.allSongs,
    required this.index,
    required this.scopeKey,
  });

  final Song song;
  final List<Song> allSongs;
  final int index;
  final String scopeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (isActive, isQueued) = ref.watch(
      transferQueueProvider.select((q) {
        var active = false;
        var queued = false;
        for (final t in q) {
          if (t.song.id != song.id) continue;
          if (t.status == TransferStatus.inProgress) {
            active = true;
            break;
          }
          if (t.status == TransferStatus.queued) queued = true;
        }
        return (active, !active && queued);
      }),
    );

    final device = ref.watch(selectedDeviceProvider);
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    ref.watch(manifestRevisionProvider);
    final isOnDevice = settings != null && songExistsOnDevice(song, settings);
    final isSelected = ref.watch(songSelectionProvider.select((s) =>
        s.matches(scopeKey) && s.isSelected(song.id)));

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
      selected: isSelected,
      selectionScopeKey: scopeKey,
      selectionAllSongs: allSongs,
      trailing: trailing,
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playSong(song, queue: allSongs, index: index),
      onTapWithModifiers: (mods) {
        final notifier = ref.read(songSelectionProvider.notifier);
        if (mods.hasRange) {
          notifier.selectRange(scopeKey, allSongs, index);
          return;
        }
        if (mods.hasToggle) {
          notifier.toggle(scopeKey, song.id, index);
          return;
        }
        // Plain tap. If there's an active selection in the same scope, plain
        // tap collapses it back to a single row (Finder-style). Otherwise
        // play the song as before.
        final selection = ref.read(songSelectionProvider);
        if (selection.matches(scopeKey) && !selection.isEmpty) {
          notifier.selectOnly(scopeKey, song.id, index);
          return;
        }
        ref
            .read(playbackProvider.notifier)
            .playSong(song, queue: allSongs, index: index);
      },
      onAddToPlaylist: () =>
          showAddToPlaylistDialog(context, ref, [song.id]),
      onGetInfo: () => showSongMetadataDialog(context, song),
    );
  }
}

