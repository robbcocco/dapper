import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/lidarr/lidarr_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/lidarr_models.dart';

class LidarrPage extends ConsumerWidget {
  const LidarrPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lidarrConnected = ref.watch(lidarrClientProvider) != null;

    if (!lidarrConnected) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: ColorTokens.textSecondary),
            SizedBox(height: 16),
            Text(
              'Lidarr not configured',
              style: TextStyle(fontSize: 15, color: ColorTokens.textSecondary),
            ),
            SizedBox(height: 6),
            Text(
              'Add a Lidarr instance in Settings.',
              style: TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
            ),
          ],
        ),
      );
    }

    final selectedMbid = ref.watch(selectedLidarrMbidProvider);

    return Row(
      children: [
        SizedBox(
          width: AppConstants.artistTreeWidth,
          child: _LidarrListPanel(selectedMbid: selectedMbid),
        ),
        Container(width: 1, color: ColorTokens.glassBorder),
        Expanded(
          child: selectedMbid != null
              ? _LidarrDetailLoader(mbid: selectedMbid)
              : const _EmptyDetail(),
        ),
      ],
    );
  }
}

// Loads the full LidarrArtist from the mbid and renders the detail panel.
class _LidarrDetailLoader extends ConsumerWidget {
  const _LidarrDetailLoader({required this.mbid});
  final String mbid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(lidarrArtistsProvider).value ?? [];
    final artist = artists.cast<LidarrArtist?>().firstWhere(
      (a) => a?.mbid == mbid,
      orElse: () => null,
    );
    if (artist == null) return const _EmptyDetail();
    return _LidarrOnlyDetailPanel(
      key: ValueKey('lidarr_$mbid'),
      artist: artist,
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

// ── Left panel: search + list ─────────────────────────────────────────────────

class _LidarrListPanel extends ConsumerStatefulWidget {
  const _LidarrListPanel({required this.selectedMbid});
  final String? selectedMbid;

  @override
  ConsumerState<_LidarrListPanel> createState() => _LidarrListPanelState();
}

class _LidarrListPanelState extends ConsumerState<_LidarrListPanel> {
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
      setState(() { _results = null; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _lookup(v.trim()));
  }

  Future<void> _lookup(String query) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    try {
      final results = await client.lookupArtists(query);
      if (!mounted) return;
      setState(() { _results = results; _searching = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _add(LidarrArtist a) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;

    final instance = ref.read(selectedLidarrInstanceProvider);
    if (instance?.defaultRootFolderId == null ||
        instance?.defaultRootFolderPath == null ||
        instance?.defaultQualityProfileId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Set a root folder and quality profile in Settings → Lidarr first.'),
      ));
      return;
    }

    setState(() => _addingMbid = a.mbid);
    try {
      await client.addArtist(
        mbid: a.mbid,
        name: a.name,
        rootFolderId: instance!.defaultRootFolderId!,
        rootFolderPath: instance.defaultRootFolderPath!,
        qualityProfileId: instance.defaultQualityProfileId!,
      );
      if (!mounted) return;
      ref.invalidate(lidarrArtistsProvider);
      _ctrl.clear();
      setState(() { _addingMbid = null; _results = null; _searching = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingMbid = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lidarrByMbid = ref.watch(lidarrArtistByMbidProvider);
    final libraryFilter = ref.watch(lidarrLibraryFilterProvider);
    final isQuerying = _ctrl.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 12, color: ColorTokens.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search Lidarr…',
                hintStyle: const TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
                prefixIcon: const Icon(Icons.search, size: 13, color: ColorTokens.textSecondary),
                prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                suffixIcon: isQuerying
                    ? GestureDetector(
                        onTap: () {
                          _ctrl.clear();
                          setState(() { _results = null; _searching = false; });
                        },
                        child: const Icon(Icons.close, size: 11, color: ColorTokens.textSecondary),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                filled: true,
                fillColor: ColorTokens.surfaceVariant.withValues(alpha: 0.65),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: ColorTokens.accent.withValues(alpha: 0.4), width: 1),
                ),
              ),
              onChanged: _onChanged,
            ),
          ),
        ),
        if (!isQuerying)
          _LidarrLibraryFilterBar(
            current: libraryFilter,
            onSelect: (f) => ref.read(lidarrLibraryFilterProvider.notifier).state = f,
          ),
        Expanded(
          child: isQuerying ? _buildResults(lidarrByMbid) : _buildExisting(),
        ),
      ],
    );
  }

  Widget _buildExisting() {
    final artists = ref.watch(filteredLidarrArtistsProvider);
    if (artists.isEmpty) {
      final customId = ref.watch(selectedCustomFilterIdProvider);
      final libraryFilter = ref.watch(lidarrLibraryFilterProvider);
      final isFiltered = customId != null || libraryFilter != LidarrLibraryFilter.all;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            isFiltered
                ? 'No artists match this filter.'
                : 'No artists in Lidarr yet.\nSearch above to add one.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: AppConstants.scrollBottomInset),
      itemCount: artists.length,
      itemExtent: 52,
      itemBuilder: (_, i) {
        final a = artists[i];
        return _LidarrArtistTile(
          artist: a,
          isSelected: a.mbid == widget.selectedMbid,
          onTap: () {
            ref.read(selectedLidarrMbidProvider.notifier).state = a.mbid;
          },
        );
      },
    );
  }

  Widget _buildResults(Map<String, LidarrArtist> lidarrByMbid) {
    if (_searching && _results == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
    }
    final results = _results ?? [];
    if (results.isEmpty) {
      return const Center(
        child: Text('No results', style: TextStyle(fontSize: 12, color: ColorTokens.textSecondary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: AppConstants.scrollBottomInset),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final a = results[i];
        final alreadyAdded = a.isInLidarr || lidarrByMbid.containsKey(a.mbid);
        final isAdding = _addingMbid == a.mbid;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: a.posterUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: a.posterUrl!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _AvatarPlaceholder(),
                  ),
                )
              : const _AvatarPlaceholder(),
          title: Text(a.name,
              style: const TextStyle(fontSize: 12, color: ColorTokens.textPrimary),
              overflow: TextOverflow.ellipsis),
          trailing: alreadyAdded
              ? const Icon(Icons.check_circle_outline, size: 16, color: Colors.green)
              : isAdding
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))
                  : TextButton(
                      onPressed: () => _add(a),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

// ── Filter bar ────────────────────────────────────────────────────────────────

class _LidarrLibraryFilterBar extends ConsumerWidget {
  const _LidarrLibraryFilterBar({required this.current, required this.onSelect});
  final LidarrLibraryFilter current;
  final ValueChanged<LidarrLibraryFilter> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customFilters = ref.watch(lidarrCustomFiltersProvider).value ?? [];
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
            ...LidarrLibraryFilter.values.map((f) => _FilterChip(
                  label: switch (f) {
                    LidarrLibraryFilter.all => 'All',
                    LidarrLibraryFilter.monitored => 'Monitored',
                    LidarrLibraryFilter.unmonitored => 'Unmonitored',
                    LidarrLibraryFilter.missing => 'Missing',
                  },
                  selected: selectedCustomId == null && current == f,
                  onTap: () {
                    ref.read(selectedCustomFilterIdProvider.notifier).state = null;
                    onSelect(f);
                  },
                )),
            ...customFilters.map((cf) => _FilterChip(
                  label: cf.label,
                  selected: selectedCustomId == cf.id,
                  onTap: () => ref.read(selectedCustomFilterIdProvider.notifier).state = cf.id,
                )),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? ColorTokens.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? ColorTokens.accent : ColorTokens.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── Artist tile ───────────────────────────────────────────────────────────────

class _LidarrArtistTile extends StatelessWidget {
  const _LidarrArtistTile({required this.artist, required this.isSelected, required this.onTap});
  final LidarrArtist artist;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: isSelected
            ? BoxDecoration(color: ColorTokens.selectionBackground, borderRadius: BorderRadius.circular(8))
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
                        errorWidget: (_, __, ___) => const _AvatarPlaceholder(),
                      ),
                    )
                  : const _AvatarPlaceholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                artist.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? ColorTokens.textPrimary : ColorTokens.textSecondary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: ColorTokens.surfaceVariant, shape: BoxShape.circle),
      child: const Icon(Icons.person_outline, size: 18, color: ColorTokens.textSecondary),
    );
  }
}

