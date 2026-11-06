import { selectedSection, SidebarSection } from './navigation.svelte';

export type LidarrLibraryFilter = 'all' | 'monitored' | 'unmonitored' | 'missing';

/**
 * Lidarr page state (lib/application/lidarr/lidarr_notifier.dart):
 * selectedLidarrMbidProvider, lidarrLibraryFilterProvider, selectedCustomFilterIdProvider.
 */
export const lidarrNav = $state<{
  selectedMbid: string | null;
  libraryFilter: LidarrLibraryFilter;
  customFilterId: number | null;
}>({
  selectedMbid: null,
  libraryFilter: 'all',
  customFilterId: null,
});

/** Jumps into the Lidarr section with this artist (by MusicBrainz id) pre-selected. */
export function openLidarrArtist(mbid: string): void {
  lidarrNav.selectedMbid = mbid;
  selectedSection.value = SidebarSection.lidarr;
}
