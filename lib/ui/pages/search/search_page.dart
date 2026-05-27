import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/artist.dart';
import '../../../domain/models/album.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
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
      error: (e, _) => Center(
          child: Text('$e',
              style: const TextStyle(color: ColorTokens.textSecondary))),
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
          padding: const EdgeInsets.symmetric(vertical: 16),
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
