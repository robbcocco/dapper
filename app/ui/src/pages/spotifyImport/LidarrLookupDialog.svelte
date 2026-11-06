<script lang="ts">
  import { untrack } from 'svelte';
  import * as api from '../../lib/api';
  import type { LidarrAlbumLookup, LidarrArtist, SpotifyTrack } from '../../lib/types';
  import { showContextMenu } from '../../lib/menu';
  import { toast } from '../../lib/stores/toast.svelte';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import Tabs from '../../widgets/Tabs.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import ExtraIcon from '../../widgets/playlists/ExtraIcon.svelte';
  import DiscographyDialog from './DiscographyDialog.svelte';
  import LidarrCover from './LidarrCover.svelte';
  import ReleasePickerDialog from './ReleasePickerDialog.svelte';
  import { albumTypeLabel, errMsg, missingDefaultsMessage, releaseYear, selectedLidarrInstance } from './lidarr';

  let { track, onclose }: { track: SpotifyTrack; onclose: () => void } = $props();

  type Mode = 'artist' | 'album';
  const primaryArtist = (): string => track.artist.split(/[,&]/)[0]!.trim();

  let mode = $state<Mode>('artist');
  let query = $state(untrack(primaryArtist));
  let artistResults = $state<LidarrArtist[] | null>(null);
  let albumResults = $state<LidarrAlbumLookup[] | null>(null);
  let searching = $state(false);
  /** Row mid-POST: artist mbid or album foreignAlbumId. */
  let addingKey = $state<string | null>(null);
  let lidarrByMbid = $state<Record<string, LidarrArtist>>({});
  let discography = $state<{ id: number; name: string } | null>(null);
  let releasePicker = $state<{ id: number; title: string; closeAfter: boolean } | null>(null);

  let timer: ReturnType<typeof setTimeout> | undefined;
  let seq = 0;

  async function lookup(q: string): Promise<void> {
    const my = ++seq;
    const m = mode;
    searching = true;
    try {
      if (m === 'artist') {
        const r = await api.lidarrArtistLookup(q);
        if (my === seq) artistResults = r;
      } else {
        const r = await api.lidarrAlbumLookup(q);
        if (my === seq) albumResults = r;
      }
    } catch {
      // Lookup failures just leave the previous results in place.
    } finally {
      if (my === seq) searching = false;
    }
  }

  $effect(() => {
    untrack(() => {
      const seed = query;
      if (seed !== '') void lookup(seed);
    });
    api
      .lidarrArtists()
      .then((list) => (lidarrByMbid = Object.fromEntries(list.map((a) => [a.mbid, a]))))
      .catch(() => {});
    return () => clearTimeout(timer);
  });

  function setMode(m: Mode): void {
    // Tidal exposes the album per track; when present, album mode seeds "<artist> <album>".
    const artist = primaryArtist();
    const seed = m === 'artist' ? artist : track.album ? `${artist} ${track.album}`.trim() : artist;
    clearTimeout(timer);
    seq++;
    artistResults = null;
    albumResults = null;
    searching = false;
    query = seed;
    if (seed !== '') void lookup(seed);
  }

  function onQuery(raw: string): void {
    clearTimeout(timer);
    const v = raw.trim();
    if (v === '') {
      seq++;
      artistResults = null;
      albumResults = null;
      searching = false;
      return;
    }
    searching = true;
    timer = setTimeout(() => void lookup(v), 400);
  }

  async function addArtist(a: LidarrArtist): Promise<void> {
    const inst = await selectedLidarrInstance();
    if (inst === null) return;
    if (inst.defaultRootFolderId == null || inst.defaultRootFolderPath == null || inst.defaultQualityProfileId == null) {
      toast(missingDefaultsMessage);
      return;
    }
    addingKey = a.mbid;
    try {
      const added = await api.lidarrAddArtist(a, inst.defaultRootFolderPath, inst.defaultQualityProfileId);
      if (added.id > 0) void api.lidarrSearchArtist(added.id).catch(() => {});
      toast(`Added ${a.name} to Lidarr.`);
      onclose();
    } catch (e) {
      addingKey = null;
      toast(`Failed to add: ${errMsg(e)}`, { kind: 'error' });
    }
  }

  /** Adds the album, then either lets Lidarr auto-search or opens the release picker on it. */
  async function addAlbum(album: LidarrAlbumLookup, interactive: boolean): Promise<void> {
    const inst = await selectedLidarrInstance();
    if (inst === null) return;
    if (inst.defaultRootFolderPath == null || inst.defaultQualityProfileId == null) {
      toast(missingDefaultsMessage);
      return;
    }
    addingKey = album.foreignAlbumId;
    try {
      // No automatic search when picking manually, or Lidarr would grab something
      // in the background while the picker is open.
      const newId = await api.lidarrAddAlbum(album, inst.defaultRootFolderPath, inst.defaultQualityProfileId, !interactive);
      addingKey = null;
      if (interactive && newId > 0) {
        releasePicker = { id: newId, title: album.title, closeAfter: true };
      } else {
        toast(`Added "${album.title}" to Lidarr and started search.`);
        onclose();
      }
    } catch (e) {
      addingKey = null;
      toast(`Failed to add album: ${errMsg(e)}`, { kind: 'error' });
    }
  }

  async function searchExisting(album: LidarrAlbumLookup): Promise<void> {
    try {
      await api.lidarrSearchAlbum(album.lidarrAlbumId);
      toast(`Started search for "${album.title}".`);
    } catch (e) {
      toast(`Search failed: ${errMsg(e)}`, { kind: 'error' });
    }
  }

  function openReleases(album: LidarrAlbumLookup): void {
    releasePicker = { id: album.lidarrAlbumId, title: album.title, closeAfter: false };
  }

  function openDiscography(a: LidarrArtist): void {
    // MusicBrainz-sourced rows carry no Lidarr id; fall back to the cached artist list.
    const id = a.id !== 0 ? a.id : (lidarrByMbid[a.mbid]?.id ?? 0);
    if (id === 0) return;
    discography = { id, name: a.name };
  }

  async function albumMenu(e: MouseEvent, album: LidarrAlbumLookup): Promise<void> {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const id = await showContextMenu(
      [
        { id: 'add_search', label: 'Add & auto search' },
        { id: 'add_pick', label: 'Add & pick a release…' },
      ],
      { x: r.left, y: r.bottom },
    );
    if (id === 'add_search') await addAlbum(album, false);
    else if (id === 'add_pick') await addAlbum(album, true);
  }

  function albumSubtitle(a: LidarrAlbumLookup): string {
    const year = releaseYear(a.releaseDate);
    const yearLabel = year !== null ? ` · ${year}` : '';
    const typeLabel = a.albumType !== null && a.albumType !== 'other' ? ` · ${albumTypeLabel[a.albumType].replaceAll('s', '')}` : '';
    return `${a.artistName}${yearLabel}${typeLabel}`;
  }

  const modes = [
    { value: 'artist', label: 'Artist' },
    { value: 'album', label: 'Album' },
  ] as const;
