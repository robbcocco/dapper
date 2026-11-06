<script lang="ts">
  import Dialog from '../Dialog.svelte';
  import Button from '../Button.svelte';
  import Icon from '../Icon.svelte';
  import Spinner from '../Spinner.svelte';
  import TextField from '../TextField.svelte';
  import * as api from '../../lib/api';
  import { toAppError } from '../../lib/ipc';
  import type { Playlist } from '../../lib/types';
  import { attempt } from './actions';

  /** Port of add_to_playlist_dialog.dart: pick an existing playlist or create a new one. */
  let { songIds, onresult }: { songIds: string[]; onresult: (r: null) => void } = $props();

  let playlists = $state<Playlist[] | null>(null);
  let loadError = $state<string | null>(null);
  let creating = $state(false);
  let name = $state('');
  let saving = $state(false);

  $effect(() => {
    api
      .playlistsList()
      .then((list) => (playlists = list))
      .catch((e: unknown) => (loadError = toAppError(e).message));
  });

  function addTo(p: Playlist): void {
    onresult(null);
    void attempt(api.playlistAddSongs(p.id, songIds), 'Could not add songs to playlist');
  }

  function createAndAdd(): void {
    const trimmed = name.trim();
    if (trimmed === '' || saving) return;
    saving = true;
    onresult(null);
    void attempt(api.playlistCreate(trimmed, songIds), 'Could not create playlist');
  }
</script>

<Dialog title="Add to Playlist" width={360} onclose={() => onresult(null)}>
  {#if creating}
    <form
      class="create"
      onsubmit={(e) => {
        e.preventDefault();
        createAndAdd();
      }}
    >
      <!-- svelte-ignore a11y_autofocus -->
      <TextField bind:value={name} placeholder="Playlist name" autofocus />
      <div class="actions">
        <Button variant="text" onclick={() => (creating = false)}>Cancel</Button>
        <Button variant="primary" type="submit" disabled={saving}>
          {#if saving}<Spinner size={14} />{:else}Create{/if}
        </Button>
      </div>
    </form>
  {:else}
    <button type="button" class="new" onclick={() => (creating = true)}>
      <Icon name="add" size={18} />
      <span>New Playlist</span>
    </button>
    <div class="divider"></div>
    {#if loadError !== null}
      <p class="error">{loadError}</p>
    {:else if playlists === null}
      <div class="loading"><Spinner /></div>
    {:else}
      <div class="list">
        {#each playlists as p (p.id)}
          <button type="button" class="item" onclick={() => addTo(p)}>
            <Icon name="queue_music" size={18} />
            <span class="name">{p.name}</span>
            <span class="count">{p.songCount}</span>
          </button>
        {/each}
      </div>
    {/if}
  {/if}
</Dialog>

<style>
  .create {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
  .new,
  .item {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    border: none;
    background: none;
    font: inherit;
    text-align: left;
    border-radius: 6px;
  }
  .new {
    padding: 10px 4px;
    color: var(--color-accent);
  }
  .item {
    height: 44px;
    padding: 0 4px;
    color: var(--color-text-secondary);
  }
  .new:hover,
  .item:hover {
    background: rgba(255, 255, 255, 0.05);
  }
  .name {
    flex: 1;
    min-width: 0;
    color: var(--color-text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .count {
    font-size: 11px;
  }
  .divider {
    height: 1px;
    background: var(--color-divider);
  }
  .list {
    max-height: 280px;
    overflow-y: auto;
    padding-top: 4px;
  }
  .loading {
    display: grid;
    place-items: center;
    padding: 24px;
  }
  .error {
    margin: 16px 0;
  }
</style>
