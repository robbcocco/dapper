import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class StarredNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(libraryRepositoryProvider); // reset when active server changes
    _load();
    return {};
  }

  Future<void> _load() async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    try {
      state = await repo.getStarredSongIds();
    } catch (e) {
      dev.log('StarredNotifier: failed to load starred songs — $e');
    }
  }

  Future<void> toggle(String songId) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final wasStarred = state.contains(songId);
    // Optimistic flip so the heart responds instantly instead of waiting a
    // network round-trip. Roll back if the server rejects it.
    state = wasStarred ? ({...state}..remove(songId)) : {...state, songId};
    try {
      if (wasStarred) {
        await repo.unstar(songId);
      } else {
        await repo.star(songId);
      }
    } catch (e) {
      state = wasStarred ? {...state, songId} : ({...state}..remove(songId));
      dev.log('StarredNotifier: toggle($songId) failed — $e');
    }
  }

  bool isStarred(String songId) => state.contains(songId);
}

final starredProvider =
    NotifierProvider<StarredNotifier, Set<String>>(StarredNotifier.new);
