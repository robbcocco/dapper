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
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/song_row.dart';
import '../albums/album_detail_page.dart';
import '../albums/album_info_dialog.dart';

class ArtistsPage extends ConsumerWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    final selectedArtistId = ref.watch(selectedArtistIdProvider);
    final selectedAlbumId = ref.watch(selectedAlbumIdProvider);

    return artists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('$e',
              style: const TextStyle(color: ColorTokens.textSecondary))),
      data: (list) {
        final selectedArtist = selectedArtistId != null
            ? list.cast<Artist?>().firstWhere(
                (a) => a?.id == selectedArtistId,
                orElse: () => null)
            : null;

        Widget rightPanel;
        if (selectedAlbumId != null) {
          rightPanel = AlbumDetailPage(albumId: selectedAlbumId);
        } else if (selectedArtist != null) {
          rightPanel = _ArtistDetailPanel(
            key: ValueKey(selectedArtist.id),
            artist: selectedArtist,
          );
        } else {
          rightPanel = const _EmptyDetail();
        }

        return Row(
          children: [
            _ArtistListPanel(
              artists: list,
              selectedId: selectedArtistId,
            ),
            Container(width: 1, color: ColorTokens.glassBorder),
            Expanded(child: rightPanel),
          ],
        );
      },
    );
  }
}

// ── Left panel: artist list ───────────────────────────────────────────────────

class _ArtistListPanel extends ConsumerWidget {
  const _ArtistListPanel({
    required this.artists,
    required this.selectedId,
  });

  final List<Artist> artists;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: AppConstants.artistTreeWidth,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: artists.length,
        itemExtent: 52,
        itemBuilder: (context, i) {
          final artist = artists[i];
          final isSelected = artist.id == selectedId;
          return _ArtistTile(
            artist: artist,
            isSelected: isSelected,
            onTap: () {
              ref.read(selectedArtistIdProvider.notifier).state = artist.id;
              ref.read(selectedAlbumIdProvider.notifier).state = null;
            },
          );
        },
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({
    required this.artist,
    required this.isSelected,
    required this.onTap,
  });

  final Artist artist;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: isSelected
            ? BoxDecoration(
                color: ColorTokens.selectionBackground,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CoverArtImage(
                coverArtId: artist.coverArtId,
                size: 68,
                borderRadius: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                artist.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Select an artist',
        style: TextStyle(fontSize: 14, color: ColorTokens.textSecondary),
      ),
    );
  }
}

// ── Right panel: artist detail ────────────────────────────────────────────────

class _ArtistDetailPanel extends ConsumerWidget {
  const _ArtistDetailPanel({super.key, required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsByArtistProvider(artist.id));
    final device = ref.watch(selectedDeviceProvider);

    return albumsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (albums) {
        final totalSongs = albums.fold(0, (sum, a) => sum + a.songCount);

        return CustomScrollView(
          slivers: [
            // ── Artist header ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: CoverArtImage(
                        coverArtId: artist.coverArtId,
                        size: 176,
                        borderRadius: 44,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist.name,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: ColorTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${albums.length} album${albums.length == 1 ? '' : 's'} · $totalSongs song${totalSongs == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontSize: 13,
                                color: ColorTokens.textSecondary),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _ActionButton(
                                icon: Icons.play_arrow,
                                label: 'Play',
                                onPressed: () => ref
                                    .read(playbackProvider.notifier)
                                    .playArtist(artist.id),
                              ),
                              const SizedBox(width: 8),
                              _ActionButton(
                                icon: Icons.shuffle,
                                label: 'Shuffle',
                                onPressed: () async {
                                  final notifier =
                                      ref.read(playbackProvider.notifier);
                                  if (!ref
                                      .read(playbackProvider)
                                      .isShuffled) {
                                    notifier.toggleShuffle();
                                  }
                                  await notifier.playArtist(artist.id);
                                },
                              ),
                              if (device != null) ...[
                                const SizedBox(width: 8),
                                _ActionButton(
                                  icon: Icons.download,
                                  label: 'Transfer All',
                                  primary: true,
                                  onPressed: () =>
                                      _transferAll(ref, device, albums),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Divider(height: 1, color: ColorTokens.divider),
            ),

            // ── Albums + songs ────────────────────────────────────────────
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _AlbumSection(album: albums[i]),
                childCount: albums.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        );
      },
    );
  }

  Future<void> _transferAll(
    WidgetRef ref,
    dynamic device,
    List<Album> albums,
  ) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final allSongs = <Song>[];
    for (final album in albums) {
      final full = await repo.getAlbum(album.id);
      allSongs.addAll(full.songs);
    }
    if (allSongs.isEmpty) return;
    ref
        .read(transferQueueProvider.notifier)
        .enqueue(allSongs, device.path, repo.downloadUri);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor:
            primary ? ColorTokens.accent : ColorTokens.surfaceVariant,
        foregroundColor: ColorTokens.textPrimary,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }
}

