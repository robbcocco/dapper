import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class StarredNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
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
    if (state.contains(songId)) {
      await repo.unstar(songId);
      state = {...state}..remove(songId);
    } else {
      await repo.star(songId);
      state = {...state, songId};
    }
  }

  bool isStarred(String songId) => state.contains(songId);
}

final starredProvider =
    NotifierProvider<StarredNotifier, Set<String>>(StarredNotifier.new);