// ── Detail panel ──────────────────────────────────────────────────────────────

class _LidarrOnlyDetailPanel extends ConsumerStatefulWidget {
  const _LidarrOnlyDetailPanel({super.key, required this.artist});
  final LidarrArtist artist;

  @override
  ConsumerState<_LidarrOnlyDetailPanel> createState() => _LidarrOnlyDetailPanelState();
}

class _LidarrOnlyDetailPanelState extends ConsumerState<_LidarrOnlyDetailPanel> {
  bool _searching = false;
  bool _searched = false;

  Future<void> _triggerSearch() async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _searching = true);
    try {
      await client.triggerArtistSearch(widget.artist.id);
      if (!mounted) return;
      setState(() { _searching = false; _searched = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: a.posterUrl != null
                      ? CachedNetworkImage(
                          imageUrl: a.posterUrl!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _posterPlaceholder(88),
                        )
                      : _posterPlaceholder(88),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold, color: ColorTokens.textPrimary)),
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
                            _StatusBadge(label: a.status!, color: ColorTokens.textSecondary),
                          const _StatusBadge(label: 'Not in library', color: ColorTokens.accent),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _searched
                          ? Row(
                              children: const [
                                Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                                SizedBox(width: 6),
                                Text('Search queued in Lidarr',
                                    style: TextStyle(fontSize: 12, color: Colors.green)),
                              ],
                            )
                          : FilledButton.icon(
                              onPressed: _searching ? null : _triggerSearch,
                              icon: _searching
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                  : const Icon(Icons.search, size: 15),
                              label: const Text('Search Missing Albums'),
                              style: FilledButton.styleFrom(
                                backgroundColor: ColorTokens.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        const SliverToBoxAdapter(child: Divider(height: 1, color: ColorTokens.divider)),
        if (a.overview != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 4),
              child: Text(a.overview!,
                  style: const TextStyle(fontSize: 13, color: ColorTokens.textSecondary, height: 1.6)),
            ),
          ),
        SliverToBoxAdapter(child: _LidarrDiscographySection(artist: a)),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _posterPlaceholder(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: ColorTokens.surfaceVariant, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.person_outline, size: 36, color: ColorTokens.textSecondary),
      );
}

