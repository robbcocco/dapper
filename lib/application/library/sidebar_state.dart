import 'package:flutter_riverpod/legacy.dart';

enum SidebarSection {
  recentlyAdded,
  artists,
  albums,
  songs,
  genres,
  playlists,
  spotifyImport,
  lidarr,
  device,
  settings,
}

final selectedSectionProvider = StateProvider<SidebarSection>(
  (_) => SidebarSection.recentlyAdded,
);

// When a playlist is selected, its ID is stored here.
final selectedPlaylistIdProvider = StateProvider<String?>((_) => null);

// When an artist is selected, its ID is stored here.
final selectedArtistIdProvider = StateProvider<String?>((_) => null);

// When an album is selected (drill-down), its ID is stored here.
final selectedAlbumIdProvider = StateProvider<String?>((_) => null);

// When a genre is selected, its name is stored here so the page can
// drill into "albums by genre" for that genre.
final selectedGenreProvider = StateProvider<String?>((_) => null);

// Search query — when non-empty, main panel shows search results.
final searchQueryProvider = StateProvider<String>((_) => '');
