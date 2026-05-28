import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/artist_sync_provider.dart';
import '../../../application/device/device_settings_notifier.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/lidarr/lidarr_notifier.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/album.dart';
import '../../../domain/models/artist.dart';
import '../../../domain/models/lidarr_models.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/song_row.dart';
import '../../widgets/sync_dot.dart';
import '../albums/album_detail_page.dart';
import '../albums/album_info_dialog.dart';

/// Normalizes an album title for fuzzy cross-service matching.
String _normalizeTitle(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"[^\w\s]"), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class ArtistsPage extends ConsumerWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    final selectedArtistId = ref.watch(selectedArtistIdProvider);
    final selectedAlbumId = ref.watch(selectedAlbumIdProvider);
    final lidarrByMbid = ref.watch(lidarrArtistByMbidProvider);
    final lidarrConnected = ref.watch(lidarrClientProvider) != null;
    final filter = ref.watch(lidarrArtistFilterProvider);
    final selectedLidarrMbid = ref.watch(selectedLidarrMbidProvider);
    final allLidarrArtists = ref.watch(lidarrArtistsProvider).valueOrNull ?? [];

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

        // Lidarr-only selected artist
        final selectedLidarrArtist = (filter == LidarrArtistFilter.lidarr &&
                selectedLidarrMbid != null)
            ? allLidarrArtists.cast<LidarrArtist?>().firstWhere(
                (a) => a?.mbid == selectedLidarrMbid,
                orElse: () => null)
            : null;

        Widget rightPanel;
        if (selectedAlbumId != null) {
          rightPanel = AlbumDetailPage(albumId: selectedAlbumId);
        } else if (selectedLidarrArtist != null) {
          rightPanel = _LidarrOnlyDetailPanel(
            key: ValueKey('lidarr_${selectedLidarrArtist.mbid}'),
            artist: selectedLidarrArtist,
          );
        } else if (selectedArtist != null) {
          rightPanel = _ArtistDetailPanel(
            key: ValueKey(selectedArtist.id),
            artist: selectedArtist,
            lidarrArtist: selectedArtist.musicBrainzId != null
                ? lidarrByMbid[selectedArtist.musicBrainzId]
                : null,
            lidarrConnected: lidarrConnected,
          );
        } else {
          rightPanel = const _EmptyDetail();
        }

        return Row(
          children: [
            _ArtistListPanel(
              artists: list,
              selectedId: selectedArtistId,
              lidarrByMbid: lidarrByMbid,
              lidarrConnected: lidarrConnected,
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
    required this.lidarrByMbid,
    required this.lidarrConnected,
  });

  final List<Artist> artists;
  final String? selectedId;
  final Map<String, LidarrArtist> lidarrByMbid;
  final bool lidarrConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(lidarrArtistFilterProvider);
    final selectedLidarrMbid = ref.watch(selectedLidarrMbidProvider);

    final deviceSync = ref.watch(artistSyncProvider);

    Widget list;

    if (lidarrConnected && filter == LidarrArtistFilter.lidarr) {
      list = _LidarrSearchList(selectedMbid: selectedLidarrMbid);
    } else {
      list = ListView.builder(
        padding: const EdgeInsets.only(
            top: 8, bottom: AppConstants.scrollBottomInset),
        itemCount: artists.length,
        itemExtent: 52,
        itemBuilder: (context, i) {
          final artist = artists[i];
          return _ArtistTile(
            artist: artist,
            isSelected: artist.id == selectedId,
            syncStatus: deviceSync[artist.id],
            onTap: () {
              ref.read(selectedArtistIdProvider.notifier).state = artist.id;
              ref.read(selectedAlbumIdProvider.notifier).state = null;
              ref.read(selectedLidarrMbidProvider.notifier).state = null;
            },
          );
        },
      );
    }

    return SizedBox(
      width: AppConstants.artistTreeWidth,
      child: Column(
        children: [
          if (lidarrConnected)
            _LidarrFilterBar(current: filter, ref: ref),
          Expanded(child: list),
        ],
      ),
    );
  }
}

