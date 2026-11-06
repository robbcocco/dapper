<script lang="ts">
  import CoverArt from '../../widgets/CoverArt.svelte';
  import LibraryEmpty from '../../widgets/library/LibraryEmpty.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import SyncDot from '../../widgets/SyncDot.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { playArtist, transferLabel, transferArtist } from '../../widgets/library/actions';
  import { Resource } from '../../widgets/library/resource.svelte';
  import { libraryStatus } from '../../widgets/library/status.svelte';
  import * as api from '../../lib/api';
  import { showContextMenu } from '../../lib/menu';
  import type { Artist, LidarrArtist, LidarrInstancesState } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { libraryNav } from '../../lib/stores/library-nav.svelte';
  import AlbumDetail from '../albums/AlbumDetail.svelte';
  import ArtistDetailPanel from './ArtistDetailPanel.svelte';

  /** artists_page.dart: artist list (with device sync dots) beside the selected artist or album. */
  const artists = new Resource<Artist[]>(() => api.artistsList());

  // Lidarr cross-reference (lidarrClientProvider / lidarrArtistByMbidProvider).
  let lidarrRev = $state(0);
  const instances = new Resource<LidarrInstancesState>(() => api.lidarrInstances(), () => String(lidarrRev));
  const instance = $derived(
    instances.value?.selectedId != null
      ? (instances.value.instances.find((i) => i.id === instances.value?.selectedId) ?? null)
      : null,
  );
  const lidarrArtists = new Resource<LidarrArtist[]>(
    (key) => (key === '' ? Promise.resolve([]) : api.lidarrArtists().catch(() => [])),
    () => (instance ? `${instance.id}:${lidarrRev}` : ''),
  );
  const lidarrByMbid = $derived(new Map((lidarrArtists.value ?? []).map((a) => [a.mbid, a])));

  $effect(() => {
    const un = api.onLidarrChanged(() => lidarrRev++);
    return () => void un.then((f) => f());
  });

  $effect(() => libraryStatus.watchArtistSync());

  const selectedArtist = $derived(
    libraryNav.artistId !== null ? (artists.value?.find((a) => a.id === libraryNav.artistId) ?? null) : null,
  );

  function select(a: Artist): void {
    libraryNav.artistId = a.id;
    libraryNav.albumId = null;
  }

  async function artistMenu(e: MouseEvent, a: Artist): Promise<void> {
    e.preventDefault();
    const devs = devices.list;
    const result = await showContextMenu(
      [
        { id: 'play', label: 'Play All' },
        ...devs.map((d) => ({ id: `transfer:${d.path}`, label: transferLabel(devs, d, 'All') })),
      ],
      { x: e.clientX, y: e.clientY },
    );
    if (result === 'play') playArtist(a.id);
    else if (result?.startsWith('transfer:')) transferArtist(result.slice('transfer:'.length), a.id);
  }
</script>

{#if artists.value}
  {@const list = artists.value}
  <div class="page">
    <div class="list">
      {#if list.length === 0}
        <LibraryEmpty icon="person" title="No artists" />
      {:else}
        <VirtualList count={list.length} rowHeight={52} paddingTop={8}>
          {#snippet row(i: number)}
            {@const a = list[i]!}
            {@const sync = devices.selected ? libraryStatus.artistSync[a.id] : undefined}
            <button
              type="button"
              class="tile"
              class:selected={a.id === libraryNav.artistId}
              onclick={() => select(a)}
              oncontextmenu={(e) => void artistMenu(e, a)}
            >
              <CoverArt coverArtId={a.coverArtId} size={68} radius={17} display="34px" />
              <span class="name">{a.name}</span>
              {#if sync}<span class="dot"><SyncDot state={sync} size={6} /></span>{/if}
            </button>
          {/snippet}
        </VirtualList>
      {/if}
    </div>
    <div class="vline"></div>
    <div class="detail">
      {#if libraryNav.albumId !== null}
        <AlbumDetail albumId={libraryNav.albumId} />
      {:else if selectedArtist}
        {#key selectedArtist.id}
          <ArtistDetailPanel
            artist={selectedArtist}
            lidarrArtist={selectedArtist.musicBrainzId ? (lidarrByMbid.get(selectedArtist.musicBrainzId) ?? null) : null}
            lidarrInstance={instance}
            onLidarrChanged={() => lidarrRev++}
          />
        {/key}
      {:else}
        <div class="center empty">Select an artist</div>
      {/if}
    </div>
  </div>
{:else if artists.error}
  <ErrorRetry error={artists.error} onRetry={() => artists.retry()} />
{:else}
  <div class="center"><Spinner /></div>
{/if}

<style>
  .page {
    height: 100%;
    display: flex;
  }
  .list {
    width: var(--artist-tree-width);
    flex: none;
  }
  .vline {
    width: 1px;
    flex: none;
    background: var(--color-glass-border);
  }
  .detail {
    flex: 1;
    min-width: 0;
  }
  .tile {
    display: flex;
    align-items: center;
    gap: 10px;
    width: calc(100% - 12px);
    height: 48px;
    margin: 2px 6px;
    padding: 0 10px;
    border: none;
    border-radius: 8px;
    background: none;
    font: inherit;
    text-align: left;
    color: var(--color-text-secondary);
  }
  .tile.selected {
    background: var(--color-selection-background);
    color: var(--color-text-primary);
    font-weight: 500;
  }
  .name {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .dot {
    display: flex;
    margin: 0 4px;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .empty {
    font-size: 14px;
    color: var(--color-text-secondary);
  }
</style>
