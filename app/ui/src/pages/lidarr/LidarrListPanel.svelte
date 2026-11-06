<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrArtist, LidarrCustomFilter, LidarrInstance } from '../../lib/types';
  import { lidarrNav, type LidarrLibraryFilter } from '../../lib/stores/lidarr-nav.svelte';
  import { toast } from '../../lib/stores/toast.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { errorOf } from '../settings/connection';
  import LidarrError from './LidarrError.svelte';
  import LidarrImage from './LidarrImage.svelte';
  import { filterArtists, isInLidarr } from './lidarr-filters';
  import type { ArtistsState } from './LidarrPage.svelte';

  let {
    artists,
    customFilters,
    instance,
    onretry,
    onadded,
  }: {
    artists: ArtistsState;
    customFilters: LidarrCustomFilter[];
    instance: LidarrInstance | null;
    onretry: () => void;
    onadded: () => void;
  } = $props();

  const FILTERS: { value: LidarrLibraryFilter; label: string }[] = [
    { value: 'all', label: 'All' },
    { value: 'monitored', label: 'Monitored' },
    { value: 'unmonitored', label: 'Unmonitored' },
    { value: 'missing', label: 'Missing' },
  ];

  let query = $state('');
  let results = $state<LidarrArtist[] | null>(null);
  let searching = $state(false);
  let addingMbid = $state<string | null>(null);
  let debounce: ReturnType<typeof setTimeout> | undefined;

  const isQuerying = $derived(query.trim() !== '');
  const all = $derived(artists.value ?? []);
  const byMbid = $derived(new Set(all.filter((a) => a.mbid !== '').map((a) => a.mbid)));
  const filtered = $derived(filterArtists(all, lidarrNav.libraryFilter, lidarrNav.customFilterId, customFilters));
  const isFiltered = $derived(lidarrNav.customFilterId !== null || lidarrNav.libraryFilter !== 'all');

  $effect(() => () => clearTimeout(debounce));

  function onQueryInput(e: Event): void {
    clearTimeout(debounce);
    const q = (e.currentTarget as HTMLInputElement).value.trim();
    if (q === '') {
      results = null;
      searching = false;
      return;
    }
    searching = true;
    debounce = setTimeout(() => void lookup(q), 400);
  }

  async function lookup(q: string): Promise<void> {
    try {
      const found = await api.lidarrArtistLookup(q);
      if (query.trim() !== q) return;
      results = found;
    } catch {
      // Lookup failures show the empty "No results" state, as in Flutter.
    }
    if (query.trim() === q) searching = false;
  }

  function clearQuery(): void {
    clearTimeout(debounce);
    query = '';
    results = null;
    searching = false;
  }

  async function add(a: LidarrArtist): Promise<void> {
    const path = instance?.defaultRootFolderPath;
    const profile = instance?.defaultQualityProfileId;
    if (instance?.defaultRootFolderId === undefined || path === undefined || profile === undefined) {
      toast('Set a root folder and quality profile in Settings → Lidarr first.');
      return;
    }
    addingMbid = a.mbid;
    try {
      await api.lidarrAddArtist(a, path, profile);
      onadded();
      clearQuery();
    } catch (e) {
      toast(`Failed to add: ${errorOf(e).message}`, { kind: 'error' });
    } finally {
      addingMbid = null;
    }
  }

  function selectBuiltIn(f: LidarrLibraryFilter): void {
    lidarrNav.customFilterId = null;
    lidarrNav.libraryFilter = f;
  }
</script>

