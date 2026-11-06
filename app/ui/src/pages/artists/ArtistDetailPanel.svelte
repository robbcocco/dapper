<script lang="ts">
  import { untrack } from 'svelte';
  import Button from '../../widgets/Button.svelte';
  import CoverArt from '../../widgets/CoverArt.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import SyncDot, { type SyncState } from '../../widgets/SyncDot.svelte';
  import SelectionActionBar from '../../widgets/library/SelectionActionBar.svelte';
  import SongRow from '../../widgets/library/SongRow.svelte';
  import SongSyncDot from '../../widgets/library/SongSyncDot.svelte';
  import VariableList from '../../widgets/library/VariableList.svelte';
  import {
    playArtist,
    playSongs,
    plural,
    shuffleArtist,
    transferAlbum,
    transferArtist,
    transferLabel,
  } from '../../widgets/library/actions';
  import { pickDevicePath, showAddToPlaylistDialog, showAlbumInfoDialog } from '../../widgets/library/dialogs';
  import { Resource } from '../../widgets/library/resource.svelte';
  import { libraryStatus, SongPresence } from '../../widgets/library/status.svelte';
  import * as api from '../../lib/api';
  import { showContextMenu } from '../../lib/menu';
  import type { Album, Artist, LidarrAlbum, LidarrArtist, LidarrInstance } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { openAlbum } from '../../lib/stores/library-nav.svelte';
  import { openLidarrArtist } from '../../lib/stores/lidarr-nav.svelte';
  import { selection } from '../../lib/stores/selection.svelte';
  import { session } from '../../lib/stores/session.svelte';
  import { showInteractiveSearch } from '../lidarr/interactiveSearch.svelte';
  import LidarrLookupSheet from './LidarrLookupSheet.svelte';

  /** artists_page.dart `_ArtistDetailPanel`: header + every album with its songs. */
  let {
    artist,
    lidarrArtist,
    lidarrInstance,
    onLidarrChanged,
  }: {
    artist: Artist;
    lidarrArtist: LidarrArtist | null;
    /** Selected Lidarr instance; null when Lidarr isn't connected. */
    lidarrInstance: LidarrInstance | null;
    onLidarrChanged: () => void;
  } = $props();

  /** Normalises an album title for fuzzy cross-service matching (`_normalizeTitle`). */
  const normalizeTitle = (s: string): string =>
    s
      .toLowerCase()
      .replace(/[^\w\s]/g, '')
      .replace(/\s+/g, ' ')
      .trim();

  const albums = new Resource<Album[]>((id) => api.artistAlbums(id), () => artist.id);
  const lidarrAlbums = new Resource<LidarrAlbum[]>(
    (key) => (key === '' ? Promise.resolve([]) : api.lidarrArtistAlbums(Number(key))),
    () => (lidarrArtist ? String(lidarrArtist.id) : ''),
  );
  const lidarrByTitle = $derived(new Map((lidarrAlbums.value ?? []).map((a) => [normalizeTitle(a.title), a])));

  // Full albums (with songs), fetched as their sections scroll into view (albumProvider).
  let full = $state.raw<ReadonlyMap<string, Album>>(new Map());
  const requested = new Set<string>();
  $effect(() => {
    void session.serverId;
    void libraryStatus.libraryRev;
    void artist.id;
    untrack(() => {
      requested.clear();
      full = new Map();
      if (lastRange) ensureFull(lastRange[0], lastRange[1]);
    });
  });

  type Row =
    | { kind: 'album'; album: Album; first: boolean }
    | { kind: 'song'; album: Album; index: number }
    | { kind: 'loading'; album: Album };

  const rows = $derived.by((): Row[] => {
    const out: Row[] = [];
    (albums.value ?? []).forEach((album, i) => {
      out.push({ kind: 'album', album, first: i === 0 });
      const f = full.get(album.id);
      if (!f) out.push({ kind: 'loading', album });
      else f.songs.forEach((_, index) => out.push({ kind: 'song', album, index }));
    });
    return out;
  });
  const rowHeight = (i: number): number => (rows[i]?.kind === 'album' ? 82 : 40);

  let lastRange: [number, number] | null = null;
  function ensureFull(start: number, end: number): void {
    for (let i = start; i < Math.min(end, rows.length); i++) {
      const r = rows[i]!;
      if (r.kind !== 'loading' || requested.has(r.album.id)) continue;
      const id = r.album.id;
      requested.add(id);
      api
        .albumGet(id)
        .then((a) => {
          const next = new Map(full);
          next.set(id, a);
          full = next;
        })
        .catch((e: unknown) => {
          // Error → the section stays without songs (Dart renders nothing).
          console.warn('artist detail: album fetch failed', e);
          const next = new Map(full);
          next.set(id, { ...r.album, songs: [] });
          full = next;
        });
    }
  }
  function onRange(start: number, end: number): void {
    lastRange = [start, end];
    ensureFull(start, end);
  }

  const totalSongs = $derived((albums.value ?? []).reduce((n, a) => n + a.songCount, 0));
  const allIds = $derived([...full.values()].flatMap((a) => a.songs.map((s) => s.id)));
  const presence = new SongPresence(() => allIds);

  $effect(() => libraryStatus.watchAlbumSync());

  function albumDot(album: Album): { state: SyncState; pulse: boolean } | null {
    const q = libraryStatus.albumQueue(album.id);
    if (q.active || q.queued) return { state: 'queued', pulse: q.active };
    const s = devices.selected ? libraryStatus.albumSync[album.id] : undefined;
    return s === 'full' || s === 'partial' ? { state: s, pulse: false } : null;
  }

  async function loadFull(album: Album): Promise<Album | null> {
    const cached = full.get(album.id);
    if (cached) return cached;
    try {
      return await api.albumGet(album.id);
    } catch {
      return null;
    }
  }

  async function albumMenu(e: MouseEvent, album: Album, at?: { x: number; y: number }): Promise<void> {
    e.preventDefault();
    e.stopPropagation();
    const devs = devices.list;
    const lidarrAlbum = lidarrByTitle.get(normalizeTitle(album.name));
    const result = await showContextMenu(
      [
        { id: 'open', label: 'Open Album' },
        { id: 'play', label: 'Play Album' },
        ...devs.map((d) => ({ id: `transfer:${d.path}`, label: transferLabel(devs, d, 'Album') })),
        { id: 'playlist', label: 'Add to Playlist' },
        { id: 'info', label: 'Get Info' },
        ...(lidarrAlbum ? [{ id: 'interactive_search', label: 'Interactive Search' }] : []),
      ],
      at ?? { x: e.clientX, y: e.clientY },
    );
    if (result === null) return;
    if (result === 'interactive_search' && lidarrAlbum) showInteractiveSearch(lidarrAlbum.id, album.name);
    else if (result === 'open') openAlbum(album.id);
    else if (result.startsWith('transfer:')) transferAlbum(result.slice('transfer:'.length), album.id);
    else {
      const f = await loadFull(album);
      if (!f) return;
      if (result === 'play') playSongs(f.songs, 0);
      else if (result === 'playlist') showAddToPlaylistDialog(f.songs.map((s) => s.id));
      else if (result === 'info') showAlbumInfoDialog(f);
    }
  }

  function moreMenu(e: MouseEvent, album: Album): void {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    void albumMenu(e, album, { x: r.left, y: r.bottom });
  }

  async function transferAll(): Promise<void> {
    const path = await pickDevicePath(devices.list);
    if (path !== null) transferArtist(path, artist.id);
  }

  // `_ArtistSelectionBar`: the bar follows whichever album section holds the selection.
  const selectedAlbum = $derived.by(() => {
    const scope = selection.scopeKey;
    if (scope === null || selection.isEmpty || !scope.startsWith('album:')) return null;
    return full.get(scope.slice('album:'.length)) ?? null;
  });

  let lookupOpen = $state(false);