class _LidarrFilterBar extends StatelessWidget {
  const _LidarrFilterBar({required this.current, required this.ref});
  final LidarrArtistFilter current;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ColorTokens.glassBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: LidarrArtistFilter.values
              .map((f) => _FilterChip(
                    label: switch (f) {
                      LidarrArtistFilter.all => 'All',
                      LidarrArtistFilter.lidarr => 'Lidarr',
                    },
                    selected: current == f,
                    onTap: () {
                      ref.read(lidarrArtistFilterProvider.notifier).state = f;
                      if (f != LidarrArtistFilter.lidarr) {
                        ref.read(selectedLidarrMbidProvider.notifier).state =
                            null;
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _LidarrLibraryFilterBar extends ConsumerWidget {
  const _LidarrLibraryFilterBar(
      {required this.current, required this.onSelect});
  final LidarrLibraryFilter current;
  final ValueChanged<LidarrLibraryFilter> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customFilters =
        ref.watch(lidarrCustomFiltersProvider).valueOrNull ?? [];
    final selectedCustomId = ref.watch(selectedCustomFilterIdProvider);

    return Container(
      height: 30,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ColorTokens.glassBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            // Built-in filters
            ...LidarrLibraryFilter.values.map((f) => _FilterChip(
                  label: switch (f) {
                    LidarrLibraryFilter.all => 'All',
                    LidarrLibraryFilter.monitored => 'Monitored',
                    LidarrLibraryFilter.unmonitored => 'Unmonitored',
                    LidarrLibraryFilter.missing => 'Missing',
                  },
                  selected: selectedCustomId == null && current == f,
                  onTap: () {
                    ref
                        .read(selectedCustomFilterIdProvider.notifier)
                        .state = null;
                    onSelect(f);
                  },
                )),
            // Lidarr custom filters
            ...customFilters.map((cf) => _FilterChip(
                  label: cf.label,
                  selected: selectedCustomId == cf.id,
                  onTap: () => ref
                      .read(selectedCustomFilterIdProvider.notifier)
                      .state = cf.id,
                )),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? ColorTokens.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color:
                selected ? ColorTokens.accent : ColorTokens.textSecondary,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({
    required this.artist,
    required this.isSelected,
    required this.onTap,
    this.syncStatus,
  });

  final Artist artist;
  final bool isSelected;
  final VoidCallback onTap;
  final ArtistSyncStatus? syncStatus;

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
            if (syncStatus != null) ...[
              const SizedBox(width: 4),
              SyncDot(
                color: syncStatus == ArtistSyncStatus.full
                    ? Colors.green.withValues(alpha: 0.85)
                    : Colors.orange.withValues(alpha: 0.85),
                size: 6,
              ),
              const SizedBox(width: 4),
            ],
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
  const _ArtistDetailPanel({
    super.key,
    required this.artist,
    required this.lidarrConnected,
    this.lidarrArtist,
  });

  final Artist artist;
  final bool lidarrConnected;
  final LidarrArtist? lidarrArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsByArtistProvider(artist.id));
    final device = ref.watch(selectedDeviceProvider);

    // Fetch Lidarr albums when this artist is linked; build a normalized-title map.
    final lidarrAlbums = lidarrArtist != null
        ? ref
            .watch(lidarrAlbumsByArtistProvider(lidarrArtist!.id))
            .valueOrNull ?? <LidarrAlbum>[]
        : <LidarrAlbum>[];
    final lidarrByTitle = {
      for (final a in lidarrAlbums) _normalizeTitle(a.title): a,
    };

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
                              if (lidarrConnected) ...[
                                const SizedBox(width: 8),
                                lidarrArtist != null
                                    ? _LidarrBadge(lidarrArtist: lidarrArtist!)
                                    : _ActionButton(
                                        icon: Icons.add,
                                        label: 'Add to Lidarr',
                                        onPressed: () =>
                                            _showAddToLidarrSheet(
                                                context, ref),
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
                (context, i) => _AlbumSection(
                  album: albums[i],
                  lidarrAlbum:
                      lidarrByTitle[_normalizeTitle(albums[i].name)],
                ),
                childCount: albums.length,
              ),
            ),

            const SliverToBoxAdapter(
                child: SizedBox(height: AppConstants.scrollBottomInset)),
          ],
        );
      },
    );
  }

  void _showAddToLidarrSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ColorTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: ColorTokens.glassBorder),
      ),
      isScrollControlled: true,
      builder: (_) => _LidarrLookupSheet(artist: artist, ref: ref),
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

// ── Lidarr search list ────────────────────────────────────────────────────────

class _LidarrSearchList extends ConsumerStatefulWidget {
  const _LidarrSearchList({required this.selectedMbid});

