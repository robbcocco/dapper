import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/artist_sync_provider.dart';
import '../../../application/device/device_settings_notifier.dart';
import '../../../domain/models/device_settings.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/lidarr/lidarr_notifier.dart';
import '../../../application/playback/playback_notifier.dart';
import '../lidarr/lidarr_page.dart' show showInteractiveSearchSheet;
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/album.dart';
import '../../../domain/models/artist.dart';
import '../../../domain/models/connected_device.dart';
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
            _ArtistListPanel(artists: list, selectedId: selectedArtistId),
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
  const _ArtistListPanel({required this.artists, required this.selectedId});

  final List<Artist> artists;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceSync = ref.watch(artistSyncProvider).valueOrNull ?? {};

    return SizedBox(
      width: AppConstants.artistTreeWidth,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: AppConstants.scrollBottomInset),
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
            },
            onSecondaryTapUp: (d) =>
                _showArtistMenu(context, ref, artist, d.globalPosition),
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
    this.syncStatus,
    this.onSecondaryTapUp,
  });

  final Artist artist;
  final bool isSelected;
  final VoidCallback onTap;
  final ArtistSyncStatus? syncStatus;
  final void Function(TapUpDetails)? onSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: onSecondaryTapUp,
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
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];

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
                              if (devices.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _ActionButton(
                                  icon: Icons.download,
                                  label: 'Transfer All',
                                  primary: true,
                                  onPressed: () => _pickAndTransferAll(
                                      context, ref, devices, albums),
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

  Future<void> _pickAndTransferAll(
    BuildContext context,
    WidgetRef ref,
    List<ConnectedDevice> devices,
    List<Album> albums,
  ) async {
    final devicePath = await _pickDevicePath(context, devices);
    if (devicePath == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final settings = ref.read(deviceSettingsProvider(devicePath));
    final allSongs = <Song>[];
    final expectedCounts = <String, int>{};
    for (final album in albums) {
      final full = await repo.getAlbum(album.id);
      allSongs.addAll(full.songs);
      final folder = buildAlbumFolder(album.artist, album.name, album.year, settings);
      if (folder != null) expectedCounts[folder] = full.songCount;
    }
    if (allSongs.isEmpty) return;
    ref
        .read(transferQueueProvider.notifier)
        .enqueue(allSongs, devicePath, repo.downloadUri,
            expectedAlbumSongCounts: expectedCounts);
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
    if (client == null) return;

    final instance = widget.ref.read(selectedLidarrInstanceProvider);
    if (instance?.defaultRootFolderId == null ||
        instance?.defaultRootFolderPath == null ||
        instance?.defaultQualityProfileId == null) {
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
        rootFolderId: instance!.defaultRootFolderId!,
        rootFolderPath: instance.defaultRootFolderPath!,
        qualityProfileId: instance.defaultQualityProfileId!,
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
    final device = ref.watch(selectedDeviceProvider);
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    final albumSync = settings != null
        ? albumSyncOnDevice(album.artist, album.name, album.year, album.songCount, settings)
        : AlbumSyncStatus.absent;
    // Only rebuild when this album's transfer status changes, not on every
    // progress-byte tick. Without .select() every progress update (200 ms)
    // would re-run albumSyncOnDevice (file I/O) for every visible album section.
    final (isAlbumActive, isAlbumQueued) = ref.watch(
      transferQueueProvider.select((q) {
        final active = q.any((t) =>
            t.song.albumId == album.id && t.status == TransferStatus.inProgress);
        return (active, !active && q.any((t) =>
            t.song.albumId == album.id && t.status == TransferStatus.queued));
      }),
    );
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Album header
        GestureDetector(
          onTap: () =>
              ref.read(selectedAlbumIdProvider.notifier).state = album.id,
          onSecondaryTapUp: (d) =>
              _showMenu(context, ref, devices, d.globalPosition),
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
                if (isAlbumActive || isAlbumQueued)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SyncDot(
                      color: Colors.blue.withValues(alpha: 0.85),
                      pulse: isAlbumActive,
                      size: 8,
                    ),
                  )
                else if (albumSync == AlbumSyncStatus.full)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SyncDot(
                      color: Colors.green.withValues(alpha: 0.85),
                      size: 8,
                    ),
                  )
                else if (albumSync == AlbumSyncStatus.partial)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SyncDot(
                      color: Colors.orange.withValues(alpha: 0.85),
                      size: 8,
                    ),
                  ),
                GestureDetector(
                  onTapDown: (d) =>
                      _showMenu(context, ref, devices, d.globalPosition),
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
              children: full.songs.asMap().entries.map((e) =>
                _AlbumSongStatusRow(
                  key: ValueKey(e.value.id),
                  song: e.value,
                  allSongs: full.songs,
                  index: e.key,
                  settings: settings,
                ),
              ).toList(),
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
    List<ConnectedDevice> devices,
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
        for (final d in devices)
          PopupMenuItem(
            value: 'transfer:${d.path}',
            child: _MenuRow(
                icon: Icons.download,
                label: devices.length == 1
                    ? 'Transfer Album'
                    : 'Transfer to ${d.label}'),
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
      showInteractiveSearchSheet(context, lidarrAlbum!.id, album.name);
      return;
    }

    if (result == 'open') {
      ref.read(selectedAlbumIdProvider.notifier).state = album.id;
      return;
    }

    if (result == 'info') {
      final full = await ref.read(albumProvider(album.id).future);
      if (full == null || !context.mounted) return;
      unawaited(AlbumInfoDialog.show(context, full));
      return;
    }

    if (result == 'play') {
      final full = await ref.read(albumProvider(album.id).future);
      if (full == null || !context.mounted) return;
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
      final folder = buildAlbumFolder(album.artist, album.name, album.year, settings);
      final expectedCounts = folder != null ? {folder: full.songCount} : null;
      ref
          .read(transferQueueProvider.notifier)
          .enqueue(full.songs, devicePath, repo.downloadUri,
              expectedAlbumSongCounts: expectedCounts);
    } else if (result == 'playlist') {
      final full = await ref.read(albumProvider(album.id).future);
      if (full == null || !context.mounted) return;
      unawaited(showAddToPlaylistDialog(
          context, ref, full.songs.map((s) => s.id).toList()));
    }
  }
}

// ── Per-song row in the artist detail album section ──────────────────────────
// Extracted to its own ConsumerWidget so each row can use .select() on the
// transfer queue — only rebuilding (and re-running songExistsOnDevice) when
// THIS specific song's status changes, not on every 200 ms progress tick.

class _AlbumSongStatusRow extends ConsumerWidget {
  const _AlbumSongStatusRow({
    super.key,
    required this.song,
    required this.allSongs,
    required this.index,
    this.settings,
  });

  final Song song;
  final List<Song> allSongs;
  final int index;
  final DeviceSettings? settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (isActive, isQueued) = ref.watch(
      transferQueueProvider.select((q) {
        final active = q.any((t) =>
            t.song.id == song.id && t.status == TransferStatus.inProgress);
        return (active, !active && q.any((t) =>
            t.song.id == song.id && t.status == TransferStatus.queued));
      }),
    );
    final isOnDevice = settings != null && songExistsOnDevice(song, settings!);

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
      index: index,
      trailing: trailing,
      showArtist: false,
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playSong(song, queue: allSongs, index: index),
      onAddToPlaylist: () =>
          showAddToPlaylistDialog(context, ref, [song.id]),
      onGetInfo: () => showSongMetadataDialog(context, song),
    );
  }
}

