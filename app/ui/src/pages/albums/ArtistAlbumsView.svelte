<script lang="ts">
  import Button from '../../widgets/Button.svelte';
  import CoverArt from '../../widgets/CoverArt.svelte';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import AlbumGrid from '../../widgets/library/AlbumGrid.svelte';
  import { playArtist, plural, transferArtist } from '../../widgets/library/actions';
  import { pickDevicePath } from '../../widgets/library/dialogs';
  import { Resource } from '../../widgets/library/resource.svelte';
  import * as api from '../../lib/api';
  import type { Album, Artist } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { libraryNav } from '../../lib/stores/library-nav.svelte';

  /** albums_page.dart `_ArtistAlbumsView`: the Albums section drilled into one artist. */
  let { artistId }: { artistId: string } = $props();

  const artists = new Resource<Artist[]>(() => api.artistsList());
  const albums = new Resource<Album[]>((id) => api.artistAlbums(id), () => artistId);
  const artist = $derived(artists.value?.find((a) => a.id === artistId) ?? null);

  async function transferAll(): Promise<void> {
    const path = await pickDevicePath(devices.list);
    if (path !== null) transferArtist(path, artistId);
  }
</script>

<div class="view">
  <header class="head">
    <IconButton icon="chevron_left" size={16} label="All Albums" onclick={() => (libraryNav.artistId = null)} />
    {#if artist}
      <CoverArt coverArtId={artist.coverArtId} size={300} radius={40} display="80px" />
      <div class="meta">
        <h1>{artist.name}</h1>
        <div class="sub">{plural(artist.albumCount, 'album')}</div>
        <div class="actions">
          <Button icon="play" small onclick={() => playArtist(artist.id)}>Play All</Button>
          {#if devices.list.length > 0}
            <Button variant="primary" icon="download" small onclick={() => void transferAll()}>Transfer All</Button>
          {/if}
        </div>
      </div>
    {/if}
  </header>
  <div class="body">
    {#if albums.value}
      {#if albums.value.length === 0}
        <EmptyState title="No albums" />
      {:else}
        <AlbumGrid albums={albums.value} />
      {/if}
    {:else if albums.error}
      <ErrorRetry error={albums.error} onRetry={() => albums.retry()} />
    {:else}
      <div class="center"><Spinner /></div>
    {/if}
  </div>
</div>

<style>
  .view {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 16px 24px 16px 12px;
    border-bottom: 1px solid var(--color-divider);
  }
  .meta {
    min-width: 0;
    margin-left: 8px;
  }
  h1 {
    margin: 0;
    font-size: 20px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sub {
    margin-top: 2px;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .actions {
    display: flex;
    gap: 8px;
    margin-top: 10px;
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
