<script lang="ts">
  import * as api from '../../lib/api';
  import type { Song, TrackMatch } from '../../lib/types';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import ExtraIcon from '../../widgets/playlists/ExtraIcon.svelte';
  import LidarrLookupDialog from './LidarrLookupDialog.svelte';
  import { selectedLidarrInstance } from './lidarr';

  /** `onpick(song)` with a song to select it, `null` to skip the track; `onclose` cancels. */
  let { match, onpick, onclose }: { match: TrackMatch; onpick: (song: Song | null) => void; onclose: () => void } = $props();

  let query = $state('');
  let manualResults = $state<Song[] | null>(null);
  let searching = $state(false);
  let lidarrReady = $state(false);
  let lidarrOpen = $state(false);
  let timer: ReturnType<typeof setTimeout> | undefined;
  let seq = 0;

  $effect(() => {
    void selectedLidarrInstance().then((i) => (lidarrReady = i !== null));
    return () => clearTimeout(timer);
  });

  const visible = $derived(manualResults ?? match.candidates.map((c) => c.song));
  const scores = $derived(new Map(match.candidates.map((c) => [c.song.id, c.score])));

  async function search(v: string): Promise<void> {
    const q = v.trim();
    const my = ++seq;
    if (q === '') {
      manualResults = null;
      searching = false;
      return;
    }
    searching = true;
    try {
      const r = await api.importManualSearch(q);
      if (my === seq) manualResults = r;
    } catch {
      if (my === seq) manualResults = [];
    } finally {
      if (my === seq) searching = false;
    }
  }

  function onQuery(v: string): void {
    clearTimeout(timer);
    timer = setTimeout(() => void search(v), 350);
  }
</script>

<Dialog title="Pick a match" width={520} {onclose}>
  <div class="frame">
    <div class="subtitle">{match.source.artist} — {match.source.title}</div>
    <TextField search bind:value={query} placeholder="Search the library…" oninput={(e) => onQuery(e.currentTarget.value)} onclear={() => onQuery('')} />
    <div class="body">
      {#if searching}
        <div class="center"><Spinner size={28} /></div>
      {:else if visible.length === 0}
        <div class="center"><span class="muted">No candidates found.</span></div>
      {:else}
        <VirtualList count={visible.length} rowHeight={52}>
          {#snippet row(i)}
            {@const song = visible[i]!}
            {@const score = scores.get(song.id)}
            {@const current = match.selectedId === song.id}
            <button class="cand" class:current onclick={() => onpick(song)}>
              <span class="text">
                <span class="title">{song.title}</span>
                <span class="sub">{song.artist ?? ''} · {song.album ?? ''}</span>
              </span>
              {#if score !== undefined}<span class="score">{(score * 100).toFixed(0)}%</span>{/if}
              {#if current}<Icon name="check" size={14} color="var(--color-accent)" />{/if}
            </button>
          {/snippet}
        </VirtualList>
      {/if}
    </div>
  </div>
  {#snippet footer()}
    <Button variant="text" style="color:var(--color-text-secondary)" onclick={() => onpick(null)}>
      <ExtraIcon name="block" size={14} />Skip
    </Button>
    <Button variant="text" icon="cloud_download" disabled={!lidarrReady} onclick={() => (lidarrOpen = true)}>Find on Lidarr</Button>
    <span class="spacer"></span>
    <Button variant="text" onclick={onclose}>Cancel</Button>
  {/snippet}
</Dialog>

{#if lidarrOpen}
  <LidarrLookupDialog track={match.source} onclose={() => (lidarrOpen = false)} />
{/if}

<style>
  .frame {
    display: flex;
    flex-direction: column;
    gap: 12px;
    height: 360px;
  }
  .subtitle {
    margin-top: -8px;
    font-size: 12px;
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .body {
    --scroll-bottom-inset: 0px;
    flex: 1;
    min-height: 0;
    overflow: hidden;
    margin: 0 -22px;
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
  .cand {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    height: 100%;
    padding: 0 22px;
    border: none;
    background: transparent;
    font: inherit;
    text-align: left;
    color: inherit;
  }
  .cand:hover {
    background: rgba(255, 255, 255, 0.04);
  }
  .cand.current {
    background: var(--color-selection-background);
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .title {
    font-size: 13px;
    color: var(--color-text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .sub,
  .score {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .sub {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .spacer {
    flex: 1;
  }
</style>
