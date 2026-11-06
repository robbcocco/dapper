<script lang="ts">
  import { untrack } from 'svelte';
  import Dialog from '../Dialog.svelte';
  import Button from '../Button.svelte';
  import CoverArt from '../CoverArt.svelte';
  import Icon from '../Icon.svelte';
  import IconButton from '../IconButton.svelte';
  import Spinner from '../Spinner.svelte';
  import TextField from '../TextField.svelte';
  import { confirm } from '../dialogs';
  import * as api from '../../lib/api';
  import { toAppError } from '../../lib/ipc';
  import type { Album, MbReleaseGroup } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';

  /** Port of album_info_dialog.dart: album metadata + MusicBrainz lookup to replace the cover art. */
  let { album, onresult }: { album: Album; onresult: (r: null) => void } = $props();

  const meta = $derived(
    [
      ['Title', album.name],
      ['Artist', album.artist],
      ['Year', album.year?.toString() ?? null],
      ['Genre', album.genre || null],
      ['Songs', String(album.songCount)],
      ['Duration', album.duration > 0 ? fmtLong(album.duration) : null],
    ].filter((r): r is [string, string] => r[1] != null),
  );

  function fmtLong(seconds: number): string {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  }

  const year = (r: MbReleaseGroup): string | null => (r.firstReleaseDate ? (r.firstReleaseDate.split('-')[0] ?? null) : null);
  const thumb = (r: MbReleaseGroup): string => `https://coverartarchive.org/release-group/${r.id}/front-250`;

  // The dialog is mounted per album, so the initial query is taken once.
  let albumQuery = $state(untrack(() => album.name));
  let artistQuery = $state(untrack(() => album.artist ?? ''));
  let results = $state<MbReleaseGroup[]>([]);
  let searching = $state(false);
  let searchError = $state<string | null>(null);
  let failedThumbs = $state<ReadonlySet<string>>(new Set());
  let applying = $state<string | null>(null);
  let seq = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;

  async function search(): Promise<void> {
    clearTimeout(timer);
    const a = albumQuery.trim();
    if (a === '' && artistQuery.trim() === '') return;
    const mine = ++seq;
    searching = true;
    searchError = null;
    results = [];
    try {
      const r = await api.mbSearchReleaseGroups(a, artistQuery.trim());
      if (mine === seq) results = r;
    } catch (e) {
      if (mine === seq) searchError = toAppError(e).message;
    } finally {
      if (mine === seq) searching = false;
    }
  }

  function onQueryInput(): void {
    clearTimeout(timer);
    timer = setTimeout(() => void search(), 600);
  }

  $effect(() => {
    untrack(() => void search());
    return () => clearTimeout(timer);
  });

  async function useCover(r: MbReleaseGroup): Promise<void> {
    if (applying !== null) return;
    const ok = await confirm({
      title: 'Replace cover art?',
      message: `Use the Cover Art Archive front cover of "${r.title}" for "${album.name}"?`,
      confirmLabel: 'Use Cover',
    });
    if (!ok) return;
    applying = r.id;
    try {
      await api.albumCoverFromReleaseGroup(album.id, r.id);
      toast('Cover art updated', { kind: 'success' });
    } catch (e) {
      toast(`Could not update cover art: ${toAppError(e).message}`, { kind: 'error' });
    } finally {
      applying = null;
    }
  }
</script>

