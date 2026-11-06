<script lang="ts">
  import { playlists } from '../../lib/stores/playlists.svelte';
  import { selectionNav } from '../../lib/stores/selection-nav.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import PlaylistList from './PlaylistList.svelte';
  import PlaylistDetail from './PlaylistDetail.svelte';
</script>

<section class="page">
  {#if selectionNav.selectedPlaylistId !== null}
    {#key selectionNav.selectedPlaylistId}
      <PlaylistDetail playlistId={selectionNav.selectedPlaylistId} />
    {/key}
  {:else if playlists.items !== null}
    <PlaylistList items={playlists.items} />
  {:else if playlists.error !== null && !playlists.loading}
    <ErrorRetry error={playlists.error} onRetry={() => playlists.load()} />
  {:else}
    <div class="center"><Spinner size={28} /></div>
  {/if}
</section>

<style>
  .page {
    height: 100%;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
