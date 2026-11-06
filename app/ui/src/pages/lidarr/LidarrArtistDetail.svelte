<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrAlbum, LidarrArtist } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import ProgressBar from '../../widgets/ProgressBar.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { errorOf } from '../settings/connection';
  import LidarrError from './LidarrError.svelte';
  import LidarrImage from './LidarrImage.svelte';
  import { showInteractiveSearch } from './interactiveSearch.svelte';
  import { albumTypeLabel, albumTypeOrder, releaseYear } from './lidarr-filters';

  /** Lidarr-only artist detail + discography (_LidarrOnlyDetailPanel). Keyed per artist by the page. */
  let { artist }: { artist: LidarrArtist } = $props();

  type Row =
    | { kind: 'title'; count: number }
    | { kind: 'section'; label: string; count: number }
    | { kind: 'album'; album: LidarrAlbum; year: number | null };

  type Albums = { status: 'loading' } | { status: 'error' } | { status: 'ok'; items: LidarrAlbum[] };

  let searching = $state(false);
  let searched = $state(false);
  let albums = $state<Albums>({ status: 'loading' });
  let albumSearching = $state(new Set<number>());
  let albumSearched = $state(new Set<number>());

  async function loadAlbums(): Promise<void> {
    albums = { status: 'loading' };
    try {
      albums = { status: 'ok', items: await api.lidarrArtistAlbums(artist.id) };
    } catch {
      albums = { status: 'error' };
    }
  }

  $effect(() => {
    void loadAlbums();
  });

  /** Grouped by type in display order; downloaded first, then newest first. */
  const rows = $derived.by((): Row[] => {
    if (albums.status !== 'ok' || albums.items.length === 0) return [];
    const out: Row[] = [{ kind: 'title', count: albums.items.length }];
    for (const type of albumTypeOrder) {
      const group = albums.items
        .filter((a) => a.albumType === type)
        .map((album) => ({ kind: 'album' as const, album, year: releaseYear(album.releaseDate) }))
        .sort((a, b) => {
          if (a.album.hasFile !== b.album.hasFile) return a.album.hasFile ? -1 : 1;
          return (b.year ?? 0) - (a.year ?? 0);
        });
      if (group.length === 0) continue;
      out.push({ kind: 'section', label: albumTypeLabel[type], count: group.length }, ...group);
    }
    return out;
  });

  async function searchArtist(): Promise<void> {
    searching = true;
    try {
      await api.lidarrSearchArtist(artist.id);
      searched = true;
    } catch (e) {
      toast(`Search failed: ${errorOf(e).message}`, { kind: 'error' });
    } finally {
      searching = false;
    }
  }

  async function searchAlbum(id: number): Promise<void> {
    albumSearching = new Set(albumSearching).add(id);
    try {
      await api.lidarrSearchAlbum(id);
      albumSearched = new Set(albumSearched).add(id);
    } catch (e) {
      toast(`Search failed: ${errorOf(e).message}`, { kind: 'error' });
    } finally {
      const next = new Set(albumSearching);
      next.delete(id);
      albumSearching = next;
    }
  }
</script>

