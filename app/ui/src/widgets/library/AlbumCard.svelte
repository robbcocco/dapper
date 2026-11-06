<script lang="ts">
  import CoverArt from '../CoverArt.svelte';
  import SyncDot, { type SyncState } from '../SyncDot.svelte';
  import { showContextMenu } from '../../lib/menu';
  import type { Album } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { openAlbum } from '../../lib/stores/library-nav.svelte';
  import { fetchAlbum, playAlbum, transferAlbum, transferLabel } from './actions';
  import { showAddToPlaylistDialog, showAlbumInfoDialog } from './dialogs';
  import { libraryStatus } from './status.svelte';

  /**
   * albums_page.dart `_AlbumCard`: cover with queue/sync dot, title, artist, context menu.
   * `plain` drops the dot and menu (genres_page.dart `_GenreAlbumCard`).
   * Grids showing dots must hold `libraryStatus.watchAlbumSync()`.
   */
  let { album, width, plain = false }: { album: Album | null; width: number; plain?: boolean } = $props();

  const dot = $derived.by((): { state: SyncState; pulse: boolean } | null => {
    if (plain || !album) return null;
    const q = libraryStatus.albumQueue(album.id);
    if (q.active || q.queued) return { state: 'queued', pulse: q.active };
    const s = devices.selected ? libraryStatus.albumSync[album.id] : undefined;
    return s === 'full' || s === 'partial' ? { state: s, pulse: false } : null;
  });

  async function oncontextmenu(e: MouseEvent): Promise<void> {
    e.preventDefault();
    if (plain || !album) return;
    const a = album;
    const devs = devices.list;
    const result = await showContextMenu(
      [
        { id: 'open', label: 'Open Album' },
        { id: 'play', label: 'Play Album' },
        ...devs.map((d) => ({ id: `transfer:${d.path}`, label: transferLabel(devs, d, 'Album') })),
        { id: 'playlist', label: 'Add to Playlist' },
        { id: 'info', label: 'Get Info' },
      ],
      { x: e.clientX, y: e.clientY },
    );
    if (result === null) return;
    if (result === 'open') openAlbum(a.id);
    else if (result === 'play') playAlbum(a.id);
    else if (result.startsWith('transfer:')) transferAlbum(result.slice('transfer:'.length), a.id);
    else if (result === 'playlist') {
      const full = await fetchAlbum(a.id);
      if (full) showAddToPlaylistDialog(full.songs.map((s) => s.id));
    } else if (result === 'info') {
      const full = await fetchAlbum(a.id);
      if (full) showAlbumInfoDialog(full);
    }
  }
</script>

{#if album}
  <button type="button" class="card" style:width="{width}px" onclick={() => openAlbum(album.id)} oncontextmenu={(e) => void oncontextmenu(e)}>
    <span class="cover">
      <CoverArt coverArtId={album.coverArtId} size={300} radius={6} display="{width}px" />
      {#if dot}<span class="dot"><SyncDot state={dot.state} pulse={dot.pulse} size={10} /></span>{/if}
    </span>
    <span class="name">{album.name}</span>
    {#if album.artist}<span class="artist">{album.artist}</span>{/if}
  </button>
{:else}
  <div class="card" style:width="{width}px">
    <span class="skeleton" style:height="{width}px"></span>
  </div>
{/if}

<style>
  .card {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    padding: 0;
    border: none;
    background: none;
    font: inherit;
    text-align: left;
    color: inherit;
  }
  .cover {
    position: relative;
    display: block;
  }
  .dot {
    position: absolute;
    right: 6px;
    bottom: 6px;
    display: flex;
  }
  .name,
  .artist {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .name {
    margin-top: 6px;
    font-size: 12px;
    font-weight: 500;
  }
  .artist {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .skeleton {
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.04);
  }
</style>