  final String? selectedMbid;

  @override
  ConsumerState<_LidarrSearchList> createState() => _LidarrSearchListState();
}

class _LidarrSearchListState extends ConsumerState<_LidarrSearchList> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<LidarrArtist>? _results;
  bool _searching = false;
  String? _addingMbid;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _lookup(v.trim()),
    );
  }

  Future<void> _lookup(String query) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    try {
      final results = await client.lookupArtists(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _add(LidarrArtist a) async {
    final client = ref.read(lidarrClientProvider);
    final storage = ref.read(secureStorageProvider);
    if (client == null) return;

    final rfId = await storage.read(key: 'lidarr_root_folder_id');
    final rfPath = await storage.read(key: 'lidarr_root_folder_path');
    final qpId = await storage.read(key: 'lidarr_quality_profile_id');

    if (rfId == null || rfPath == null || qpId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Set a root folder and quality profile in Settings → Lidarr first.'),
      ));
      return;
    }

    setState(() => _addingMbid = a.mbid);
    try {
      await client.addArtist(
        mbid: a.mbid,
        name: a.name,
        rootFolderId: int.parse(rfId),
        rootFolderPath: rfPath,
        qualityProfileId: int.parse(qpId),
      );
      if (!mounted) return;
      ref.invalidate(lidarrArtistsProvider);
      _ctrl.clear();
      setState(() {
        _addingMbid = null;
        _results = null;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingMbid = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lidarrByMbid = ref.watch(lidarrArtistByMbidProvider);
    final libraryFilter = ref.watch(lidarrLibraryFilterProvider);
    final isQuerying = _ctrl.text.trim().isNotEmpty;

    return Column(
      children: [
        // Search field — matches the sidebar search style
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(
                  fontSize: 12, color: ColorTokens.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search Lidarr…',
                hintStyle: const TextStyle(
                    fontSize: 12, color: ColorTokens.textSecondary),
                prefixIcon: const Icon(Icons.search,
                    size: 13, color: ColorTokens.textSecondary),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 28, minHeight: 26),
                suffixIcon: isQuerying
                    ? GestureDetector(
                        onTap: () {
                          _ctrl.clear();
                          setState(() {
                            _results = null;
                            _searching = false;
                          });
                        },
                        child: const Icon(Icons.close,
                            size: 11, color: ColorTokens.textSecondary),
                      )
                    : null,
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                filled: true,
                fillColor:
                    ColorTokens.surfaceVariant.withValues(alpha: 0.65),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: ColorTokens.accent.withValues(alpha: 0.4),
                      width: 1),
                ),
              ),
              onChanged: _onChanged,
            ),
          ),
        ),

        // Filter chips — only when not searching
        if (!isQuerying)
          _LidarrLibraryFilterBar(
            current: libraryFilter,
            onSelect: (f) =>
                ref.read(lidarrLibraryFilterProvider.notifier).state = f,
          ),

        // Body
        Expanded(
          child: isQuerying
              ? _buildResults(lidarrByMbid)
              : _buildExisting(),
        ),
      ],
    );
  }

  Widget _buildExisting() {
    final artists = ref.watch(filteredLidarrArtistsProvider);
    if (artists.isEmpty) {
      final customId = ref.watch(selectedCustomFilterIdProvider);
      final libraryFilter = ref.watch(lidarrLibraryFilterProvider);
      final isFiltered =
          customId != null || libraryFilter != LidarrLibraryFilter.all;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            isFiltered
                ? 'No artists match this filter.'
                : 'No artists in Lidarr yet.\nSearch above to add one.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(
          top: 4, bottom: AppConstants.scrollBottomInset),
      itemCount: artists.length,
      itemExtent: 52,
      itemBuilder: (_, i) {
        final a = artists[i];
        return _LidarrOnlyTile(
          artist: a,
          isSelected: a.mbid == widget.selectedMbid,
          onTap: () {
            ref.read(selectedLidarrMbidProvider.notifier).state = a.mbid;
            ref.read(selectedArtistIdProvider.notifier).state = null;
            ref.read(selectedAlbumIdProvider.notifier).state = null;
          },
        );
      },
    );
  }

  Widget _buildResults(Map<String, LidarrArtist> lidarrByMbid) {
    if (_searching && _results == null) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 1.5));
    }
    final results = _results ?? [];
    if (results.isEmpty) {
      return const Center(
        child: Text('No results',
            style: TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(
          top: 4, bottom: AppConstants.scrollBottomInset),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final a = results[i];
        final alreadyAdded =
            a.isInLidarr || lidarrByMbid.containsKey(a.mbid);
        final isAdding = _addingMbid == a.mbid;
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: a.posterUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: a.posterUrl!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const _LidarrAvatarPlaceholder(),
                  ),
                )
              : const _LidarrAvatarPlaceholder(),
          title: Text(
            a.name,
            style: const TextStyle(
                fontSize: 12, color: ColorTokens.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: alreadyAdded
              ? const Icon(Icons.check_circle_outline,
                  size: 16, color: Colors.green)
              : isAdding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 1.5))
                  : TextButton(
                      onPressed: () => _add(a),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        foregroundColor: ColorTokens.accent,
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('Add'),
                    ),
        );
      },
    );
  }
}

