<script lang="ts">
  import LibraryEmpty from '../../widgets/library/LibraryEmpty.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { plural } from '../../widgets/library/actions';
  import { Resource } from '../../widgets/library/resource.svelte';
  import * as api from '../../lib/api';
  import type { Genre } from '../../lib/types';
  import { libraryNav } from '../../lib/stores/library-nav.svelte';
  import AlbumDetail from '../albums/AlbumDetail.svelte';
  import GenreAlbumsPanel from './GenreAlbumsPanel.svelte';

  /** genres_page.dart: genre list → albums in that genre → album detail. */
  const genres = new Resource<Genre[]>(() => api.genresList());
</script>

{#if libraryNav.albumId !== null}
  <AlbumDetail albumId={libraryNav.albumId} />
{:else if libraryNav.genre !== null}
  <GenreAlbumsPanel genre={libraryNav.genre} />
{:else if genres.value}
  {@const list = genres.value}
  {#if list.length === 0}
    <LibraryEmpty icon="category" title="No genres on this server." />
  {:else}
    <VirtualList count={list.length} rowHeight={48} paddingTop={8}>
      {#snippet row(i: number)}
        {@const g = list[i]!}
        <button type="button" class="genre" onclick={() => (libraryNav.genre = g.name)}>
          <span class="text">
            <span class="name">{g.name}</span>
            <span class="sub">{plural(g.albumCount, 'album')} · {plural(g.songCount, 'song')}</span>
          </span>
          <Icon name="chevron_right" size={16} />
        </button>
      {/snippet}
    </VirtualList>
  {/if}
{:else if genres.error}
  <ErrorRetry error={genres.error} onRetry={() => genres.retry()} />
{:else}
  <div class="center"><Spinner /></div>
{/if}

<style>
  .genre {
    display: flex;
    align-items: center;
    width: 100%;
    height: 48px;
    padding: 0 16px;
    border: none;
    background: none;
    font: inherit;
    text-align: left;
    color: var(--color-text-secondary);
  }
  .genre:hover {
    background: rgba(255, 255, 255, 0.04);
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .name {
    font-size: 13px;
    color: var(--color-text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sub {
    font-size: 11px;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
