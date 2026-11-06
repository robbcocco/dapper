<script lang="ts">
  import type { Playlist } from '../../lib/types';
  import { showContextMenu } from '../../lib/menu';
  import { playlists } from '../../lib/stores/playlists.svelte';
  import { selectionNav } from '../../lib/stores/selection-nav.svelte';
  import { confirm, prompt } from '../../widgets/dialogs';
  import CoverArt from '../../widgets/CoverArt.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';

  let { items }: { items: Playlist[] } = $props();

  async function rename(p: Playlist): Promise<void> {
    const name = await prompt({ title: 'Rename Playlist', initial: p.name, confirmLabel: 'Rename' });
    if (name !== null) void playlists.rename(p.id, name);
  }

  async function remove(p: Playlist): Promise<void> {
    const ok = await confirm({
      title: 'Delete Playlist',
      message: `Delete "${p.name}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    });
    if (ok) void playlists.delete(p.id);
  }

  async function menu(e: MouseEvent, p: Playlist): Promise<void> {
    e.preventDefault();
    const id = await showContextMenu(
      [
        { id: 'rename', label: 'Rename' },
        { id: 'delete', label: 'Delete' },
      ],
      { x: e.clientX, y: e.clientY },
    );
    if (id === 'rename') await rename(p);
    else if (id === 'delete') await remove(p);
  }
</script>

<VirtualList count={items.length} rowHeight={56}>
  {#snippet row(i)}
    {@const p = items[i]!}
    <button class="row" onclick={() => (selectionNav.selectedPlaylistId = p.id)} oncontextmenu={(e) => void menu(e, p)}>
      <CoverArt coverArtId={p.coverArtId} size={80} display="40px" radius={4} />
      <span class="text">
        <span class="name">{p.name}</span>
        <span class="count">{p.songCount} songs</span>
      </span>
    </button>
  {/snippet}
</VirtualList>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    height: 100%;
    padding: 8px 24px;
    border: none;
    background: transparent;
    color: inherit;
    font: inherit;
    text-align: left;
  }
  .row:hover {
    background: rgba(255, 255, 255, 0.03);
  }
  .text {
    display: flex;
    flex-direction: column;
    justify-content: center;
    min-width: 0;
  }
  .name {
    font-size: 13px;
    color: var(--color-text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .count {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
</style>
