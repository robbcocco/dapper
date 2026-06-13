import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/album.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/error_retry.dart';
import '../albums/album_detail_page.dart';

/// Top-level Genres page. Lists all server-side genres; selecting one drills
/// into an album grid filtered by that genre. Mirrors the artists-page
/// "select an item → show its content" pattern.
class GenresPage extends ConsumerWidget {
  const GenresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedGenreProvider);
    final selectedAlbumId = ref.watch(selectedAlbumIdProvider);

    if (selectedAlbumId != null) {
      return AlbumDetailPage(albumId: selectedAlbumId);
    }
    if (selected != null) {
      return _GenreAlbumsPanel(genre: selected);
    }

    final async = ref.watch(genresProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(genresProvider),
      ),
      data: (genres) {
        if (genres.isEmpty) {
          return const Center(
            child: Text('No genres on this server.',
                style: TextStyle(color: ColorTokens.textSecondary)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: genres.length,
          itemBuilder: (_, i) {
            final g = genres[i];
            return ListTile(
              dense: true,
              onTap: () =>
                  ref.read(selectedGenreProvider.notifier).state = g.name,
              title: Text(
                g.name,
                style: const TextStyle(
                    fontSize: 13, color: ColorTokens.textPrimary),
              ),
              subtitle: Text(
                '${g.albumCount} album${g.albumCount == 1 ? '' : 's'} · '
                '${g.songCount} song${g.songCount == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 11, color: ColorTokens.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right,
                  size: 16, color: ColorTokens.textSecondary),
            );
          },
        );
      },
    );
  }
}

class _GenreAlbumsPanel extends ConsumerWidget {
  const _GenreAlbumsPanel({required this.genre});
  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumsByGenreProvider(genre));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with a back button and the genre name.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 24, 16),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ColorTokens.divider))),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                onPressed: () =>
                    ref.read(selectedGenreProvider.notifier).state = null,
                color: ColorTokens.textSecondary,
                tooltip: 'All Genres',
              ),
              const SizedBox(width: 4),
              Text(genre,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ColorTokens.textPrimary,
                  )),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () => ref.invalidate(albumsByGenreProvider(genre)),
            ),
            data: (albums) {
              if (albums.isEmpty) {
                return Center(
                  child: Text('No albums in "$genre"',
                      style: const TextStyle(
                          color: ColorTokens.textSecondary)),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(24),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: AppConstants.albumCardSize + 16,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.75,
                ),
                itemCount: albums.length,
                itemBuilder: (_, i) => _GenreAlbumCard(album: albums[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GenreAlbumCard extends ConsumerWidget {
  const _GenreAlbumCard({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () =>
          ref.read(selectedAlbumIdProvider.notifier).state = album.id,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: CoverArtImage(
              coverArtId: album.coverArtId,
              size: AppConstants.gridCoverArtSize,
              borderRadius: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12,
                color: ColorTokens.textPrimary,
                fontWeight: FontWeight.w500),
          ),
          if (album.artist != null)
            Text(
              album.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, color: ColorTokens.textSecondary),
            ),
        ],
      ),
    );
  }
}
