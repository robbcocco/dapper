<script lang="ts">
  import CoverArt from '../../widgets/CoverArt.svelte';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import SongRow from '../../widgets/library/SongRow.svelte';
  import { fetchAlbum, playArtist, playSongs, transferAlbum, transferLabel } from '../../widgets/library/actions';
  import { Resource } from '../../widgets/library/resource.svelte';
  import * as api from '../../lib/api';
  import { showContextMenu } from '../../lib/menu';
  import type { Album, Artist, SearchResults, Song } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { goToAlbum, goToArtist } from '../../lib/stores/library-nav.svelte';
  import { search } from '../../lib/stores/search.svelte';

  /** search_page.dart: shown instead of the section page while the sidebar query is non-empty. */
  const results = new Resource<SearchResults>((q) => api.search(q), () => search.query);

  type Row =
    | { kind: 'header'; label: string }
    | { kind: 'artist'; artist: Artist }
    | { kind: 'album'; album: Album }
    | { kind: 'song'; song: Song; index: number };

  const rows = $derived.by((): Row[] => {
    const r = results.value;
    if (!r) return [];
    const out: Row[] = [];
    if (r.artists.length > 0) {
      out.push({ kind: 'header', label: 'ARTISTS' });
      for (const artist of r.artists) out.push({ kind: 'artist', artist });
    }
    if (r.albums.length > 0) {
      out.push({ kind: 'header', label: 'ALBUMS' });
      for (const album of r.albums) out.push({ kind: 'album', album });
    }
    if (r.songs.length > 0) {
      out.push({ kind: 'header', label: 'SONGS' });
      r.songs.forEach((song, index) => out.push({ kind: 'song', song, index }));
    }
    return out;
  });

  async function artistMenu(e: MouseEvent, artist: Artist): Promise<void> {
    e.preventDefault();
    const result = await showContextMenu(
      [
        { id: 'go', label: 'Go to Artist' },
        { id: 'play', label: 'Play All' },
      ],
      { x: e.clientX, y: e.clientY },
    );
    if (result === 'go') goToArtist(artist.id);
    else if (result === 'play') playArtist(artist.id);
  }

  async function albumMenu(e: MouseEvent, album: Album): Promise<void> {
    e.preventDefault();
    const devs = devices.list;
    const result = await showContextMenu(
      [
        { id: 'open', label: 'Open Album' },
        { id: 'play', label: 'Play Album' },
        ...devs.map((d) => ({ id: `transfer:${d.path}`, label: transferLabel(devs, d, 'Album') })),
      ],
      { x: e.clientX, y: e.clientY },
    );
    if (result === null) return;
    if (result === 'open') goToAlbum(album.id);
    else if (result === 'play') {
      const full = await fetchAlbum(album.id);
      if (full && full.songs.length > 0) playSongs(full.songs, 0);
    } else if (result.startsWith('transfer:')) transferAlbum(result.slice('transfer:'.length), album.id);
  }
</script>

{#if results.value}
  {@const r = results.value}
  {#if rows.length === 0}
    <EmptyState icon="search" title={`No results for "${search.query}"`} />
  {:else}
    <VirtualList count={rows.length} rowHeight={48} paddingTop={16}>
      {#snippet row(i: number)}
        {@const it = rows[i]!}
        {#if it.kind === 'header'}
          <div class="section">{it.label}</div>
        {:else if it.kind === 'artist'}
          <button type="button" class="item" onclick={() => goToArtist(it.artist.id)} oncontextmenu={(e) => void artistMenu(e, it.artist)}>
            <Icon name="person" size={16} />
            <span class="text"><span class="name">{it.artist.name}</span></span>
            <span class="aside">{it.artist.albumCount} albums</span>
          </button>
        {:else if it.kind === 'album'}
          <button type="button" class="item" onclick={() => goToAlbum(it.album.id)} oncontextmenu={(e) => void albumMenu(e, it.album)}>
            <CoverArt coverArtId={it.album.coverArtId} size={72} radius={3} display="36px" />
            <span class="text">
              <span class="name">{it.album.name}</span>
              {#if it.album.artist}<span class="sub">{it.album.artist}</span>{/if}
            </span>
            {#if it.album.year != null}<span class="aside">{it.album.year}</span>{/if}
          </button>
        {:else}
          <SongRow song={it.song} index={it.index} showArtist onTap={() => playSongs(r.songs, it.index)} />
        {/if}
      {/snippet}
    </VirtualList>
  {/if}
{:else if results.error}
  <ErrorRetry error={results.error} onRetry={() => results.retry()} />
{:else}
  <div class="center"><Spinner /></div>
{/if}

<style>
  .section {
    height: 100%;
    display: flex;
    align-items: flex-end;
    padding: 0 24px 6px;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.8px;
    color: var(--color-text-secondary);
  }
  .item {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    height: 48px;
    padding: 0 24px;
    border: none;
    border-bottom: 1px solid #2a2a2a;
    background: none;
    font: inherit;
    text-align: left;
    color: var(--color-text-secondary);
  }
  .item:hover {
    background: rgba(255, 255, 255, 0.03);
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .name,
  .sub {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .name {
    font-size: 13px;
    color: var(--color-text-primary);
  }
  .sub,
  .aside {
    font-size: 11px;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
