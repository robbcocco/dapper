import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'library_notifier.dart';

class PlaylistActionsNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> createPlaylist(String name,
      {List<String> songIds = const []}) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    await repo.createPlaylist(name, songIds: songIds);
    ref.invalidate(playlistsProvider);
  }

  Future<void> rename(String playlistId, String newName) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    await repo.updatePlaylist(playlistId, name: newName);
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistProvider(playlistId));
  }

  Future<void> addSongs(String playlistId, List<String> songIds) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    await repo.updatePlaylist(playlistId, songIdsToAdd: songIds);
    ref.invalidate(playlistProvider(playlistId));
    ref.invalidate(playlistsProvider);
  }

  Future<void> removeSong(String playlistId, int songIndex) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    await repo.updatePlaylist(playlistId, songIndexesToRemove: [songIndex]);
    ref.invalidate(playlistProvider(playlistId));
  }

  Future<void> delete(String playlistId) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    await repo.deletePlaylist(playlistId);
    ref.invalidate(playlistsProvider);
  }
}

final playlistActionsProvider =
    NotifierProvider<PlaylistActionsNotifier, void>(PlaylistActionsNotifier.new);