// ── Lidarr-only tile ──────────────────────────────────────────────────────────

class _LidarrOnlyTile extends StatelessWidget {
  const _LidarrOnlyTile({
    required this.artist,
    required this.isSelected,
    required this.onTap,
  });

  final LidarrArtist artist;
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
              child: artist.posterUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: CachedNetworkImage(
                        imageUrl: artist.posterUrl!,
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const _LidarrAvatarPlaceholder(),
                      ),
                    )
                  : const _LidarrAvatarPlaceholder(),
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
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _LidarrAvatarPlaceholder extends StatelessWidget {
  const _LidarrAvatarPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person_outline,
          size: 18, color: ColorTokens.textSecondary),
    );
  }
}

// ── Lidarr-only detail panel ──────────────────────────────────────────────────

class _LidarrOnlyDetailPanel extends ConsumerStatefulWidget {
  const _LidarrOnlyDetailPanel({super.key, required this.artist});
  final LidarrArtist artist;

  @override
  ConsumerState<_LidarrOnlyDetailPanel> createState() =>
      _LidarrOnlyDetailPanelState();
}

class _LidarrOnlyDetailPanelState
    extends ConsumerState<_LidarrOnlyDetailPanel> {
  bool _searching = false;
  bool _searched = false;

  Future<void> _triggerSearch() async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _searching = true);
    try {
      await client.triggerArtistSearch(widget.artist.id);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.artist;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: a.posterUrl != null
                      ? CachedNetworkImage(
                          imageUrl: a.posterUrl!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _posterPlaceholder(88),
                        )
                      : _posterPlaceholder(88),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: ColorTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _StatusBadge(
                            label: a.monitored ? 'Monitored' : 'Unmonitored',
                            color: a.monitored ? Colors.green : ColorTokens.textSecondary,
                          ),
                          if (a.status != null)
                            _StatusBadge(
                              label: a.status!,
                              color: ColorTokens.textSecondary,
                            ),
                          const _StatusBadge(
                            label: 'Not in library',
                            color: ColorTokens.accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _searched
                          ? Row(
                              children: const [
                                Icon(Icons.check_circle_outline,
                                    size: 14, color: Colors.green),
                                SizedBox(width: 6),
                                Text(
                                  'Search queued in Lidarr',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.green),
                                ),
                              ],
                            )
                          : FilledButton.icon(
                              onPressed: _searching ? null : _triggerSearch,
                              icon: _searching
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.search, size: 15),
                              label: const Text('Search Missing Albums'),
                              style: FilledButton.styleFrom(
                                backgroundColor: ColorTokens.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
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
        if (a.overview != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 4),
              child: Text(
                a.overview!,
                style: const TextStyle(
                  fontSize: 13,
                  color: ColorTokens.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ),

        // ── Discography from Lidarr ───────────────────────────────────────
        SliverToBoxAdapter(
          child: _LidarrDiscographySection(artist: a),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _posterPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ColorTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.person_outline,
          size: 36, color: ColorTokens.textSecondary),
    );
  }
}

// ── Interactive search sheet ──────────────────────────────────────────────────

void _showInteractiveSearchSheet(
    BuildContext context, int albumId, String albumTitle) {
  showModalBottomSheet(
    context: context,
    backgroundColor: ColorTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      side: BorderSide(color: ColorTokens.glassBorder),
    ),
    isScrollControlled: true,
    builder: (_) => _InteractiveSearchSheet(
      albumId: albumId,
      albumTitle: albumTitle,
    ),
  );
}

