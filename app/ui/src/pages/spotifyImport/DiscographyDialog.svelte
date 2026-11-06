<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrAlbum } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import ExtraIcon from '../../widgets/playlists/ExtraIcon.svelte';
  import LidarrCover from './LidarrCover.svelte';
  import ReleasePickerDialog from './ReleasePickerDialog.svelte';
  import { albumTypeLabel, albumTypeOrder, errMsg, releaseYear } from './lidarr';

  /**
   * Mini Lidarr artist page: every album Lidarr knows for the artist with per-album
   * auto-search and interactive grab, without leaving the import flow.
   */
  let { artistId, artistName, onclose }: { artistId: number; artistName: string; onclose: () => void } = $props();

  let albums = $state<LidarrAlbum[] | null>(null);
  let error = $state<string | null>(null);
  let reload = $state(0);
  let searching = $state<ReadonlySet<number>>(new Set());
  let searched = $state<ReadonlySet<number>>(new Set());
  let picker = $state<{ id: number; title: string } | null>(null);

  $effect(() => {
    void reload;
    let stale = false;
    albums = null;
    error = null;
    api
      .lidarrArtistAlbums(artistId)
      .then((a) => {
        if (!stale) albums = a;
      })
      .catch((e: unknown) => {
        if (!stale) error = errMsg(e);
      });
    return () => (stale = true);
  });

  // Group by type, missing-first within a group, then newest first; flattened with
  // group headers so the list can be virtualized at a fixed row height.
  type Row = { kind: 'header'; label: string } | { kind: 'album'; album: LidarrAlbum };
  const rows = $derived.by(() => {
    const out: Row[] = [];
    for (const t of albumTypeOrder) {
      const g = (albums ?? [])
        .filter((a) => a.albumType === t)
        .sort((a, b) =>
          a.hasFile !== b.hasFile ? (a.hasFile ? 1 : -1) : (releaseYear(b.releaseDate) ?? 0) - (releaseYear(a.releaseDate) ?? 0),
        );
      if (g.length === 0) continue;
      out.push({ kind: 'header', label: `${albumTypeLabel[t]} · ${g.length}` });
      for (const album of g) out.push({ kind: 'album', album });
    }
    return out;
  });

  async function autoSearch(id: number): Promise<void> {
    searching = new Set([...searching, id]);
    try {
      await api.lidarrSearchAlbum(id);
      searched = new Set([...searched, id]);
    } catch (e) {
      toast(`Search failed: ${errMsg(e)}`, { kind: 'error' });
    } finally {
      searching = new Set([...searching].filter((x) => x !== id));
    }
  }
</script>

<Dialog width={580} {onclose}>
  <div class="frame">
    <div class="head">
      <Icon name="person" size={18} color="var(--color-text-secondary)" />
      <span class="title">{artistName}</span>
      <IconButton label="Refresh" icon="refresh" size={16} color="var(--color-text-secondary)" onclick={() => reload++} />
    </div>
    <div class="body">
      {#if error !== null}
        <div class="center"><span class="err">Could not load discography: {error}</span></div>
      {:else if albums === null}
        <div class="center"><Spinner size={28} /></div>
      {:else if albums.length === 0}
        <div class="center"><span class="muted">No albums known for this artist yet.</span></div>
      {:else}
        <VirtualList count={rows.length} rowHeight={52}>
          {#snippet row(i)}
            {@const r = rows[i]!}
            {#if r.kind === 'header'}
              <div class="group">{r.label}</div>
            {:else}
              {@const album = r.album}
              {@const year = releaseYear(album.releaseDate)}
              <div class="row">
                <LidarrCover url={album.coverUrl} size={40} />
                <div class="main">
                  <div class="atitle">{album.title}</div>
                  <div class="sub">
                    {#if year !== null}<span class="year">{year}</span>{/if}
                    <span class="pill" class:ok={album.hasFile}>{album.hasFile ? 'Downloaded' : 'Missing'}</span>
                    {#if !album.monitored}<span class="pill grey">Unmonitored</span>{/if}
                  </div>
                </div>
                {#if !album.hasFile}
                  <span class="slot">
                    {#if searched.has(album.id)}
                      <ExtraIcon name="check_circle_outline" size={16} color="#4caf50" />
                    {:else if searching.has(album.id)}
                      <Spinner size={16} stroke={1.5} />
                    {:else}
                      <IconButton label="Auto search" icon="search" size={16} color="var(--color-text-secondary)" onclick={() => void autoSearch(album.id)} />
                    {/if}
                  </span>
                {/if}
                <span class="slot">
                  <button class="pick" title="Pick a release" aria-label="Pick a release" onclick={() => (picker = { id: album.id, title: album.title })}>
                    <ExtraIcon name="manage_search" size={16} />
                  </button>
                </span>
              </div>
            {/if}
          {/snippet}
        </VirtualList>
      {/if}
    </div>
  </div>
  {#snippet footer()}
    <Button variant="text" onclick={onclose}>Close</Button>
  {/snippet}
</Dialog>

{#if picker}
  <ReleasePickerDialog albumId={picker.id} albumTitle={picker.title} onclose={() => (picker = null)} />
{/if}

<style>
  .frame {
    display: flex;
    flex-direction: column;
    height: 470px;
    margin: -4px -22px 0;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 12px 8px 22px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 16px;
    font-weight: 700;
    color: var(--color-text-primary);
  }
  .body {
    --scroll-bottom-inset: 0px;
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
    padding: 24px;
    text-align: center;
  }
  .err {
    font-size: 12px;
    color: #ff5252;
  }
  .muted {
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .group {
    display: flex;
    align-items: flex-end;
    height: 100%;
    padding: 0 22px 6px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.5px;
    color: var(--color-text-secondary);
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 100%;
    padding: 6px 22px;
  }
  .main {
    flex: 1;
    min-width: 0;
  }
  .atitle {
    font-size: 13px;
    color: var(--color-text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .sub {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 2px;
  }
  .year {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .pill {
    padding: 1px 5px;
    border-radius: 6px;
    font-size: 10px;
    color: #ff9800;
    background: rgba(255, 152, 0, 0.12);
  }
  .pill.ok {
    color: #4caf50;
    background: rgba(76, 175, 80, 0.12);
  }
  .pill.grey {
    margin-left: -2px;
    color: var(--color-text-secondary);
    background: rgba(142, 142, 147, 0.1);
  }
  .slot {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
  }
  .pick {
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
  .pick:hover {
    background: rgba(255, 255, 255, 0.08);
  }
</style>
