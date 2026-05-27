import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_queue_notifier.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/artist.dart';
import '../../../domain/models/song.dart';

class ArtistsPage extends ConsumerWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    return artists.when(
      data: (list) => _ArtistList(artists: list),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _ArtistList extends ConsumerWidget {
  const _ArtistList({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    return ListView.builder(
      itemCount: artists.length,
      itemExtent: 44,
      itemBuilder: (context, i) {
        final artist = artists[i];
        return GestureDetector(
          onTap: () {
            ref.read(selectedArtistIdProvider.notifier).state = artist.id;
            ref.read(selectedSectionProvider.notifier).state =
                SidebarSection.albums;
          },
          onSecondaryTapUp: (d) =>
              _showMenu(context, ref, artist, device?.label, d.globalPosition),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: ColorTokens.divider.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    artist.name,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ColorTokens.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${artist.albumCount} albums',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ColorTokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: ColorTokens.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMenu(
    BuildContext context,
    WidgetRef ref,
    Artist artist,
    String? deviceLabel,
    Offset pos,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: ColorTokens.surface,
      items: [
        const PopupMenuItem(
          value: 'browse',
          child: _MenuItem(icon: Icons.album_outlined, label: 'Browse Albums'),
        ),
        const PopupMenuItem(
          value: 'play',
          child: _MenuItem(icon: Icons.play_arrow, label: 'Play All'),
        ),
        if (deviceLabel != null)
          PopupMenuItem(
            value: 'transfer',
            child: _MenuItem(
                icon: Icons.download,
                label: 'Transfer to $deviceLabel'),
          ),
      ],
    );
    if (!context.mounted) return;

    if (result == 'browse') {
      ref.read(selectedArtistIdProvider.notifier).state = artist.id;
      ref.read(selectedSectionProvider.notifier).state = SidebarSection.albums;
    }
    if (result == 'play') {
      ref.read(playbackProvider.notifier).playArtist(artist.id);
    }
    if (result == 'transfer') {
      final device = ref.read(selectedDeviceProvider);
      final repo = ref.read(libraryRepositoryProvider);
      if (device == null || repo == null) return;
      final albums = await repo.getAlbumsByArtist(artist.id);
      final allSongs = <Song>[];
      for (final album in albums) {
        final full = await repo.getAlbum(album.id);
        allSongs.addAll(full.songs);
      }
      if (allSongs.isEmpty || !context.mounted) return;
      ref.read(transferQueueProvider.notifier)
          .enqueue(allSongs, device.path, repo.downloadUri);
    }
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ColorTokens.textPrimary),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 13, color: ColorTokens.textPrimary)),
      ],
    );
  }
}