<Dialog width={780} onclose={() => onresult(null)}>
  <div class="wrap">
    <div class="titlebar">
      <h2>Get Info</h2>
      <IconButton icon="close" size={16} label="Close" onclick={() => onresult(null)} />
    </div>
    <div class="content">
      <div class="info">
        <CoverArt coverArtId={album.coverArtId} size={360} radius={8} display="180px" />
        <div class="meta">
          {#each meta as [label, value] (label)}
            <div class="meta-row">
              <span class="label">{label}</span>
              <span class="value">{value}</span>
            </div>
          {/each}
        </div>
      </div>
      <div class="vdivider"></div>
      <div class="mb">
        <div class="caption">FIX VIA MUSICBRAINZ</div>
        <form
          class="query"
          onsubmit={(e) => {
            e.preventDefault();
            void search();
          }}
        >
          <TextField search placeholder="Album" bind:value={albumQuery} oninput={onQueryInput} onclear={onQueryInput} />
          <TextField placeholder="Artist" bind:value={artistQuery} oninput={onQueryInput} />
          <button type="submit" hidden aria-hidden="true"></button>
          {#if searching}<Spinner size={14} stroke={1.5} />{/if}
        </form>
        <div class="results">
          {#if searchError}
            <div class="empty">{searchError}</div>
          {:else if results.length === 0 && !searching}
            <div class="empty">No results</div>
          {:else}
            <div class="grid">
              {#each results as r (r.id)}
                <button type="button" class="card" title="Use this cover" disabled={applying !== null} onclick={() => void useCover(r)}>
                  <span class="thumb">
                    {#if failedThumbs.has(r.id)}
                      <Icon name="album" size={24} />
                    {:else}
                      <img
                        src={thumb(r)}
                        alt=""
                        loading="lazy"
                        draggable="false"
                        onerror={() => (failedThumbs = new Set([...failedThumbs, r.id]))}
                      />
                    {/if}
                    {#if applying === r.id}<span class="busy"><Spinner size={20} /></span>{/if}
                  </span>
                  <span class="card-text">
                    <span class="card-title">{r.title}</span>
                    {#if r.artistName}<span class="card-sub">{r.artistName}</span>{/if}
                    {#if year(r)}<span class="card-sub">{year(r)}</span>{/if}
                  </span>
                </button>
              {/each}
            </div>
          {/if}
        </div>
      </div>
    </div>
    <div class="bottom">
      <Icon name="info" size={12} />
      <span class="note">Click a MusicBrainz result to use its Cover Art Archive front cover for this album.</span>
      <Button variant="text" onclick={() => onresult(null)}>Close</Button>
    </div>
  </div>
</Dialog>

<style>
  .wrap {
    height: min(580px, calc(100vh - 96px));
    display: flex;
    flex-direction: column;
  }
  .titlebar {
    display: flex;
    align-items: center;
    margin-bottom: 16px;
  }
  h2 {
    flex: 1;
    margin: 0;
    font-size: 16px;
    font-weight: 700;
    color: var(--color-text-primary);
  }
  .content {
    flex: 1;
    min-height: 0;
    display: flex;
    gap: 20px;
  }
  .info {
    width: 180px;
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .meta-row {
    display: flex;
    padding-bottom: 6px;
  }
  .label {
    width: 56px;
    flex: none;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.4px;
  }
  .value {
    flex: 1;
    min-width: 0;
    font-size: 11px;
    color: var(--color-text-primary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .vdivider {
    width: 1px;
    background: var(--color-glass-border);
  }
  .mb {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .caption {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.6px;
    opacity: 0.7;
  }
  .query {
    display: grid;
    grid-template-columns: 3fr 2fr auto;
    gap: 8px;
    align-items: center;
  }
  .results {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    margin-top: 4px;
  }
  .empty {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
  }
  .card {
    display: flex;
    flex-direction: column;
    padding: 0;
    border: 1px solid var(--color-glass-border);
    border-radius: 8px;
    background: var(--color-surface-variant);
    font: inherit;
    text-align: left;
    overflow: hidden;
  }
  .card:hover:not(:disabled) {
    border-color: var(--color-accent);
  }
  .thumb {
    position: relative;
    aspect-ratio: 1;
    display: grid;
    place-items: center;
    color: var(--color-text-secondary);
  }
  .thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .busy {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.45);
  }
  .card-text {
    display: flex;
    flex-direction: column;
    padding: 8px;
  }
  .card-title {
    font-size: 11px;
    color: var(--color-text-primary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .card-sub {
    font-size: 10px;
    color: var(--color-text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .bottom {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 12px;
  }
  .note {
    flex: 1;
    font-size: 10px;
  }
</style>
