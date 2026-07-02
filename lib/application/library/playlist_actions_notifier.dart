import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'library_notifier.dart';

class PlaylistActionsNotifier extends Notifier<void> {
  @override
  void build() {}

  // Runs [body] and, on failure, surfaces [failMessage] to the user via
  // actionErrorProvider instead of leaving an unhandled async exception —
  // these methods are called `unawaited` from the UI. Returns true on success.
  Future<bool> _guard(String failMessage, Future<void> Function() body) async {
    try {
      await body();
      return true;
    } catch (e) {
      dev.log('PlaylistActionsNotifier: $failMessage — $e');
      ref.read(actionErrorProvider.notifier).state = failMessage;
      return false;
    }
  }

  Future<bool> createPlaylist(String name,
      {List<String> songIds = const []}) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return false;
    return _guard('Could not create playlist', () async {
      await repo.createPlaylist(name, songIds: songIds);
      ref.invalidate(playlistsProvider);
    });
  }

  Future<bool> rename(String playlistId, String newName) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return false;
    return _guard('Could not rename playlist', () async {
      await repo.updatePlaylist(playlistId, name: newName);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(playlistId));
    });
  }

  Future<bool> addSongs(String playlistId, List<String> songIds) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return false;
    return _guard('Could not add songs to playlist', () async {
      await repo.updatePlaylist(playlistId, songIdsToAdd: songIds);
      ref.invalidate(playlistProvider(playlistId));
      ref.invalidate(playlistsProvider);
    });
  }

  Future<bool> removeSong(String playlistId, int songIndex) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return false;
    return _guard('Could not remove song from playlist', () async {
      await repo.updatePlaylist(playlistId, songIndexesToRemove: [songIndex]);
      ref.invalidate(playlistProvider(playlistId));
      ref.invalidate(playlistsProvider);
    });
  }

  Future<bool> delete(String playlistId) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return false;
    return _guard('Could not delete playlist', () async {
      await repo.deletePlaylist(playlistId);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistProvider(playlistId));
    });
  }
}

final playlistActionsProvider =
    NotifierProvider<PlaylistActionsNotifier, void>(PlaylistActionsNotifier.new);
