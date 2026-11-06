<script lang="ts">
  import type { Snippet } from 'svelte';
  import BaseSongRow from '../SongRow.svelte';
  import { showContextMenu, type MenuItem } from '../../lib/menu';
  import type { Song } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { player } from '../../lib/stores/player.svelte';
  import { selection } from '../../lib/stores/selection.svelte';
  import { starred } from '../../lib/stores/starred.svelte';
  import { transferSongs } from './actions';
  import { showAddToPlaylistDialog, showSongMetadataDialog } from './dialogs';

  /**
   * Library-aware song_row.dart: playing/starred state, modifier-click selection when
   * `scopeKey` + `allSongs` are given, and the (bulk-aware) context menu.
   */
  let {
    song,
    index,
    showArtist = false,
    selected,
    scopeKey,
    allSongs,
    onTap,
    onRemove,
    addToPlaylist = true,
    getInfo = true,
    trailing,
  }: {
    song: Song;
    index?: number;
    showArtist?: boolean;
    /** Defaults to the selection store's state for `scopeKey`. */
    selected?: boolean;
    scopeKey?: string;
    allSongs?: Song[];
    onTap?: () => void;
    onRemove?: () => void;
    addToPlaylist?: boolean;
    getInfo?: boolean;
    trailing?: Snippet;
  } = $props();

  const isSelected = $derived(
    selected ?? (scopeKey !== undefined && selection.matches(scopeKey) && selection.isSelected(song.id)),
  );
  const playing = $derived(player.state.currentSong?.id === song.id);

  function onclick(e: MouseEvent): void {
    if (scopeKey === undefined || allSongs === undefined) {
      onTap?.();
      return;
    }
    const ids = allSongs.map((s) => s.id);
    const pos = ids.indexOf(song.id);
    if (pos < 0) {
      onTap?.();
      return;
    }
    if (e.shiftKey) selection.selectRange(scopeKey, ids, pos);
    else if (e.metaKey || e.ctrlKey) selection.toggle(scopeKey, song.id, pos);
    // Plain click collapses an active selection (Finder-style); otherwise it plays.
    else if (selection.matches(scopeKey) && !selection.isEmpty) selection.selectOnly(scopeKey, song.id, pos);
    else onTap?.();
  }

  async function oncontextmenu(e: MouseEvent): Promise<void> {
    const devs = devices.list;
    const isBulk =
      scopeKey !== undefined &&
      allSongs !== undefined &&
      selection.matches(scopeKey) &&
      selection.isSelected(song.id) &&
      selection.count > 1;
    const bulkSongs = isBulk ? allSongs!.filter((s) => selection.isSelected(s.id)) : [];
    const bulkLabel = `${bulkSongs.length} selected songs`;
    const items: MenuItem[] = [
      { id: 'play', label: 'Play' },
      ...devs.map((d) => ({
        id: `transfer:${d.path}`,
        label: isBulk ? `Transfer ${bulkLabel} to ${d.label}` : `Transfer to ${d.label}`,
      })),
      ...(addToPlaylist ? [{ id: 'playlist', label: isBulk ? `Add ${bulkLabel} to Playlist` : 'Add to Playlist' }] : []),
      ...(onRemove ? [{ id: 'remove', label: 'Remove from Playlist' }] : []),
      ...(getInfo ? [{ id: 'info', label: 'Get Info' }] : []),
    ];
    const result = await showContextMenu(items, { x: e.clientX, y: e.clientY });
    if (result === null) return;
    if (result === 'play') onTap?.();
    else if (result.startsWith('transfer:')) {
      transferSongs(result.slice('transfer:'.length), isBulk ? bulkSongs : [song]);
      if (isBulk) selection.clear();
    } else if (result === 'playlist') {
      showAddToPlaylistDialog(isBulk ? bulkSongs.map((s) => s.id) : [song.id]);
      if (isBulk) selection.clear();
    } else if (result === 'remove') onRemove?.();
    else if (result === 'info') showSongMetadataDialog(song);
  }
</script>

<BaseSongRow
  {song}
  {index}
  {showArtist}
  selected={isSelected}
  {playing}
  starred={starred.has(song.id)}
  {onclick}
  oncontextmenu={(e) => void oncontextmenu(e)}
  onToggleStar={() => void starred.toggle(song.id)}
  {trailing}
/>
