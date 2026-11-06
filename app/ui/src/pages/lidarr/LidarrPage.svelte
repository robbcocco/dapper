<script lang="ts" module>
  import type { LidarrArtist } from '../../lib/types';

  /** lidarrArtistsProvider as AsyncValue: a refresh keeps the previous value. */
  export interface ArtistsState {
    value: LidarrArtist[] | null;
    loading: boolean;
    error: string | null;
  }
</script>

<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrCustomFilter, LidarrInstancesState } from '../../lib/types';
  import { lidarrNav } from '../../lib/stores/lidarr-nav.svelte';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import { errorOf } from '../settings/connection';
  import LidarrArtistDetail from './LidarrArtistDetail.svelte';
  import LidarrListPanel from './LidarrListPanel.svelte';

  let instances = $state<LidarrInstancesState | null>(null);
  let artists = $state<ArtistsState>({ value: null, loading: true, error: null });
  let customFilters = $state<LidarrCustomFilter[]>([]);
  /** Drops responses from a superseded instance. */
  let generation = 0;

  const instance = $derived(instances?.instances.find((i) => i.id === instances?.selectedId) ?? null);
  const connected = $derived(instances !== null && instances.selectedId !== null);
  const selected = $derived(
    lidarrNav.selectedMbid === null ? null : (artists.value?.find((a) => a.mbid === lidarrNav.selectedMbid) ?? null),
  );

  async function loadArtists(gen: number): Promise<void> {
    artists = { ...artists, loading: true, error: null };
    try {
      const list = await api.lidarrArtists();
      if (gen === generation) artists = { value: list, loading: false, error: null };
    } catch (e) {
      if (gen === generation) artists = { ...artists, loading: false, error: errorOf(e).message };
    }
  }

  async function loadFilters(gen: number): Promise<void> {
    try {
      const list = await api.lidarrCustomFilters();
      if (gen === generation) customFilters = list;
    } catch {
      // Custom filters are optional chips; the built-in ones still work.
      if (gen === generation) customFilters = [];
    }
  }

  async function load(): Promise<void> {
    const gen = ++generation;
    let next: LidarrInstancesState;
    try {
      next = await api.lidarrInstances();
    } catch (e) {
      if (gen !== generation) return;
      instances = { instances: [], selectedId: null };
      artists = { value: null, loading: false, error: errorOf(e).message };
      return;
    }
    const changed = next.selectedId !== instances?.selectedId;
    instances = next;
    if (next.selectedId === null) {
      artists = { value: null, loading: false, error: null };
      customFilters = [];
      return;
    }
    if (changed) artists = { value: null, loading: true, error: null };
    void loadArtists(gen);
    void loadFilters(gen);
  }

  $effect(() => {
    void load();
    const un = api.onLidarrChanged(() => void load());
    return () => void un.then((f) => f());
  });
</script>

{#if instances === null}
  <div class="center"><Spinner /></div>
{:else if !connected}
  <EmptyState icon="cloud_off" title="Lidarr not configured" message="Add a Lidarr instance in Settings." />
{:else}
  <div class="page">
    <div class="list">
      <LidarrListPanel
        {artists}
        {customFilters}
        {instance}
        onretry={() => void loadArtists(generation)}
        onadded={() => void loadArtists(generation)}
      />
    </div>
    <div class="detail">
      {#if selected}
        {#key selected.mbid}
          <LidarrArtistDetail artist={selected} />
        {/key}
      {:else}
        <div class="center msg">Select an artist</div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .page {
    height: 100%;
    display: flex;
  }
  .list {
    width: var(--artist-tree-width);
    flex: none;
    border-right: 1px solid var(--color-glass-border);
  }
  .detail {
    flex: 1;
    min-width: 0;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .msg {
    font-size: 14px;
    color: var(--color-text-secondary);
  }
</style>
