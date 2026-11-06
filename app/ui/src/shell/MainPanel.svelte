<script lang="ts">
  import type { Component } from 'svelte';
  import { selectedSection, type SidebarSection } from '../lib/stores/navigation.svelte';
  import RecentlyAddedPage from '../pages/recentlyAdded/RecentlyAddedPage.svelte';
  import ArtistsPage from '../pages/artists/ArtistsPage.svelte';
  import AlbumsPage from '../pages/albums/AlbumsPage.svelte';
  import SongsPage from '../pages/songs/SongsPage.svelte';
  import GenresPage from '../pages/genres/GenresPage.svelte';
  import PlaylistsPage from '../pages/playlists/PlaylistsPage.svelte';
  import SpotifyImportPage from '../pages/spotifyImport/SpotifyImportPage.svelte';
  import LidarrPage from '../pages/lidarr/LidarrPage.svelte';
  import DevicePage from '../pages/device/DevicePage.svelte';
  import SettingsPage from '../pages/settings/SettingsPage.svelte';
  import SearchPage from '../pages/search/SearchPage.svelte';
  import { search } from '../lib/stores/search.svelte';

  const pages: Record<SidebarSection, Component> = {
    recentlyAdded: RecentlyAddedPage,
    artists: ArtistsPage,
    albums: AlbumsPage,
    songs: SongsPage,
    genres: GenresPage,
    playlists: PlaylistsPage,
    spotifyImport: SpotifyImportPage,
    lidarr: LidarrPage,
    device: DevicePage,
    settings: SettingsPage,
  };

  const Page = $derived(pages[selectedSection.value]);
</script>

<!-- A non-empty sidebar query overrides the section (app_shell.dart _MainPanel). -->
{#if search.query !== ''}
  <SearchPage />
{:else}
  <Page />
{/if}
