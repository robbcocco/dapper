<script lang="ts">
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import * as api from '../../lib/api';
  import { toAppError } from '../../lib/ipc';
  import type { Artist, LidarrArtist, LidarrInstance } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';

  /** artists_page.dart `_LidarrLookupSheet`: pick the Lidarr lookup match and add it. */
  let {
    artist,
    instance,
    onadded,
    onclose,
  }: { artist: Artist; instance: LidarrInstance | null; onadded: () => void; onclose: () => void } = $props();

  let results = $state<LidarrArtist[] | null>(null);
  let error = $state<string | null>(null);
  let addingMbid = $state<string | null>(null);
  let addedMbid = $state<string | null>(null);
  let failedPosters = $state<ReadonlySet<string>>(new Set());

  $effect(() => {
    api
      .lidarrArtistLookup(artist.name)
      .then((r) => (results = r))
      .catch((e: unknown) => (error = toAppError(e).message));
  });

  async function add(a: LidarrArtist): Promise<void> {
    const root = instance?.defaultRootFolderPath;
    const profile = instance?.defaultQualityProfileId;
    if (instance?.defaultRootFolderId == null || root == null || profile == null) {
      toast('Set a root folder and quality profile in Settings → Lidarr first.');
      return;
    }
    addingMbid = a.mbid;
    try {
      await api.lidarrAddArtist(a, root, profile);
      addedMbid = a.mbid;
      onadded();
    } catch (e) {
      toast(`Failed to add: ${toAppError(e).message}`, { kind: 'error' });
    } finally {
      addingMbid = null;
    }
  }
</script>

<Dialog width={520} {onclose}>
  <div class="sheet">
    <h2>Add "{artist.name}" to Lidarr</h2>
    <p class="hint">Select the correct match from the Lidarr lookup.</p>
    <div class="divider"></div>
    <div class="body">
      {#if error !== null}
        <div class="center error">{error}</div>
      {:else if results === null}
        <div class="center"><Spinner /></div>
      {:else if results.length === 0}
        <div class="center">No results found.</div>
      {:else}
        {#each results as a (a.mbid)}
          {@const added = addedMbid === a.mbid || a.id > 0}
          <div class="item">
            {#if a.posterUrl && !failedPosters.has(a.mbid)}
              <img
                class="avatar"
                src={a.posterUrl}
                alt=""
                loading="lazy"
                onerror={() => (failedPosters = new Set([...failedPosters, a.mbid]))}
              />
            {:else}
              <span class="avatar fallback"><Icon name="person" size={20} /></span>
            {/if}
            <span class="text">
              <span class="name">{a.name}</span>
              {#if a.overview}<span class="overview">{a.overview}</span>{/if}
            </span>
            {#if added}
              <Icon name="check_circle" size={18} color="#4caf50" />
            {:else if addingMbid === a.mbid}
              <Spinner size={18} stroke={1.5} />
            {:else}
              <Button variant="primary" small disabled={addingMbid !== null} onclick={() => void add(a)}>Add</Button>
            {/if}
          </div>
        {/each}
      {/if}
    </div>
  </div>
</Dialog>

<style>
  .sheet {
    height: min(520px, calc(100vh - 120px));
    display: flex;
    flex-direction: column;
  }
  h2 {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
    color: var(--color-text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .hint {
    margin: 4px 0 12px;
    font-size: 12px;
  }
  .divider {
    height: 1px;
    background: var(--color-glass-border);
  }
  .body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 8px 0;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .error {
    color: #ff5252;
    font-size: 12px;
  }
  .item {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 8px 4px;
  }
  .avatar {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 50%;
    object-fit: cover;
  }
  .fallback {
    display: grid;
    place-items: center;
    background: var(--color-surface-variant);
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
  }
  .overview {
    font-size: 11px;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
</style>
