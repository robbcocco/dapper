import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SidebarSection {
  recentlyAdded,
  artists,
  albums,
  songs,
  playlists,
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

// Search query — when non-empty, main panel shows search results.
final searchQueryProvider = StateProvider<String>((_) => '');