</script>

<Dialog title="Find on Lidarr" width={540} {onclose}>
  <div class="frame">
    <div class="subtitle">Missing: {track.artist} — {track.title}</div>
    <div class="tabs"><Tabs value={mode} tabs={modes} onchange={(m) => m !== mode && setMode(m)} /></div>
    <TextField
      search
      bind:value={query}
      placeholder={mode === 'artist' ? 'Search Lidarr for an artist…' : 'Search Lidarr for an album…'}
      oninput={(e) => onQuery(e.currentTarget.value)}
      onclear={() => onQuery('')}
    />
    <div class="body">
      {#if mode === 'artist'}
        {#if searching && artistResults === null}
          <div class="center"><Spinner size={28} /></div>
        {:else if !artistResults || artistResults.length === 0}
          <div class="center"><span class="muted">No results.</span></div>
        {:else}
          {@const list = artistResults}
          <VirtualList count={list.length} rowHeight={48}>
            {#snippet row(i)}
            {@const a = list[i]!}
            {@const added = a.id > 0 || a.mbid in lidarrByMbid}
            <div class="row">
              <LidarrCover url={a.posterUrl} size={32} person />
              <span class="name">{a.name}</span>
              {#if addingKey === a.mbid}
                <Spinner size={16} stroke={1.5} />
              {:else if added}
                <Button variant="text" small icon="album" style="color:#4caf50" onclick={() => openDiscography(a)}>Open</Button>
              {:else}
                <Button variant="text" small onclick={() => void addArtist(a)}>Add</Button>
              {/if}
            </div>
            {/snippet}
          </VirtualList>
        {/if}
      {:else if searching && albumResults === null}
        <div class="center"><Spinner size={28} /></div>
      {:else if !albumResults || albumResults.length === 0}
        <div class="center"><span class="muted">No results.</span></div>
      {:else}
        {@const list = albumResults}
        <VirtualList count={list.length} rowHeight={52}>
          {#snippet row(i)}
          {@const a = list[i]!}
          <div class="row">
            <LidarrCover url={a.coverUrl} size={36} />
            <span class="text">
              <span class="name">{a.title}</span>
              <span class="sub">{albumSubtitle(a)}</span>
            </span>
            {#if addingKey === a.foreignAlbumId}
              <Spinner size={16} stroke={1.5} />
            {:else if a.lidarrAlbumId > 0}
              <IconButton label="Auto search" icon="search" size={16} color="var(--color-text-secondary)" onclick={() => void searchExisting(a)} />
              <button class="icon-btn" title="Pick a release" aria-label="Pick a release" onclick={() => openReleases(a)}>
                <ExtraIcon name="manage_search" size={16} />
              </button>
            {:else}
              <button class="icon-btn accent" title="Options" aria-label="Options" onclick={(e) => void albumMenu(e, a)}>
                <ExtraIcon name="add_circle_outline" size={18} />
              </button>
            {/if}
          </div>
          {/snippet}
        </VirtualList>
      {/if}
    </div>
  </div>
  {#snippet footer()}
    <Button variant="text" onclick={onclose}>Close</Button>
  {/snippet}
</Dialog>

{#if discography}
  <DiscographyDialog artistId={discography.id} artistName={discography.name} onclose={() => (discography = null)} />
{/if}

{#if releasePicker}
  {@const rp = releasePicker}
  <ReleasePickerDialog
    albumId={rp.id}
    albumTitle={rp.title}
    onclose={() => {
      releasePicker = null;
      if (rp.closeAfter) onclose();
    }}
  />
{/if}

<style>
  .frame {
    display: flex;
    flex-direction: column;
    gap: 8px;
    height: 400px;
  }
  .subtitle {
    margin-top: -8px;
    font-size: 12px;
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .tabs {
    padding-top: 4px;
  }
  .body {
    --scroll-bottom-inset: 0px;
    flex: 1;
    min-height: 0;
    overflow: hidden;
    margin: 4px -22px 0;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .muted {
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 100%;
    padding: 4px 22px;
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .name {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    color: var(--color-text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .sub {
    font-size: 11px;
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .icon-btn {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    padding: 0;
    border: none;
    border-radius: 6px;
    background: none;
    color: var(--color-text-secondary);
  }
  .icon-btn.accent {
    color: var(--color-accent);
  }
  .icon-btn:hover {
    background: rgba(255, 255, 255, 0.08);
  }
</style>
