import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/models/artist.dart';
import '../../domain/models/lidarr_models.dart';
import '../library/library_notifier.dart';
import '../providers/providers.dart';

// ── Artists ───────────────────────────────────────────────────────────────────

final lidarrArtistsProvider = FutureProvider<List<LidarrArtist>>((ref) async {
  final client = ref.watch(lidarrClientProvider);
  if (client == null) return [];
  final artists = await client.getArtists();
  return artists..sort((a, b) => a.name.compareTo(b.name));
});

/// MBID → LidarrArtist map for O(1) cross-reference with Navidrome artists.
final lidarrArtistByMbidProvider = Provider<Map<String, LidarrArtist>>((ref) {
  final artists = ref.watch(lidarrArtistsProvider).value ?? [];
  return {
    for (final a in artists)
      if (a.mbid.isNotEmpty) a.mbid: a,
  };
});

/// Lidarr artists that have no matching Navidrome artist by MBID.
/// These represent monitored artists not yet in the local library.
final lidarrOnlyArtistsProvider = Provider<List<LidarrArtist>>((ref) {
  final lidarrArtists = ref.watch(lidarrArtistsProvider).value ?? [];
  final navArtists = ref.watch(artistsProvider).value ?? [];
  final navMbids = navArtists
      .map((Artist a) => a.musicBrainzId)
      .whereType<String>()
      .toSet();
  return lidarrArtists
      .where((a) => a.isInLidarr && !navMbids.contains(a.mbid))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

// ── Selection ─────────────────────────────────────────────────────────────────

/// MBID of the selected Lidarr-only artist (null = none selected).
final selectedLidarrMbidProvider = StateProvider<String?>((_) => null);

// ── Sidebar filter (All artists / Lidarr view) ────────────────────────────────

enum LidarrArtistFilter { all, lidarr }

final lidarrArtistFilterProvider =
    StateProvider<LidarrArtistFilter>((_) => LidarrArtistFilter.all);

// ── Library filter (within the Lidarr artist list) ────────────────────────────

enum LidarrLibraryFilter { all, monitored, unmonitored, missing }

final lidarrLibraryFilterProvider =
    StateProvider<LidarrLibraryFilter>((_) => LidarrLibraryFilter.all);

/// Custom filters saved in Lidarr (type = artistIndex).
final lidarrCustomFiltersProvider =
    FutureProvider<List<LidarrCustomFilter>>((ref) async {
  final client = ref.watch(lidarrClientProvider);
  if (client == null) return [];
  return client.getCustomFilters();
});

/// ID of the currently active custom filter (null = use built-in filter).
final selectedCustomFilterIdProvider = StateProvider<int?>((_) => null);

/// All Lidarr artists after applying whichever filter is active.
final filteredLidarrArtistsProvider = Provider<List<LidarrArtist>>((ref) {
  final all = ref.watch(lidarrArtistsProvider).value ?? [];
  final customId = ref.watch(selectedCustomFilterIdProvider);

  if (customId != null) {
    final customs =
        ref.watch(lidarrCustomFiltersProvider).value ?? [];
    final cf = customs.where((f) => f.id == customId).firstOrNull;
    return cf != null ? all.where((a) => cf.matches(a)).toList() : all;
  }

  final filter = ref.watch(lidarrLibraryFilterProvider);
  return switch (filter) {
    LidarrLibraryFilter.all => all,
    LidarrLibraryFilter.monitored => all.where((a) => a.monitored).toList(),
    LidarrLibraryFilter.unmonitored =>
      all.where((a) => !a.monitored).toList(),
    LidarrLibraryFilter.missing => all.where((a) => a.isMissing).toList(),
  };
});

// ── Albums by artist ──────────────────────────────────────────────────────────

final lidarrAlbumsByArtistProvider =
    FutureProvider.family<List<LidarrAlbum>, int>((ref, artistId) async {
  final client = ref.watch(lidarrClientProvider);
  if (client == null) return [];
  return client.getAlbumsByArtist(artistId);
});

// ── Root folders ──────────────────────────────────────────────────────────────

final lidarrRootFoldersProvider =
    FutureProvider<List<LidarrRootFolder>>((ref) async {
  final client = ref.watch(lidarrClientProvider);
  if (client == null) return [];
  return client.getRootFolders();
});

// ── Quality profiles ──────────────────────────────────────────────────────────

final lidarrQualityProfilesProvider =
    FutureProvider<List<LidarrQualityProfile>>((ref) async {
  final client = ref.watch(lidarrClientProvider);
  if (client == null) return [];
  return client.getQualityProfiles();
});
