<script lang="ts">
  import LibraryEmpty from '../../widgets/library/LibraryEmpty.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import AlbumGrid from '../../widgets/library/AlbumGrid.svelte';
  import { Resource } from '../../widgets/library/resource.svelte';
  import * as api from '../../lib/api';
  import type { Album } from '../../lib/types';
  import { libraryNav } from '../../lib/stores/library-nav.svelte';
  import AlbumDetail from '../albums/AlbumDetail.svelte';

  /** AlbumsPage(mode: recent): the 24 newest albums (recentAlbumsProvider). */
  const recent = new Resource<Album[]>(() => api.albumsRecent(24));
</script>

{#if libraryNav.albumId !== null}
  <AlbumDetail albumId={libraryNav.albumId} />
{:else if recent.value}
  {#if recent.value.length === 0}
    <LibraryEmpty icon="album" title="No albums" message="Recently added albums will appear here." />
  {:else}
    <AlbumGrid albums={recent.value} />
  {/if}
{:else if recent.error}
  <ErrorRetry error={recent.error} onRetry={() => recent.retry()} />
{:else}
  <div class="center"><Spinner /></div>
{/if}

<style>
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