</script>

{#if albums.value}
  <div class="panel">
    <VariableList count={rows.length} {rowHeight} onRangeChange={onRange}>
      {#snippet header()}
        <header class="head">
          <CoverArt coverArtId={artist.coverArtId} size={300} radius={44} display="88px" />
          <div class="meta">
            <h1>{artist.name}</h1>
            <div class="sub">{plural(albums.value?.length ?? 0, 'album')} · {plural(totalSongs, 'song')}</div>
            <div class="actions">
              <Button icon="play" small onclick={() => playArtist(artist.id)}>Play</Button>
              <Button icon="shuffle" small onclick={() => void shuffleArtist(artist.id)}>Shuffle</Button>
              {#if devices.list.length > 0}
                <Button variant="primary" icon="download" small onclick={() => void transferAll()}>Transfer All</Button>
              {/if}
              {#if lidarrInstance}
                {#if lidarrArtist}
                  <button
                    type="button"
                    class="lidarr-link"
                    disabled={lidarrArtist.mbid === ''}
                    onclick={() => lidarrArtist && openLidarrArtist(lidarrArtist.mbid)}
                  >
                    <Icon name="chevron_right" size={13} /> Lidarr Page
                  </button>
                {:else}
                  <Button icon="add" small onclick={() => (lookupOpen = true)}>Add to Lidarr</Button>
                {/if}
              {/if}
            </div>
          </div>
        </header>
        <div class="divider"></div>
      {/snippet}
      {#snippet row(i: number)}
        {@const r = rows[i]!}
        {#if r.kind === 'album'}
          {@const dot = albumDot(r.album)}
          <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
          <div
            class="album"
            class:first={r.first}
            onclick={() => openAlbum(r.album.id)}
            oncontextmenu={(e) => void albumMenu(e, r.album)}
          >
            <CoverArt coverArtId={r.album.coverArtId} size={300} radius={6} display="52px" />
            <div class="album-meta">
              <div class="album-name">{r.album.name}</div>
              <div class="sub">
                {[r.album.year != null ? String(r.album.year) : null, plural(r.album.songCount, 'song')]
                  .filter(Boolean)
                  .join(' · ')}
              </div>
            </div>
            {#if dot}<span class="dot"><SyncDot state={dot.state} pulse={dot.pulse} size={8} /></span>{/if}
            <IconButton icon="more" size={16} label="More" onclick={(e) => (e.stopPropagation(), moreMenu(e, r.album))} />
          </div>
        {:else if r.kind === 'loading'}
          <div class="loading"><Spinner size={16} /></div>
        {:else}
          {@const songs = full.get(r.album.id)?.songs ?? []}
          {@const s = songs[r.index]}
          {#if s}
            <SongRow
              song={s}
              index={r.index}
              scopeKey={`album:${r.album.id}`}
              allSongs={songs}
              onTap={() => playSongs(songs, r.index)}
            >
              {#snippet trailing()}<SongSyncDot songId={s.id} onDevice={presence.has(s.id)} />{/snippet}
            </SongRow>
          {/if}
        {/if}
      {/snippet}
    </VariableList>
    {#if selectedAlbum}
      <div class="bar"><SelectionActionBar scopeKey={`album:${selectedAlbum.id}`} allSongs={selectedAlbum.songs} /></div>
    {/if}
  </div>
  {#if lookupOpen}
    <LidarrLookupSheet {artist} instance={lidarrInstance} onadded={onLidarrChanged} onclose={() => (lookupOpen = false)} />
  {/if}
{:else if albums.error}
  <ErrorRetry error={albums.error} onRetry={() => albums.retry()} />
{:else}
  <div class="center"><Spinner /></div>
{/if}

<style>
  .panel {
    position: relative;
    height: 100%;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 20px;
    padding: 28px 28px 20px;
  }
  .meta {
    flex: 1;
    min-width: 0;
  }
  h1 {
    margin: 0;
    font-size: 26px;
    font-weight: 700;
  }
  .sub {
    margin-top: 4px;
    font-size: 13px;
    color: var(--color-text-secondary);
  }
  .album .sub {
    margin-top: 2px;
    font-size: 12px;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
    margin-top: 14px;
  }
  .lidarr-link {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 6px 10px;
    border-radius: 8px;
    border: 1px solid rgba(76, 175, 80, 0.35);
    background: rgba(76, 175, 80, 0.1);
    color: #4caf50;
    font: inherit;
    font-size: 12px;
  }
  .lidarr-link:disabled {
    opacity: 0.6;
  }
  .divider {
    height: 1px;
    background: var(--color-divider);
  }
  .album {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 10px 16px 0 28px;
    cursor: default;
  }
  .album:not(.first) {
    border-top: 1px solid var(--color-divider);
  }
  .album-meta {
    flex: 1;
    min-width: 0;
  }
  .album-name {
    font-size: 15px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .dot {
    display: flex;
    margin-right: 6px;
  }
  .loading {
    height: 100%;
    display: grid;
    place-items: center;
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
