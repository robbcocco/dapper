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
import '../../../domain/models/artist.dart';
import '../../../domain/models/album.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/song_row.dart';

class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    if (query.isEmpty) return const SizedBox.shrink();

    final results = ref.watch(searchResultsProvider(query));
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(searchResultsProvider(query)),
      ),
      data: (r) {
        if (r.isEmpty) {
          return Center(
            child: Text(
              'No results for "$query"',
              style: const TextStyle(
                  fontSize: 14, color: ColorTokens.textSecondary),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(
              top: 16, bottom: AppConstants.scrollBottomInset),
          children: [
            if (r.artists.isNotEmpty) ...[
              _SectionHeader('ARTISTS'),
              ...r.artists.map((a) => _ArtistRow(artist: a)),
              const SizedBox(height: 8),
            ],
            if (r.albums.isNotEmpty) ...[
              _SectionHeader('ALBUMS'),
              ...r.albums.map((a) => _AlbumRow(album: a)),
              const SizedBox(height: 8),
            ],
            if (r.songs.isNotEmpty) ...[
              _SectionHeader('SONGS'),
              ...r.songs.asMap().entries.map(
                    (e) => SongRow(
                      song: e.value,
                      index: e.key,
                      showArtist: true,
                      onTap: () => ref
                          .read(playbackProvider.notifier)
                          .playSong(e.value, queue: r.songs, index: e.key),
                      onAddToPlaylist: () =>
                          showAddToPlaylistDialog(context, ref, [e.value.id]),
                      onGetInfo: () =>
                          showSongMetadataDialog(context, e.value),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: ColorTokens.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ArtistRow extends ConsumerWidget {
  const _ArtistRow({required this.artist});
  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        ref.read(selectedArtistIdProvider.notifier).state = artist.id;
        ref.read(selectedAlbumIdProvider.notifier).state = null;
        ref.read(selectedSectionProvider.notifier).state = SidebarSection.artists;
        ref.read(searchQueryProvider.notifier).state = '';
      },
      onSecondaryTapUp: (d) =>
          _showSearchArtistMenu(context, ref, artist, d.globalPosition),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_outline,
                size: 16, color: ColorTokens.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                artist.name,
                style: const TextStyle(
                    fontSize: 13, color: ColorTokens.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${artist.albumCount} albums',
              style: const TextStyle(
                  fontSize: 11, color: ColorTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumRow extends ConsumerWidget {
  const _AlbumRow({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        ref.read(selectedAlbumIdProvider.notifier).state = album.id;
        ref.read(selectedSectionProvider.notifier).state = SidebarSection.albums;
        ref.read(searchQueryProvider.notifier).state = '';
      },
      onSecondaryTapUp: (d) =>
          _showSearchAlbumMenu(context, ref, album, d.globalPosition),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CoverArtImage(
                  coverArtId: album.coverArtId, size: 72, borderRadius: 3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    style: const TextStyle(
                        fontSize: 13, color: ColorTokens.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (album.artist != null)
                    Text(
                      album.artist!,
                      style: const TextStyle(
                          fontSize: 11, color: ColorTokens.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (album.year != null)
              Text(
                '${album.year}',
                style: const TextStyle(
                    fontSize: 11, color: ColorTokens.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Context-menu helpers ──────────────────────────────────────────────────────

Future<void> _showSearchArtistMenu(
  BuildContext context,
  WidgetRef ref,
  Artist artist,
  Offset pos,
) async {
  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
    color: ColorTokens.surface,
    items: [
      const PopupMenuItem(
        value: 'go',
        child: _SearchMenuRow(icon: Icons.person_outline, label: 'Go to Artist'),
      ),
      const PopupMenuItem(
        value: 'play',
        child: _SearchMenuRow(icon: Icons.play_arrow, label: 'Play All'),
      ),
    ],
  );
  if (!context.mounted) return;

  if (result == 'go') {
    ref.read(selectedArtistIdProvider.notifier).state = artist.id;
    ref.read(selectedAlbumIdProvider.notifier).state = null;
    ref.read(selectedSectionProvider.notifier).state = SidebarSection.artists;
    ref.read(searchQueryProvider.notifier).state = '';
  } else if (result == 'play') {
    unawaited(ref.read(playbackProvider.notifier).playArtist(artist.id));
  }
}

Future<void> _showSearchAlbumMenu(
  BuildContext context,
  WidgetRef ref,
  Album album,
  Offset pos,
) async {
  final devices = ref.read(connectedDevicesProvider).valueOrNull ?? [];

  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
    color: ColorTokens.surface,
    items: [
      const PopupMenuItem(
        value: 'open',
        child: _SearchMenuRow(icon: Icons.album_outlined, label: 'Open Album'),
      ),
      const PopupMenuItem(
        value: 'play',
        child: _SearchMenuRow(icon: Icons.play_arrow, label: 'Play Album'),
      ),
      for (final d in devices)
        PopupMenuItem(
          value: 'transfer:${d.path}',
          child: _SearchMenuRow(
            icon: Icons.download,
            label: devices.length == 1
                ? 'Transfer Album'
                : 'Transfer to ${d.label}',
          ),
        ),
    ],
  );
  if (!context.mounted) return;

  if (result == 'open') {
    ref.read(selectedAlbumIdProvider.notifier).state = album.id;
    ref.read(selectedSectionProvider.notifier).state = SidebarSection.albums;
    ref.read(searchQueryProvider.notifier).state = '';
  } else if (result == 'play') {
    final full = await ref.read(albumProvider(album.id).future);
    if (full == null || full.songs.isEmpty || !context.mounted) return;
    unawaited(ref.read(playbackProvider.notifier).playSong(
          full.songs.first,
          queue: full.songs,
          index: 0,
        ));
  } else if (result != null && result.startsWith('transfer:')) {
    final devicePath = result.substring(9);
    final full = await ref.read(albumProvider(album.id).future);
    if (full == null || !context.mounted) return;
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final settings = ref.read(deviceSettingsProvider(devicePath));
    final folder =
        buildAlbumFolder(album.artist, album.name, album.year, settings);
    final expectedCounts = folder != null ? {folder: full.songCount} : null;
    ref.read(transferQueueProvider.notifier).enqueue(
          full.songs,
          devicePath,
          expectedAlbumSongCounts: expectedCounts,
        );
  }
}

class _SearchMenuRow extends StatelessWidget {
  const _SearchMenuRow({required this.icon, required this.label});
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
