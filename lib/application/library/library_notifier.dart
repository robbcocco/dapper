import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/album.dart';
import '../../domain/models/artist.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/search_results.dart';
import '../../domain/models/song.dart';
import '../providers/providers.dart';

// ── Artists ───────────────────────────────────────────────────────────────────

final artistsProvider = FutureProvider<List<Artist>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null) return [];
  return repo.getArtists();
});

// ── Albums ────────────────────────────────────────────────────────────────────

final albumsByArtistProvider =
    FutureProvider.family<List<Album>, String>((ref, artistId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null) return [];
  return repo.getAlbumsByArtist(artistId);
});

final albumProvider =
    FutureProvider.family<Album?, String>((ref, albumId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null) return null;
  return repo.getAlbum(albumId);
});

final recentAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null) return [];
  return repo.getRecentAlbums(size: 24);
});

// ── All albums (paginated) ────────────────────────────────────────────────────

class AllAlbumsState {
  const AllAlbumsState({
    this.albums = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final List<Album> albums;
  final bool isLoading;
  final bool hasMore;
  final Object? error;

  AllAlbumsState copyWith({
    List<Album>? albums,
    bool? isLoading,
    bool? hasMore,
    Object? error,
  }) =>
      AllAlbumsState(
        albums: albums ?? this.albums,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

class AllAlbumsNotifier extends Notifier<AllAlbumsState> {
  static const _pageSize = 100;

  @override
  AllAlbumsState build() {
    _loadInitial();
    return const AllAlbumsState(isLoading: true);
  }

  Future<void> _loadInitial() async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      if (repo == null) {
        state = const AllAlbumsState();
        return;
      }
      final albums = await repo.getAllAlbums(size: _pageSize, offset: 0);
      state = AllAlbumsState(
        albums: albums,
        isLoading: false,
        hasMore: albums.length == _pageSize,
      );
    } catch (e) {
      state = AllAlbumsState(isLoading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final repo = ref.read(libraryRepositoryProvider);
      if (repo == null) return;
      final more = await repo.getAllAlbums(
          size: _pageSize, offset: state.albums.length);
      state = AllAlbumsState(
        albums: [...state.albums, ...more],
        isLoading: false,
        hasMore: more.length == _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }
}

final allAlbumsProvider =
    NotifierProvider<AllAlbumsNotifier, AllAlbumsState>(AllAlbumsNotifier.new);

// ── All songs (paginated) ─────────────────────────────────────────────────────

class AllSongsState {
  const AllSongsState({
    this.songs = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final List<Song> songs;
  final bool isLoading;
  final bool hasMore;
  final Object? error;

  AllSongsState copyWith({
    List<Song>? songs,
    bool? isLoading,
    bool? hasMore,
    Object? error,
  }) =>
      AllSongsState(
        songs: songs ?? this.songs,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        error: error,
      );
}

class AllSongsNotifier extends Notifier<AllSongsState> {
  static const _pageSize = 100;

  @override
  AllSongsState build() {
    _loadInitial();
    return const AllSongsState(isLoading: true);
  }

  Future<void> _loadInitial() async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      if (repo == null) {
        state = const AllSongsState();
        return;
      }
      final songs = await repo.getAllSongs(count: _pageSize, offset: 0);
      state = AllSongsState(
        songs: songs,
        isLoading: false,
        hasMore: songs.length == _pageSize,
      );
    } catch (e) {
      state = AllSongsState(isLoading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final repo = ref.read(libraryRepositoryProvider);
      if (repo == null) return;
      final more =
          await repo.getAllSongs(count: _pageSize, offset: state.songs.length);
      state = AllSongsState(
        songs: [...state.songs, ...more],
        isLoading: false,
        hasMore: more.length == _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }
}

final allSongsProvider =
    NotifierProvider<AllSongsNotifier, AllSongsState>(AllSongsNotifier.new);

// ── Playlists ─────────────────────────────────────────────────────────────────

final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null) return [];
  return repo.getPlaylists();
});

final playlistProvider =
    FutureProvider.family<Playlist?, String>((ref, playlistId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null) return null;
  return repo.getPlaylist(playlistId);
});

// ── Search ────────────────────────────────────────────────────────────────────

final searchResultsProvider =
    FutureProvider.family<SearchResults, String>((ref, query) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null || query.trim().isEmpty) return const SearchResults();
  return repo.searchAll(query.trim());
});
