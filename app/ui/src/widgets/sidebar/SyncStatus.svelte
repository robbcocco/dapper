<script lang="ts">
  import Icon from '../Icon.svelte';
  import ProgressBar from '../ProgressBar.svelte';
  import { librarySync } from '../../lib/stores/library-sync.svelte';
  import type { SyncPhase } from '../../lib/types';

  /** Library-cache sync line under the server switcher: progress, failure + retry, last sync. */
  const phases: Record<SyncPhase, string> = {
    idle: '',
    checking: 'Checking for changes',
    artists: 'Artists',
    albums: 'Albums',
    songs: 'Songs',
    starred: 'Favourites',
    genres: 'Genres',
    playlists: 'Playlists',
    done: '',
  };

  // Re-render the relative time every 30 s.
  let now = $state(Date.now());
  $effect(() => {
    const t = setInterval(() => (now = Date.now()), 30_000);
    return () => clearInterval(t);
  });

  function ago(iso: string, at: number): string {
    const t = Date.parse(iso);
    if (Number.isNaN(t)) return '';
    const min = Math.floor((at - t) / 60_000);
    if (min < 1) return 'just now';
    if (min < 60) return `${min} min ago`;
    const h = Math.floor(min / 60);
    if (h < 24) return `${h} h ago`;
    return new Date(t).toLocaleDateString();
  }

  const s = $derived(librarySync.status);
  const fraction = $derived(s?.running && s.total ? s.done / s.total : null);
</script>

{#if s}
  <div class="sync-status" class:error={!s.running && !!s.error}>
    {#if s.running}
      <div class="line">
        <Icon name="sync" size={12} />
        <span class="text">Syncing library{phases[s.phase] ? ` · ${phases[s.phase]}` : ''}{s.total ? ` ${s.done}/${s.total}` : ''}</span>
      </div>
      <ProgressBar value={fraction} height={2} />
    {:else}
      <div class="line">
        <Icon name={s.error ? 'error' : 'cloud_done'} size={12} />
        <span class="text" title={s.error ?? undefined}>
          {#if s.error}Library sync failed{:else if s.lastSyncedAt}Synced {ago(s.lastSyncedAt, now)}{:else}Not synced{/if}
        </span>
        <button type="button" class="refresh" title="Sync library now" aria-label="Sync library now" onclick={() => librarySync.start()}>
          <Icon name="refresh" size={12} />
        </button>
      </div>
    {/if}
  </div>
{/if}

<style>
  .sync-status {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin: 0 16px 4px;
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .sync-status.error {
    color: #ff6b6b;
  }
  .line {
    display: flex;
    align-items: center;
    gap: 6px;
    min-height: 18px;
  }
  .text {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .refresh {
    display: grid;
    place-items: center;
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-secondary);
    opacity: 0.7;
  }
  .refresh:hover {
    opacity: 1;
    color: var(--color-text-primary);
  }
</style>