<div class="panel">
  <div class="search">
    <TextField search bind:value={query} placeholder="Search Lidarr…" oninput={onQueryInput} onclear={clearQuery} />
  </div>

  {#if !isQuerying}
    <div class="filters">
      {#each FILTERS as f (f.value)}
        <button
          type="button"
          class="chip"
          class:sel={lidarrNav.customFilterId === null && lidarrNav.libraryFilter === f.value}
          onclick={() => selectBuiltIn(f.value)}>{f.label}</button
        >
      {/each}
      {#each customFilters as cf (cf.id)}
        <button
          type="button"
          class="chip"
          class:sel={lidarrNav.customFilterId === cf.id}
          onclick={() => (lidarrNav.customFilterId = cf.id)}>{cf.label}</button
        >
      {/each}
    </div>
  {/if}

  <div class="list">
    {#if isQuerying}
      {#if searching && results === null}
        <div class="center"><Spinner size={20} stroke={1.5} /></div>
      {:else if !results || results.length === 0}
        <div class="center msg">No results</div>
      {:else}
        {@const list = results}
        <VirtualList count={list.length} rowHeight={44} paddingTop={4}>
          {#snippet row(i)}
            {@const a = list[i]!}
            <div class="result">
              <LidarrImage url={a.posterUrl} size={32} radius={16} icon="person" iconSize={18} />
              <span class="rname" title={a.name}>{a.name}</span>
              {#if isInLidarr(a) || byMbid.has(a.mbid)}
                <Icon name="check_circle" size={16} color="#4caf50" />
              {:else if addingMbid === a.mbid}
                <Spinner size={16} stroke={1.5} />
              {:else}
                <button type="button" class="add" onclick={() => void add(a)}>Add</button>
              {/if}
            </div>
          {/snippet}
        </VirtualList>
      {/if}
    {:else if artists.loading && artists.value === null}
      <div class="center"><Spinner size={20} stroke={1.5} /></div>
    {:else if artists.error !== null && artists.value === null}
      <LidarrError message="Could not reach Lidarr. Check the instance is running and reachable." {onretry} />
    {:else if filtered.length === 0}
      <div class="center msg">
        {isFiltered ? 'No artists match this filter.' : 'No artists in Lidarr yet.\nSearch above to add one.'}
      </div>
    {:else}
      {@const list = filtered}
      <VirtualList count={list.length} rowHeight={52} paddingTop={4}>
        {#snippet row(i)}
          {@const a = list[i]!}
          {@const selected = a.mbid === lidarrNav.selectedMbid}
          <button type="button" class="artist" class:selected onclick={() => (lidarrNav.selectedMbid = a.mbid)}>
            <LidarrImage url={a.posterUrl} size={34} radius={17} icon="person" iconSize={18} />
            <span class="aname">{a.name}</span>
          </button>
        {/snippet}
      </VirtualList>
    {/if}
  </div>
</div>

<style>
  .panel {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .search {
    padding: 6px 10px 4px;
  }
  .filters {
    flex: none;
    display: flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 9px;
    overflow-x: auto;
    overflow-y: hidden;
    border-bottom: 1px solid var(--color-glass-border);
    scrollbar-width: none;
  }
  .filters::-webkit-scrollbar {
    display: none;
  }
  .chip {
    flex: none;
    height: 18px;
    padding: 0 8px;
    border: none;
    border-radius: 10px;
    background: transparent;
    color: var(--color-text-secondary);
    font: inherit;
    font-size: 11px;
    white-space: nowrap;
  }
  .chip:hover {
    color: var(--color-text-primary);
  }
  .chip.sel {
    background: rgba(10, 132, 255, 0.18);
    color: var(--color-accent);
    font-weight: 600;
  }
  .list {
    flex: 1;
    min-height: 0;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
    padding: 16px;
  }
  .msg {
    font-size: 12px;
    color: var(--color-text-secondary);
    text-align: center;
    white-space: pre-line;
  }
  .result {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 10px;
  }
  .rname {
    flex: 1;
    min-width: 0;
    font-size: 12px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .add {
    padding: 4px 8px;
    border: none;
    border-radius: 6px;
    background: transparent;
    color: var(--color-accent);
    font: inherit;
    font-size: 11px;
  }
  .add:hover {
    background: rgba(255, 255, 255, 0.06);
  }
  .artist {
    width: calc(100% - 12px);
    height: 48px;
    margin: 2px 6px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 10px;
    border: none;
    border-radius: 8px;
    background: transparent;
    font: inherit;
    text-align: start;
    color: var(--color-text-secondary);
  }
  .artist:hover {
    background: rgba(255, 255, 255, 0.04);
  }
  .artist.selected {
    background: var(--color-selection-background);
    color: var(--color-text-primary);
    font-weight: 500;
  }
  .aname {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