class _InteractiveSearchSheet extends ConsumerStatefulWidget {
  const _InteractiveSearchSheet({
    required this.albumId,
    required this.albumTitle,
  });

  final int albumId;
  final String albumTitle;

  @override
  ConsumerState<_InteractiveSearchSheet> createState() =>
      _InteractiveSearchSheetState();
}

class _InteractiveSearchSheetState
    extends ConsumerState<_InteractiveSearchSheet> {
  List<LidarrRelease>? _releases;
  bool _loading = true;
  String? _error;
  String? _grabbingGuid;
  final Set<String> _grabbedGuids = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final releases = await client.searchReleases(widget.albumId);
      // Sort: non-rejected first, then by seeders desc
      releases.sort((a, b) {
        if (a.rejected != b.rejected) return a.rejected ? 1 : -1;
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      });
      if (!mounted) return;
      setState(() {
        _releases = releases;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _grab(LidarrRelease release) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _grabbingGuid = release.guid);
    try {
      await client.grabRelease(release.raw);
      if (!mounted) return;
      setState(() {
        _grabbingGuid = null;
        _grabbedGuids.add(release.guid);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _grabbingGuid = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Grab failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ColorTokens.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.manage_search,
                    size: 16, color: ColorTokens.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.albumTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ColorTokens.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_loading)
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 16, color: ColorTokens.textSecondary),
                    tooltip: 'Refresh',
                    onPressed: _fetch,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: ColorTokens.glassBorder),
          Expanded(child: _buildBody(scrollCtrl)),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController scrollCtrl) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 12)),
        ),
      );
    }
    final releases = _releases ?? [];
    if (releases.isEmpty) {
      return const Center(
        child: Text('No results found from indexers.',
            style:
                TextStyle(fontSize: 13, color: ColorTokens.textSecondary)),
      );
    }
    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: releases.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: ColorTokens.glassBorder),
      itemBuilder: (_, i) => _ReleaseRow(
        release: releases[i],
        isGrabbing: _grabbingGuid == releases[i].guid,
        isGrabbed: _grabbedGuids.contains(releases[i].guid),
        onGrab: () => _grab(releases[i]),
      ),
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({
    required this.release,
    required this.isGrabbing,
    required this.isGrabbed,
    required this.onGrab,
  });

  final LidarrRelease release;
  final bool isGrabbing;
  final bool isGrabbed;
  final VoidCallback onGrab;

  @override
  Widget build(BuildContext context) {
    final r = release;
    final dimmed = r.rejected;

    final metaParts = <String>[
      r.indexer,
      if (r.quality.isNotEmpty) r.quality,
      r.formattedSize,
      '${r.ageInDays}d',
      if (r.protocol == 'torrent' && r.seeders != null)
        '${r.seeders}↑',
    ];

    return Container(
      color: dimmed
          ? Colors.red.withValues(alpha: 0.04)
          : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Protocol icon
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(
              r.protocol == 'torrent'
                  ? Icons.swap_vert
                  : Icons.cloud_outlined,
              size: 14,
              color: dimmed
                  ? ColorTokens.textSecondary.withValues(alpha: 0.4)
                  : ColorTokens.textSecondary,
            ),
          ),

          // Title + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: dimmed
                        ? ColorTokens.textSecondary.withValues(alpha: 0.5)
                        : ColorTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metaParts.join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: ColorTokens.textSecondary
                        .withValues(alpha: dimmed ? 0.4 : 0.8),
                  ),
                ),
                if (r.rejections.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    r.rejections.join(' · '),
                    style: const TextStyle(
                        fontSize: 10, color: Colors.redAccent),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Action
          SizedBox(
            width: 56,
            child: isGrabbed
                ? const Center(
                    child: Icon(Icons.check_circle_outline,
                        size: 18, color: Colors.green))
                : isGrabbing
                    ? const Center(
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 1.5)))
                    : FilledButton(
                        onPressed: r.rejected ? null : onGrab,
                        style: FilledButton.styleFrom(
                          backgroundColor: r.rejected
                              ? ColorTokens.surfaceVariant
                              : ColorTokens.accent,
                          foregroundColor: r.rejected
                              ? ColorTokens.textSecondary
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 6),
                          minimumSize: const Size(48, 28),
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                        child: const Text('Grab'),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Discography from Lidarr (used in _LidarrOnlyDetailPanel) ─────────────────

class _LidarrDiscographySection extends ConsumerStatefulWidget {
  const _LidarrDiscographySection({required this.artist});
  final LidarrArtist artist;

  @override
  ConsumerState<_LidarrDiscographySection> createState() =>
      _LidarrDiscographySectionState();
}

class _LidarrDiscographySectionState
    extends ConsumerState<_LidarrDiscographySection> {
  final Map<int, bool> _searching = {};
  final Set<int> _searched = {};

  Future<void> _searchAlbum(int albumId) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _searching[albumId] = true);
    try {
      await client.triggerAlbumSearch(albumId);
      if (!mounted) return;
      setState(() {
        _searching.remove(albumId);
        _searched.add(albumId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching.remove(albumId));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync =
        ref.watch(lidarrAlbumsByArtistProvider(widget.artist.id));

    return albumsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(28, 20, 28, 0),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (albums) {
        if (albums.isEmpty) return const SizedBox.shrink();

        // Sort: downloaded first, then by year desc
        final sorted = [...albums]..sort((a, b) {
            if (a.hasFile != b.hasFile) return a.hasFile ? -1 : 1;
            final ay = a.year ?? 0;
            final by = b.year ?? 0;
            return by.compareTo(ay);
          });

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1, color: ColorTokens.glassBorder),
              const SizedBox(height: 16),
              Text(
                'Discography in Lidarr (${albums.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ColorTokens.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 12),
              ...sorted.map((album) => _AlbumRow(
                    album: album,
                    isSearching: _searching[album.id] == true,
                    isSearched: _searched.contains(album.id),
                    onSearch: () => _searchAlbum(album.id),
                    onInteractiveSearch: () => _showInteractiveSearchSheet(
                        context, album.id, album.title),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.isSearching,
    required this.isSearched,
    required this.onSearch,
    required this.onInteractiveSearch,
  });

  final LidarrAlbum album;
  final bool isSearching;
  final bool isSearched;
  final VoidCallback onSearch;
  final VoidCallback onInteractiveSearch;

  @override
  Widget build(BuildContext context) {
    final statusColor = album.hasFile ? Colors.green : Colors.orange;
    final statusLabel = album.hasFile ? 'Downloaded' : 'Missing';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Cover thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: album.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: album.coverUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _albumPlaceholder(),
                  )
                : _albumPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.title,
                  style: const TextStyle(
                      fontSize: 13, color: ColorTokens.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (album.year != null)
                      Text(
                        '${album.year}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: ColorTokens.textSecondary),
                      ),
                    if (album.year != null)
                      const Text(' · ',
                          style: TextStyle(
                              fontSize: 11,
                              color: ColorTokens.textSecondary)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style:
                            TextStyle(fontSize: 10, color: statusColor),
                      ),
                    ),
                    if (!album.monitored) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: ColorTokens.textSecondary
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Unmonitored',
                          style: TextStyle(
                              fontSize: 10,
                              color: ColorTokens.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Auto-search (missing albums only)
              if (!album.hasFile)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: isSearched
                      ? const Center(
                          child: Icon(Icons.check_circle_outline,
                              size: 16, color: Colors.green))
                      : isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search,
                                  size: 16,
                                  color: ColorTokens.textSecondary),
                              tooltip: 'Auto search',
                              padding: EdgeInsets.zero,
                              onPressed: onSearch,
                            ),
                ),
              // Interactive search (always visible)
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: const Icon(Icons.manage_search,
                      size: 16, color: ColorTokens.textSecondary),
                  tooltip: 'Interactive search',
                  padding: EdgeInsets.zero,
                  onPressed: onInteractiveSearch,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _albumPlaceholder() => Container(
        width: 40,
        height: 40,
        color: ColorTokens.surfaceVariant,
        child: const Icon(Icons.album_outlined,
            size: 20, color: ColorTokens.textSecondary),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

// ── Lidarr badge (already in Lidarr) ─────────────────────────────────────────

class _LidarrBadge extends StatelessWidget {
  const _LidarrBadge({required this.lidarrArtist});
  final LidarrArtist lidarrArtist;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 13, color: Colors.green),
          const SizedBox(width: 5),
          Text(
            'In Lidarr',
            style: const TextStyle(fontSize: 12, color: Colors.green),
          ),
        ],
      ),
    );
  }
}

