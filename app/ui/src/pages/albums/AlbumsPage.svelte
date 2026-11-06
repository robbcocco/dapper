<script lang="ts">
  import { untrack } from 'svelte';
  import LibraryEmpty from '../../widgets/library/LibraryEmpty.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Select from '../../widgets/Select.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import AlbumGrid from '../../widgets/library/AlbumGrid.svelte';
  import { Windowed } from '../../widgets/library/windowed.svelte';
  import { libraryStatus } from '../../widgets/library/status.svelte';
  import * as api from '../../lib/api';
  import type { Album, AlbumSort } from '../../lib/types';
  import { libraryNav } from '../../lib/stores/library-nav.svelte';
  import { session } from '../../lib/stores/session.svelte';
  import AlbumDetail from './AlbumDetail.svelte';
  import ArtistAlbumsView from './ArtistAlbumsView.svelte';

  /** AlbumsPage(mode: all): album detail > artist drill-down > lazily loaded grid of every album. */
  const sorts: { value: AlbumSort; label: string }[] = [
    { value: 'name', label: 'Name' },
    { value: 'artist', label: 'Artist' },
    { value: 'year', label: 'Year' },
    { value: 'recent', label: 'Recently Added' },
  ];
  let sort = $state<AlbumSort>('name');

  const list = $derived.by(() => {
    const s = sort;
    return new Windowed<Album>((offset, limit) => api.albumsWindow(offset, limit, s));
  });

  // New list (sort change) or server switch → start over.
  $effect(() => {
    void session.serverId;
    const l = list;
    untrack(() => void l.reset());
  });

  // library-changed → refetch loaded windows in place.
  let seenRev = libraryStatus.libraryRev;
  $effect(() => {
    const rev = libraryStatus.libraryRev;
    if (rev === seenRev) return;
    seenRev = rev;
    untrack(() => void list.refresh());
  });
</script>

{#if libraryNav.albumId !== null}
  <AlbumDetail albumId={libraryNav.albumId} />
{:else if libraryNav.artistId !== null}
  <ArtistAlbumsView artistId={libraryNav.artistId} />
{:else if list.total !== null}
  {#if list.total === 0}
    <LibraryEmpty icon="album" title="No albums" message="Your library has no albums yet." />
  {:else}
    <AlbumGrid count={list.total} get={(i) => list.get(i)} onRangeChange={(s, e) => void list.ensure(s, e)}>
      {#snippet header()}
        <div class="head">
          <span class="count">{list.total} albums</span>
          <div class="sort"><Select value={sort} options={sorts} onchange={(v) => (sort = v)} /></div>
        </div>
      {/snippet}
    </AlbumGrid>
  {/if}
{:else if list.error}
  <ErrorRetry error={list.error} onRetry={() => list.reset()} />
{:else}
  <div class="center"><Spinner /></div>
{/if}

<style>
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 24px 16px;
  }
  .count {
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .sort {
    width: 160px;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
