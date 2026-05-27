import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:macos_window_utils/widgets/visual_effect_subview_container/visual_effect_subview_container.dart';

import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/album.dart';
import '../../../domain/models/artist.dart';

class ArtistTreeWidget extends StatelessWidget {
  const ArtistTreeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return VisualEffectSubviewContainer(
      material: NSVisualEffectViewMaterial.sidebar,
      state: NSVisualEffectViewState.active,
      child: const _ArtistTreeContent(),
    );
  }
}

class _ArtistTreeContent extends ConsumerStatefulWidget {
  const _ArtistTreeContent();

  @override
  ConsumerState<_ArtistTreeContent> createState() => _ArtistTreeContentState();
}

class _ArtistTreeContentState extends ConsumerState<_ArtistTreeContent> {
  final _expanded = <String>{};

  void _toggle(String artistId) {
    setState(() {
      if (_expanded.contains(artistId)) {
        _expanded.remove(artistId);
      } else {
        _expanded.add(artistId);
      }
    });
  }

  void _selectArtist(Artist artist) {
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedArtistIdProvider.notifier).state = artist.id;
    ref.read(selectedAlbumIdProvider.notifier).state = null;
    ref.read(selectedSectionProvider.notifier).state = SidebarSection.albums;
  }

  void _selectAlbum(String albumId) {
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedAlbumIdProvider.notifier).state = albumId;
    ref.read(selectedSectionProvider.notifier).state = SidebarSection.albums;
  }

  @override
  Widget build(BuildContext context) {
    final artistsAsync = ref.watch(artistsProvider);
    final selectedArtistId = ref.watch(selectedArtistIdProvider);
    final selectedAlbumId = ref.watch(selectedAlbumIdProvider);

    return Container(
      width: AppConstants.artistTreeWidth,
      color: ColorTokens.sidebarOverlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(),
          Expanded(
            child: artistsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('$e',
                    style: const TextStyle(
                        fontSize: 11, color: ColorTokens.textSecondary)),
              ),
              data: (artists) => ListView.builder(
                itemCount: artists.length,
                itemBuilder: (_, i) {
                  final artist = artists[i];
                  return _ArtistNode(
                    artist: artist,
                    isExpanded: _expanded.contains(artist.id),
                    isSelected: selectedArtistId == artist.id &&
                        selectedAlbumId == null,
                    selectedAlbumId: selectedAlbumId,
                    onToggle: () => _toggle(artist.id),
                    onArtistTap: () => _selectArtist(artist),
                    onAlbumTap: _selectAlbum,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ColorTokens.divider)),
      ),
      alignment: Alignment.centerLeft,
      child: const Text(
        'ARTISTS',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: ColorTokens.textSecondary,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

// ── Artist node (collapsible) ─────────────────────────────────────────────────

class _ArtistNode extends StatelessWidget {
  const _ArtistNode({
    required this.artist,
    required this.isExpanded,
    required this.isSelected,
    required this.selectedAlbumId,
    required this.onToggle,
    required this.onArtistTap,
    required this.onAlbumTap,
  });

  final Artist artist;
  final bool isExpanded;
  final bool isSelected;
  final String? selectedAlbumId;
  final VoidCallback onToggle;
  final VoidCallback onArtistTap;
  final ValueChanged<String> onAlbumTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Artist row ──────────────────────────────────────────────────────
        InkWell(
          onTap: () {
            onArtistTap();
            if (!isExpanded) onToggle();
          },
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: isSelected
                ? BoxDecoration(
                    color: ColorTokens.selectionBackground,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Row(
              children: [
                GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 18,
                    height: 30,
                    child: Center(
                      child: AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: isSelected
                              ? ColorTokens.accent
                              : ColorTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    artist.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? ColorTokens.textPrimary
                          : ColorTokens.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Album subtree (lazy) ────────────────────────────────────────────
        if (isExpanded)
          _AlbumSubtree(
            artistId: artist.id,
            selectedAlbumId: selectedAlbumId,
            onAlbumTap: onAlbumTap,
          ),
      ],
    );
  }
}

// ── Album subtree — only built and watched when the artist is expanded ─────────

class _AlbumSubtree extends ConsumerWidget {
  const _AlbumSubtree({
    required this.artistId,
    required this.selectedAlbumId,
    required this.onAlbumTap,
  });

  final String artistId;
  final String? selectedAlbumId;
  final ValueChanged<String> onAlbumTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsByArtistProvider(artistId));

    return albumsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(28, 4, 8, 4),
        child: LinearProgressIndicator(minHeight: 1),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (albums) => Column(
        children: albums.map((album) {
          final isSelected = selectedAlbumId == album.id;
          return _AlbumRow(
            album: album,
            isSelected: isSelected,
            onTap: () => onAlbumTap(album.id),
          );
        }).toList(),
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.isSelected,
    required this.onTap,
  });

  final Album album;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 28, right: 8),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: isSelected
            ? BoxDecoration(
                color: ColorTokens.selectionBackground,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                album.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            if (album.year != null)
              Text(
                '${album.year}',
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? ColorTokens.textSecondary
                      : ColorTokens.textSecondary.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
