/** Mirrors `SidebarSection` in lib/application/library/sidebar_state.dart. */
export const SidebarSection = {
  recentlyAdded: 'recentlyAdded',
  artists: 'artists',
  albums: 'albums',
  songs: 'songs',
  genres: 'genres',
  playlists: 'playlists',
  spotifyImport: 'spotifyImport',
  lidarr: 'lidarr',
  device: 'device',
  settings: 'settings',
} as const;
export type SidebarSection = (typeof SidebarSection)[keyof typeof SidebarSection];

/** `selectedSection.value` drives MainPanel (no router, like the Flutter app). */
export const selectedSection = $state<{ value: SidebarSection }>({ value: SidebarSection.recentlyAdded });