// ── Lidarr lookup bottom sheet ────────────────────────────────────────────────

class _LidarrLookupSheet extends StatefulWidget {
  const _LidarrLookupSheet({required this.artist, required this.ref});
  final Artist artist;
  final WidgetRef ref;

  @override
  State<_LidarrLookupSheet> createState() => _LidarrLookupSheetState();
}

class _LidarrLookupSheetState extends State<_LidarrLookupSheet> {
  List<LidarrArtist>? _results;
  bool _loading = true;
  String? _error;
  String? _addingMbid;
  String? _addedMbid;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    final client = widget.ref.read(lidarrClientProvider);
    if (client == null) return;
    try {
      final results = await client.lookupArtists(widget.artist.name);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _add(LidarrArtist lidarrArtist) async {
    final client = widget.ref.read(lidarrClientProvider);
    final storage = widget.ref.read(secureStorageProvider);
    if (client == null) return;

    final rfId = await storage.read(key: 'lidarr_root_folder_id');
    final rfPath = await storage.read(key: 'lidarr_root_folder_path');
    final qpId = await storage.read(key: 'lidarr_quality_profile_id');

    if (rfId == null || rfPath == null || qpId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Set a root folder and quality profile in Settings → Lidarr first.'),
      ));
      return;
    }

    setState(() => _addingMbid = lidarrArtist.mbid);
    try {
      await client.addArtist(
        mbid: lidarrArtist.mbid,
        name: lidarrArtist.name,
        rootFolderId: int.parse(rfId),
        rootFolderPath: rfPath,
        qualityProfileId: int.parse(qpId),
      );
      if (!mounted) return;
      widget.ref.invalidate(lidarrArtistsProvider);
      setState(() {
        _addingMbid = null;
        _addedMbid = lidarrArtist.mbid;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingMbid = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ColorTokens.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add "${widget.artist.name}" to Lidarr',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ColorTokens.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select the correct match from the Lidarr lookup.',
              style:
                  TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: ColorTokens.glassBorder),
          Expanded(
            child: _buildBody(scrollCtrl),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController scrollCtrl) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: const TextStyle(
                color: Colors.redAccent, fontSize: 12)),
      );
    }
    final results = _results ?? [];
    if (results.isEmpty) {
      return const Center(
        child: Text('No results found.',
            style: TextStyle(color: ColorTokens.textSecondary)),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final a = results[i];
        final isAdding = _addingMbid == a.mbid;
        final isAdded = _addedMbid == a.mbid || a.isInLidarr;
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: a.posterUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CachedNetworkImage(
                    imageUrl: a.posterUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _FallbackAvatar(),
                  ),
                )
              : const _FallbackAvatar(),
          title: Text(
            a.name,
            style: const TextStyle(
                fontSize: 13, color: ColorTokens.textPrimary),
          ),
          subtitle: a.overview != null
              ? Text(
                  a.overview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary),
                )
              : null,
          trailing: isAdded
              ? const Icon(Icons.check_circle_outline,
                  size: 18, color: Colors.green)
              : isAdding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 1.5))
                  : FilledButton(
                      onPressed: () => _add(a),
                      style: FilledButton.styleFrom(
                        backgroundColor: ColorTokens.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Add'),
                    ),
        );
      },
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  const _FallbackAvatar();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: ColorTokens.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person_outline,
          size: 20, color: ColorTokens.textSecondary),
    );
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
  const _AlbumSection({required this.album, this.lidarrAlbum});

  final Album album;
  final LidarrAlbum? lidarrAlbum;

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
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SyncDot(
                      color: Colors.green.withValues(alpha: 0.85),
                      size: 8,
                    ),
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
                final isActive = queue.any((t) =>
                    t.song.id == song.id &&
                    t.status == TransferStatus.inProgress);
                final isQueued = !isActive &&
                    queue.any((t) =>
                        t.song.id == song.id &&
                        t.status == TransferStatus.queued);
                final isOnDevice = settings != null &&
                    songExistsOnDevice(song, settings);
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
        if (lidarrAlbum != null)
          const PopupMenuItem(
            value: 'interactive_search',
            child: _MenuRow(
                icon: Icons.manage_search, label: 'Interactive Search'),
          ),
      ],
    );
    if (!context.mounted) return;

    if (result == 'interactive_search' && lidarrAlbum != null) {
      _showInteractiveSearchSheet(context, lidarrAlbum!.id, album.name);
      return;
    }

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
