<script lang="ts">
  import { untrack } from 'svelte';
  import LibraryEmpty from '../../widgets/library/LibraryEmpty.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import SelectionActionBar from '../../widgets/library/SelectionActionBar.svelte';
  import { attempt, transferSongs } from '../../widgets/library/actions';
  import { showAddToPlaylistDialog, showSongMetadataDialog } from '../../widgets/library/dialogs';
  import { libraryStatus, SongPresence } from '../../widgets/library/status.svelte';
  import { Windowed } from '../../widgets/library/windowed.svelte';
  import * as api from '../../lib/api';
  import { showContextMenu } from '../../lib/menu';
  import type { Song, SongSort } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { selection, selectAllShortcut } from '../../lib/stores/selection.svelte';
  import { session } from '../../lib/stores/session.svelte';
  import SongTableRow from './SongTableRow.svelte';

  /**
   * songs_page.dart: every song as a sortable table, lazily windowed. `songs_ids` gives the
   * full display order so shift-range / ⌘A selection covers rows that aren't loaded yet.
   */
  const scopeKey = 'songs:all';

  let sort = $state<SongSort>('title');
  let desc = $state(false);
  let ids = $state.raw<string[]>([]);
  let range = $state<[number, number]>([0, 0]);

  const list = $derived.by(() => {
    const s = sort;
    const d = desc;
    return new Windowed<Song>((offset, limit) => api.songsWindow(offset, limit, s, d));
  });

  function loadIds(): void {
    const s = sort;
    const d = desc;
    api
      .songsIds(s, d)
      .then((r) => {
        if (s === sort && d === desc) ids = r;
      })
      .catch((e: unknown) => console.warn('songs: ids failed', e));
  }

  $effect(() => {
    void session.serverId;
    const l = list;
    untrack(() => {
      ids = [];
      void l.reset();
      loadIds();
    });
  });

  let seenRev = libraryStatus.libraryRev;
  $effect(() => {
    const rev = libraryStatus.libraryRev;
    if (rev === seenRev) return;
    seenRev = rev;
    untrack(() => {
      void list.refresh();
      loadIds();
    });
  });

  $effect(() => selection.setScope(scopeKey));
  $effect(() => selectAllShortcut(scopeKey, () => ids));

  const visibleIds = $derived.by(() => {
    const out: string[] = [];
    for (let i = range[0]; i < range[1]; i++) {
      const s = list.get(i);
      if (s) out.push(s.id);
    }
    return out;
  });
  const presence = new SongPresence(() => visibleIds);

  function onRange(start: number, end: number): void {
    range = [start, end];
    void list.ensure(start, end);
  }

  function setSort(col: SongSort): void {
    if (sort === col) desc = !desc;
    else {
      sort = col;
      desc = false;
    }
  }

  /** Queues the whole library in the current table order (Flutter played its loaded list). */
  function play(index: number): void {
    void attempt(api.playerPlayLibrary(sort, desc, index));
  }

  /** Selected songs in display order, fetching any windows that aren't loaded. */
  async function resolveSelected(): Promise<Song[]> {
    const indices: number[] = [];
    ids.forEach((id, i) => {
      if (selection.isSelected(id)) indices.push(i);
    });
    if (indices.length === 0) return [];
    await Promise.all(indices.map((i) => list.ensure(i, i + 1)));
    return indices.map((i) => list.get(i)).filter((s): s is Song => s !== null);
  }

  function onRowClick(e: MouseEvent, index: number, song: Song | null): void {
    if (!song) return;
    if (e.shiftKey) {
      selection.selectRange(scopeKey, ids, index);
      return;
    }
    if (e.metaKey || e.ctrlKey) {
      selection.toggle(scopeKey, song.id, index);
      return;
    }
    if (selection.matches(scopeKey) && !selection.isEmpty) {
      selection.selectOnly(scopeKey, song.id, index);
      return;
    }
    play(index);
  }

  async function onRowMenu(e: MouseEvent, index: number, song: Song): Promise<void> {
    const devs = devices.list;
    const isBulk = selection.matches(scopeKey) && selection.isSelected(song.id) && selection.count > 1;
    const bulkLabel = `${selection.count} selected songs`;
    const result = await showContextMenu(
      [
        { id: 'play', label: 'Play' },
        ...devs.map((d) => ({
          id: `transfer:${d.path}`,
          label: isBulk ? `Transfer ${bulkLabel} to ${d.label}` : `Transfer to ${d.label}`,
        })),
        { id: 'playlist', label: isBulk ? `Add ${bulkLabel} to Playlist` : 'Add to Playlist' },
        { id: 'info', label: 'Get Info' },
      ],
      { x: e.clientX, y: e.clientY },
    );
    if (result === null) return;
    if (result === 'play') play(index);
    else if (result.startsWith('transfer:')) {
      const songs = isBulk ? await resolveSelected() : [song];
      transferSongs(result.slice('transfer:'.length), songs);
      if (isBulk) selection.clear();
    } else if (result === 'playlist') {
      const songIds = isBulk ? ids.filter((id) => selection.isSelected(id)) : [song.id];
      showAddToPlaylistDialog(songIds);
      if (isBulk) selection.clear();
    } else if (result === 'info') showSongMetadataDialog(song);
  }

  const columns: { key: SongSort; label: string; cls: string }[] = [
    { key: 'track', label: '#', cls: 'num' },
    { key: 'title', label: 'Title', cls: 'title' },
    { key: 'artist', label: 'Artist', cls: 'sec' },
    { key: 'album', label: 'Album', cls: 'sec' },
    { key: 'year', label: 'Year', cls: 'year' },
    { key: 'duration', label: 'Time', cls: 'time' },
  ];
