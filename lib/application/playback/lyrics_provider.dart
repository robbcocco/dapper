import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/lyrics.dart';
import '../providers/providers.dart';

/// Family-keyed lyrics fetcher. Riverpod's cache means revisiting the same
/// song's lyrics modal doesn't refetch — useful since lyrics never change
/// for a given track. Cache is implicitly cleared when the server changes,
/// because libraryRepositoryProvider rebuilds with the new credentials.
final lyricsProvider =
    FutureProvider.family<Lyrics?, String>((ref, songId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  if (repo == null) return null;
  return repo.getLyrics(songId);
});