{#snippet header()}
  <div class="hero">
    <LidarrImage url={artist.posterUrl} size={88} radius={10} icon="person" iconSize={36} />
    <div class="info">
      <h1>{artist.name}</h1>
      <div class="badges">
        <span class="badge" class:green={artist.monitored}>{artist.monitored ? 'Monitored' : 'Unmonitored'}</span>
        {#if artist.status !== null}<span class="badge">{artist.status}</span>{/if}
        <span class="badge accent">Not in library</span>
      </div>
      {#if searched}
        <div class="queued"><Icon name="check_circle" size={14} />Search queued in Lidarr</div>
      {:else}
        <button type="button" class="search-btn" disabled={searching} onclick={() => void searchArtist()}>
          {#if searching}<Spinner size={14} stroke={1.5} />{:else}<Icon name="search" size={15} />{/if}
          Search Missing Albums
        </button>
      {/if}
    </div>
  </div>
  <div class="divider"></div>
  {#if artist.overview !== null}
    <p class="overview">{artist.overview}</p>
  {/if}
  {#if albums.status === 'loading'}
    <div class="pad"><ProgressBar /></div>
  {:else if albums.status === 'error'}
    <div class="pad">
      <LidarrError compact message="Could not load this artist's discography." onretry={() => void loadAlbums()} />
    </div>
  {/if}
{/snippet}

<div class="detail">
  <VirtualList count={rows.length} rowHeight={50} {header}>
    {#snippet row(i)}
      {@const r = rows[i]!}
      {#if r.kind === 'title'}
        <div class="disc-title">Discography in Lidarr ({r.count})</div>
      {:else if r.kind === 'section'}
        <div class="section">
          <span class="slabel">{r.label}</span>
          <span class="scount">{r.count}</span>
          <span class="sline"></span>
        </div>
      {:else}
        {@const a = r.album}
        <div class="album">
          <LidarrImage url={a.coverUrl} size={40} radius={4} icon="album" iconSize={20} />
          <div class="atext">
            <div class="atitle" title={a.title}>{a.title}</div>
            <div class="ameta">
              {#if r.year !== null}<span>{r.year} · </span>{/if}
              <span class="pill" class:has={a.hasFile}>{a.hasFile ? 'Downloaded' : 'Missing'}</span>
              {#if !a.monitored}<span class="pill muted">Unmonitored</span>{/if}
            </div>
          </div>
          {#if !a.hasFile}
            <span class="slot">
              {#if albumSearched.has(a.id)}
                <Icon name="check_circle" size={16} color="#4caf50" />
              {:else if albumSearching.has(a.id)}
                <Spinner size={16} stroke={1.5} />
              {:else}
                <IconButton icon="search" size={16} label="Auto search" color="var(--color-text-secondary)" onclick={() => void searchAlbum(a.id)} />
              {/if}
            </span>
          {/if}
          <span class="slot">
            <IconButton
              icon="list"
              size={16}
              label="Interactive search"
              color="var(--color-text-secondary)"
              onclick={() => showInteractiveSearch(a.id, a.title)}
            />
          </span>
        </div>
      {/if}
    {/snippet}
  </VirtualList>
</div>

<style>
  .detail {
    height: 100%;
  }
  .hero {
    display: flex;
    align-items: flex-start;
    gap: 20px;
    padding: 28px 28px 20px;
  }
  .info {
    flex: 1;
    min-width: 0;
  }
  h1 {
    margin: 0 0 6px;
    font-size: 26px;
    font-weight: 700;
    user-select: text;
    -webkit-user-select: text;
  }
  .badges {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 8px;
    margin-bottom: 14px;
  }
  .badge {
    padding: 3px 8px;
    border-radius: 10px;
    font-size: 11px;
    color: var(--color-text-secondary);
    background: rgba(142, 142, 147, 0.12);
    border: 1px solid rgba(142, 142, 147, 0.3);
  }
  .badge.green {
    color: #4caf50;
    background: rgba(76, 175, 80, 0.12);
    border-color: rgba(76, 175, 80, 0.3);
  }
  .badge.accent {
    color: var(--color-accent);
    background: rgba(10, 132, 255, 0.12);
    border-color: rgba(10, 132, 255, 0.3);
  }
  .queued {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    color: #4caf50;
  }
  .search-btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 32px;
    padding: 0 14px;
    border: none;
    border-radius: 8px;
    background: var(--color-accent);
    color: #fff;
    font: inherit;
    font-size: 12px;
  }
  .search-btn:not(:disabled):hover {
    filter: brightness(1.15);
  }
  .search-btn:disabled {
    opacity: 0.6;
  }
  .search-btn :global(svg) {
    color: #fff;
  }
  .divider {
    height: 1px;
    background: var(--color-divider);
  }
  .overview {
    margin: 0;
    padding: 20px 28px 4px;
    font-size: 13px;
    line-height: 1.6;
    color: var(--color-text-secondary);
    white-space: pre-line;
    user-select: text;
    -webkit-user-select: text;
  }
  .pad {
    padding: 20px 28px 0;
  }
  .disc-title {
    height: 100%;
    margin: 0 28px;
    display: flex;
    align-items: flex-end;
    padding-bottom: 4px;
    border-top: 1px solid var(--color-glass-border);
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.4px;
    color: var(--color-text-secondary);
  }
  .section {
    height: 100%;
    display: flex;
    align-items: flex-end;
    gap: 6px;
    padding: 0 28px 10px;
  }
  .slabel {
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.5px;
    color: var(--color-text-secondary);
  }
  .scount {
    font-size: 11px;
    color: rgba(142, 142, 147, 0.55);
  }
  .sline {
    flex: 1;
    margin: 0 0 6px 4px;
    height: 1px;
    background: var(--color-glass-border);
  }
  .album {
    height: 40px;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 28px;
  }
  .atext {
    flex: 1;
    min-width: 0;
  }
  .atitle {
    font-size: 13px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .ameta {
    margin-top: 2px;
    display: flex;
    align-items: center;
    gap: 4px;
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
  .pill.has {
    color: #4caf50;
    background: rgba(76, 175, 80, 0.12);
  }
  .pill.muted {
    color: var(--color-text-secondary);
    background: rgba(142, 142, 147, 0.1);
  }
  .slot {
    width: 28px;
    height: 28px;
    display: grid;
    place-items: center;
    flex: none;
  }
</style>
