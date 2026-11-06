<script lang="ts">
  import EmptyState from '../../widgets/EmptyState.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import AlbumGrid from '../../widgets/library/AlbumGrid.svelte';
  import { Resource } from '../../widgets/library/resource.svelte';
  import * as api from '../../lib/api';
  import type { Album } from '../../lib/types';
  import { libraryNav } from '../../lib/stores/library-nav.svelte';

  /** genres_page.dart `_GenreAlbumsPanel`. */
  let { genre }: { genre: string } = $props();

  const albums = new Resource<Album[]>((g) => api.genreAlbums(g), () => genre);
</script>

<div class="panel">
  <header class="head">
    <IconButton icon="chevron_left" size={16} label="All Genres" onclick={() => (libraryNav.genre = null)} />
    <h1>{genre}</h1>
  </header>
  <div class="body">
    {#if albums.value}
      {#if albums.value.length === 0}
        <EmptyState title={`No albums in "${genre}"`} />
      {:else}
        <AlbumGrid albums={albums.value} plain />
      {/if}
    {:else if albums.error}
      <ErrorRetry error={albums.error} onRetry={() => albums.retry()} />
    {:else}
      <div class="center"><Spinner /></div>
    {/if}
  </div>
</div>

<style>
  .panel {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 16px 24px 16px 12px;
    border-bottom: 1px solid var(--color-divider);
  }
  h1 {
    margin: 0;
    font-size: 20px;
    font-weight: 700;
  }
  .body {
    flex: 1;
    min-height: 0;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
