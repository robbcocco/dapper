import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// In-memory overlay of the user's ratings. Songs/albums returned from the
/// server already carry a `userRating` field; this notifier exists so a
/// click on a rating star updates the UI immediately without re-fetching
/// the whole album. The map is keyed by song/album/artist id.
///
/// Optimistic: the new rating is applied locally first, then sent to the
/// server. On error we roll back and log.
class RatingsNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    // Reset whenever the active server changes — ratings are server-side
    // state that doesn't carry over.
    ref.watch(libraryRepositoryProvider);
    return const {};
  }

  int? operator [](String id) => state[id];

  Future<void> setRating(String id, int rating) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final previous = state[id];
    state = {...state, id: rating};
    try {
      await repo.setRating(id, rating);
    } catch (e) {
      dev.log('RatingsNotifier: setRating($id, $rating) failed — $e');
      // Roll back to whatever we had before (or remove the entry if there
      // was none).
      state = previous == null
          ? (Map.of(state)..remove(id))
          : {...state, id: previous};
      rethrow;
    }
  }
}

final ratingsProvider =
    NotifierProvider<RatingsNotifier, Map<String, int>>(RatingsNotifier.new);
