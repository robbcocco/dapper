import { selectedSection, SidebarSection } from './navigation.svelte';
import { search } from './search.svelte';

/**
 * Library drill-down state (lib/application/library/sidebar_state.dart):
 * selectedArtistIdProvider, selectedAlbumIdProvider, selectedGenreProvider.
 * Album detail renders inside whichever section is active (albums, artists, genres).
 */
export const libraryNav = $state<{ artistId: string | null; albumId: string | null; genre: string | null }>({
  artistId: null,
  albumId: null,
  genre: null,
});

export function openAlbum(albumId: string): void {
  libraryNav.albumId = albumId;
}

export function closeAlbum(): void {
  libraryNav.albumId = null;
}

/** Jumps to the artist detail in the Artists section, clearing any search. */
export function goToArtist(artistId: string): void {
  libraryNav.albumId = null;
  libraryNav.artistId = artistId;
  selectedSection.value = SidebarSection.artists;
  search.query = '';
}

/** Opens an album in the Albums section, clearing any search. */
export function goToAlbum(albumId: string): void {
  libraryNav.albumId = albumId;
  selectedSection.value = SidebarSection.albums;
  search.query = '';
}

/** Sidebar "Albums" tile: land on the full grid, not a stale drill-down. */
export function resetAlbumsNav(): void {
  libraryNav.artistId = null;
  libraryNav.albumId = null;
}

/** Sidebar "Genres" tile: land on the genre list. */
export function resetGenresNav(): void {
  libraryNav.albumId = null;
  libraryNav.genre = null;
}