</script>

<div class="page">
  <div class="cols" role="row">
    {#each columns as c (c.key)}
      <button type="button" class="col {c.cls}" class:active={sort === c.key} onclick={() => setSort(c.key)}>
        <span>{c.label}</span>
        {#if sort === c.key}<Icon name={desc ? 'chevron_down' : 'chevron_up'} size={12} />{/if}
      </button>
    {/each}
    <span class="col sync"></span>
    <span class="col rating">Rating</span>
    <span class="col star"></span>
  </div>
  <div class="body">
    {#if list.total !== null}
      {#if list.total === 0}
        <LibraryEmpty icon="music_note" title="No songs" message="Your library has no songs yet." />
      {:else}
        <VirtualList count={list.total} rowHeight={36} onRangeChange={onRange}>
          {#snippet row(i: number)}
            {@const s = list.get(i)}
            <SongTableRow
              song={s}
              index={i}
              selected={s !== null && selection.matches(scopeKey) && selection.isSelected(s.id)}
              onDevice={s !== null && presence.has(s.id)}
              onclick={(e) => onRowClick(e, i, s)}
              oncontextmenu={(e) => s && void onRowMenu(e, i, s)}
            />
          {/snippet}
        </VirtualList>
      {/if}
    {:else if list.error}
      <ErrorRetry error={list.error} onRetry={() => list.reset()} />
    {:else}
      <div class="center"><Spinner /></div>
    {/if}
    <div class="bar"><SelectionActionBar {scopeKey} {resolveSelected} /></div>
  </div>
</div>

<style>
  .page {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .cols {
    height: 34px;
    flex: none;
    display: flex;
    align-items: center;
    padding: 0 16px;
    border-bottom: 1px solid var(--color-divider);
  }
  .col {
    display: flex;
    align-items: center;
    gap: 2px;
    min-width: 0;
    padding: 0 12px 0 0;
    border: none;
    background: none;
    font: inherit;
    font-size: 11px;
    font-weight: 500;
    letter-spacing: 0.3px;
    color: var(--color-text-secondary);
    text-align: left;
  }
  button.col:hover,
  .col.active {
    color: var(--color-text-primary);
  }
  .num {
    width: 40px;
    flex: none;
    justify-content: flex-end;
  }
  .title {
    flex: 3;
  }
  .sec {
    flex: 2;
  }
  .year {
    width: 48px;
    flex: none;
  }
  .time {
    width: 55px;
    flex: none;
    justify-content: flex-end;
    padding-right: 0;
  }
  .sync {
    width: 20px;
    flex: none;
  }
  .rating {
    width: 76px;
    flex: none;
    justify-content: center;
    padding: 0;
  }
  .star {
    width: 36px;
    flex: none;
  }
  .body {
    position: relative;
    flex: 1;
    min-height: 0;
  }
  /* Floats above the shell's bottom player bar, which overlays page content. */
  .bar {
    position: absolute;
    left: 0;
    right: 0;
    bottom: var(--scroll-bottom-inset);
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
