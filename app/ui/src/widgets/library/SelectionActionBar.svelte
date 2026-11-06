<script lang="ts">
  import BaseBar from '../SelectionActionBar.svelte';
  import Button from '../Button.svelte';
  import { showContextMenu } from '../../lib/menu';
  import type { Song } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { selection } from '../../lib/stores/selection.svelte';
  import { transferSongs } from './actions';
  import { showAddToPlaylistDialog } from './dialogs';

  /**
   * selection_action_bar.dart. Selected songs come from `allSongs` (display order) or,
   * for windowed lists that don't hold every row, from `resolveSelected`.
   */
  let {
    scopeKey,
    allSongs,
    resolveSelected,
  }: { scopeKey: string; allSongs?: Song[]; resolveSelected?: () => Promise<Song[]> } = $props();

  const count = $derived(selection.matches(scopeKey) ? selection.count : 0);

  async function selectedSongs(): Promise<Song[]> {
    if (resolveSelected) return resolveSelected();
    return (allSongs ?? []).filter((s) => selection.isSelected(s.id));
  }

  async function enqueueTo(path: string): Promise<void> {
    const songs = await selectedSongs();
    if (songs.length === 0) return;
    transferSongs(path, songs);
    selection.clear();
  }

  async function pickDevice(e: MouseEvent): Promise<void> {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const path = await showContextMenu(
      devices.list.map((d) => ({ id: d.path, label: d.label })),
      { x: r.left, y: r.bottom },
    );
    if (path !== null) await enqueueTo(path);
  }

  async function addToPlaylist(): Promise<void> {
    const songs = await selectedSongs();
    showAddToPlaylistDialog(songs.map((s) => s.id));
  }
</script>

<BaseBar {count} onClear={() => selection.clear()}>
  {#if devices.list.length > 1}
    <Button variant="text" small icon="download" title="Transfer to…" onclick={(e) => void pickDevice(e)}>Transfer ▾</Button>
  {:else}
    <Button
      variant="text"
      small
      icon="download"
      disabled={devices.selected === null}
      onclick={() => devices.selected && void enqueueTo(devices.selected.path)}>Transfer</Button
    >
  {/if}
  <Button variant="text" small icon="playlist_add" onclick={() => void addToPlaylist()}>Add to playlist</Button>
</BaseBar>