Future<void> _showArtistMenu(
  BuildContext context,
  WidgetRef ref,
  Artist artist,
  Offset pos,
) async {
  final devices = ref.read(connectedDevicesProvider).valueOrNull ?? [];

  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
    color: ColorTokens.surface,
    items: [
      const PopupMenuItem(
        value: 'play',
        child: _MenuRow(icon: Icons.play_arrow, label: 'Play All'),
      ),
      for (final d in devices)
        PopupMenuItem(
          value: 'transfer:${d.path}',
          child: _MenuRow(
            icon: Icons.download,
            label: devices.length == 1
                ? 'Transfer All'
                : 'Transfer to ${d.label}',
          ),
        ),
    ],
  );
  if (!context.mounted) return;

  if (result == 'play') {
    unawaited(ref.read(playbackProvider.notifier).playArtist(artist.id));
  } else if (result != null && result.startsWith('transfer:')) {
    final devicePath = result.substring(9);
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final settings = ref.read(deviceSettingsProvider(devicePath));
    final albums = await ref.read(albumsByArtistProvider(artist.id).future);
    if (!context.mounted) return;
    final allSongs = <Song>[];
    final expectedCounts = <String, int>{};
    for (final album in albums) {
      final full = await repo.getAlbum(album.id);
      allSongs.addAll(full.songs);
      final folder =
          buildAlbumFolder(album.artist, album.name, album.year, settings);
      if (folder != null) expectedCounts[folder] = full.songCount;
    }
    if (allSongs.isEmpty) return;
    ref.read(transferQueueProvider.notifier).enqueue(
          allSongs,
          devicePath,
          repo.downloadUri,
          expectedAlbumSongCounts: expectedCounts,
        );
  }
}

Future<String?> _pickDevicePath(
  BuildContext context,
  List<ConnectedDevice> devices,
) async {
  if (devices.isEmpty) return null;
  if (devices.length == 1) return devices.first.path;
  final result = await showDialog<ConnectedDevice>(
    context: context,
    builder: (_) => SimpleDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Choose device',
          style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
      children: devices
          .map((d) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, d),
                child: Text(d.label,
                    style: const TextStyle(
                        color: ColorTokens.textPrimary, fontSize: 13)),
              ))
          .toList(),
    ),
  );
  return result?.path;
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