// ── Discography section ───────────────────────────────────────────────────────

class _LidarrDiscographySection extends ConsumerStatefulWidget {
  const _LidarrDiscographySection({required this.artist});
  final LidarrArtist artist;

  @override
  ConsumerState<_LidarrDiscographySection> createState() => _LidarrDiscographySectionState();
}

class _LidarrDiscographySectionState extends ConsumerState<_LidarrDiscographySection> {
  final Map<int, bool> _searching = {};
  final Set<int> _searched = {};

  Future<void> _searchAlbum(int albumId) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _searching[albumId] = true);
    try {
      await client.triggerAlbumSearch(albumId);
      if (!mounted) return;
      setState(() { _searching.remove(albumId); _searched.add(albumId); });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching.remove(albumId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(lidarrAlbumsByArtistProvider(widget.artist.id));

    return albumsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(28, 20, 28, 0),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (albums) {
        if (albums.isEmpty) return const SizedBox.shrink();

        // Group by type, preserving display order.
        final groups = <LidarrAlbumType, List<LidarrAlbum>>{};
        for (final type in LidarrAlbumType.values) {
          final inGroup = albums.where((a) => a.albumType == type).toList()
            ..sort((a, b) {
              if (a.hasFile != b.hasFile) return a.hasFile ? -1 : 1;
              return (b.year ?? 0).compareTo(a.year ?? 0);
            });
          if (inGroup.isNotEmpty) groups[type] = inGroup;
        }

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
                    letterSpacing: 0.4),
              ),
              for (final entry in groups.entries) ...[
                const SizedBox(height: 20),
                _SectionHeader(label: entry.key.label, count: entry.value.length),
                const SizedBox(height: 10),
                ...entry.value.map((album) => _AlbumRow(
                      album: album,
                      isSearching: _searching[album.id] == true,
                      isSearched: _searched.contains(album.id),
                      onSearch: () => _searchAlbum(album.id),
                      onInteractiveSearch: () =>
                          showInteractiveSearchSheet(context, album.id, album.title),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ColorTokens.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            color: ColorTokens.textSecondary.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1, color: ColorTokens.glassBorder)),
      ],
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
                Text(album.title,
                    style: const TextStyle(fontSize: 13, color: ColorTokens.textPrimary),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (album.year != null)
                      Text('${album.year}',
                          style: const TextStyle(fontSize: 11, color: ColorTokens.textSecondary)),
                    if (album.year != null)
                      const Text(' · ',
                          style: TextStyle(fontSize: 11, color: ColorTokens.textSecondary)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor)),
                    ),
                    if (!album.monitored) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: ColorTokens.textSecondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('Unmonitored',
                            style: TextStyle(fontSize: 10, color: ColorTokens.textSecondary)),
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
              if (!album.hasFile)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: isSearched
                      ? const Center(
                          child: Icon(Icons.check_circle_outline, size: 16, color: Colors.green))
                      : isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(strokeWidth: 1.5))
                          : IconButton(
                              icon: const Icon(Icons.search, size: 16, color: ColorTokens.textSecondary),
                              tooltip: 'Auto search',
                              padding: EdgeInsets.zero,
                              onPressed: onSearch,
                            ),
                ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: const Icon(Icons.manage_search, size: 16, color: ColorTokens.textSecondary),
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
        child: const Icon(Icons.album_outlined, size: 20, color: ColorTokens.textSecondary),
      );
}