// ── Album section (header + songs) ────────────────────────────────────────────

class _AlbumSection extends ConsumerWidget {
  const _AlbumSection({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fullAlbum = ref.watch(albumProvider(album.id));
    final queue = ref.watch(transferQueueProvider);
    final device = ref.watch(selectedDeviceProvider);
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    final isSynced = settings != null &&
        albumExistsOnDevice(album.artist, album.name, album.year, settings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Album header
        GestureDetector(
          onTap: () =>
              ref.read(selectedAlbumIdProvider.notifier).state = album.id,
          onSecondaryTapUp: (d) =>
              _showMenu(context, ref, device, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 16, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CoverArtImage(
                    coverArtId: album.coverArtId,
                    size: 104,
                    borderRadius: 6,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ColorTokens.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (album.year != null) '${album.year}',
                          '${album.songCount} song${album.songCount == 1 ? '' : 's'}',
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 12,
                            color: ColorTokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (isSynced)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.green),
                  ),
                GestureDetector(
                  onTapDown: (d) =>
                      _showMenu(context, ref, device, d.globalPosition),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.more_horiz,
                        size: 16, color: ColorTokens.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Song rows
        fullAlbum.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child:
                Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (full) {
            if (full == null) return const SizedBox.shrink();
            return Column(
              children: full.songs.asMap().entries.map((e) {
                final song = e.value;
                final i = e.key;
                final isQueued = queue.any((t) =>
                    t.song.id == song.id &&
                    (t.status == TransferStatus.queued ||
                        t.status == TransferStatus.inProgress));
                final isOnDevice = settings != null &&
                    songExistsOnDevice(song, settings);
                Widget? trailing;
                if (isQueued) {
                  trailing = const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.download,
                        size: 12, color: ColorTokens.accent),
                  );
                } else if (isOnDevice) {
                  trailing = const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.check_circle,
                        size: 12, color: Colors.green),
                  );
                }
                return SongRow(
                  song: song,
                  index: i,
                  trailing: trailing,
                  showArtist: false,
                  onTap: () => ref
                      .read(playbackProvider.notifier)
                      .playSong(song, queue: full.songs, index: i),
                  onAddToPlaylist: () =>
                      showAddToPlaylistDialog(context, ref, [song.id]),
                  onGetInfo: () =>
                      showSongMetadataDialog(context, song),
                );
              }).toList(),
            );
          },
        ),

        const Divider(height: 1, color: ColorTokens.divider),
      ],
    );
  }

  void _showMenu(
    BuildContext context,
    WidgetRef ref,
    dynamic device,
    Offset pos,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: ColorTokens.surface,
      items: [
        const PopupMenuItem(
          value: 'open',
          child: _MenuRow(icon: Icons.album_outlined, label: 'Open Album'),
        ),
        const PopupMenuItem(
          value: 'play',
          child: _MenuRow(icon: Icons.play_arrow, label: 'Play Album'),
        ),
        if (device != null)
          PopupMenuItem(
            value: 'transfer',
            child: _MenuRow(
                icon: Icons.download,
                label: 'Transfer to ${device.label}'),
          ),
        const PopupMenuItem(
          value: 'playlist',
          child:
              _MenuRow(icon: Icons.playlist_add, label: 'Add to Playlist'),
        ),
        const PopupMenuItem(
          value: 'info',
          child: _MenuRow(icon: Icons.info_outline, label: 'Get Info'),
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
      AlbumInfoDialog.show(context, full);
      return;
    }

    if (result == 'play' || result == 'transfer' || result == 'playlist') {
      final full = await ref.read(albumProvider(album.id).future);
      if (full == null || !context.mounted) return;
      if (result == 'play') {
        ref.read(playbackProvider.notifier).playSong(
              full.songs.first,
              queue: full.songs,
              index: 0,
            );
      } else if (result == 'transfer') {
        final d = ref.read(selectedDeviceProvider);
        final repo = ref.read(libraryRepositoryProvider);
        if (d == null || repo == null) return;
        ref
            .read(transferQueueProvider.notifier)
            .enqueue(full.songs, d.path, repo.downloadUri);
      } else {
        showAddToPlaylistDialog(
            context, ref, full.songs.map((s) => s.id).toList());
      }
    }
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
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