// ── Interactive search sheet (also imported by artists_page) ──────────────────

void showInteractiveSearchSheet(BuildContext context, int albumId, String albumTitle) {
  showModalBottomSheet(
    context: context,
    backgroundColor: ColorTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      side: BorderSide(color: ColorTokens.glassBorder),
    ),
    isScrollControlled: true,
    builder: (_) => _InteractiveSearchSheet(albumId: albumId, albumTitle: albumTitle),
  );
}

class _InteractiveSearchSheet extends ConsumerStatefulWidget {
  const _InteractiveSearchSheet({required this.albumId, required this.albumTitle});
  final int albumId;
  final String albumTitle;

  @override
  ConsumerState<_InteractiveSearchSheet> createState() => _InteractiveSearchSheetState();
}

class _InteractiveSearchSheetState extends ConsumerState<_InteractiveSearchSheet> {
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
    setState(() { _loading = true; _error = null; });
    try {
      final releases = await client.searchReleases(widget.albumId);
      releases.sort((a, b) {
        if (a.rejected != b.rejected) return a.rejected ? 1 : -1;
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      });
      if (!mounted) return;
      setState(() { _releases = releases; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _grab(LidarrRelease release) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _grabbingGuid = release.guid);
    try {
      await client.grabRelease(release.raw);
      if (!mounted) return;
      setState(() { _grabbingGuid = null; _grabbedGuids.add(release.guid); });
    } catch (e) {
      if (!mounted) return;
      setState(() => _grabbingGuid = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Grab failed: $e')));
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
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.manage_search, size: 16, color: ColorTokens.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.albumTitle,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: ColorTokens.textPrimary),
                      overflow: TextOverflow.ellipsis),
                ),
                if (!_loading)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: ColorTokens.textSecondary),
                    tooltip: 'Refresh',
                    onPressed: _fetch,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      );
    }
    final releases = _releases ?? [];
    if (releases.isEmpty) {
      return const Center(
        child: Text('No results found from indexers.',
            style: TextStyle(fontSize: 13, color: ColorTokens.textSecondary)),
      );
    }
    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: releases.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: ColorTokens.glassBorder),
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
      if (r.protocol == 'torrent' && r.seeders != null) '${r.seeders}↑',
    ];

    return Container(
      color: dimmed ? Colors.red.withValues(alpha: 0.04) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(
              r.protocol == 'torrent' ? Icons.swap_vert : Icons.cloud_outlined,
              size: 14,
              color: dimmed ? ColorTokens.textSecondary.withValues(alpha: 0.4) : ColorTokens.textSecondary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: dimmed
                            ? ColorTokens.textSecondary.withValues(alpha: 0.5)
                            : ColorTokens.textPrimary)),
                const SizedBox(height: 3),
                Text(metaParts.join(' · '),
                    style: TextStyle(
                        fontSize: 11,
                        color: ColorTokens.textSecondary.withValues(alpha: dimmed ? 0.4 : 0.8))),
                if (r.rejections.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(r.rejections.join(' · '),
                      style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: isGrabbed
                ? const Center(child: Icon(Icons.check_circle_outline, size: 18, color: Colors.green))
                : isGrabbing
                    ? const Center(
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.5)))
                    : FilledButton(
                        onPressed: r.rejected ? null : onGrab,
                        style: FilledButton.styleFrom(
                          backgroundColor: r.rejected ? ColorTokens.surfaceVariant : ColorTokens.accent,
                          foregroundColor: r.rejected ? ColorTokens.textSecondary : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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

// ── Status badge ──────────────────────────────────────────────────────────────

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
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
