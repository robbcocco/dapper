<script lang="ts">
  import { untrack } from 'svelte';
  import * as api from '../../lib/api';
  import type { Song, TrackMatch } from '../../lib/types';
  import { attempt } from '../../widgets/library/actions';
  import Button from '../../widgets/Button.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import ExtraIcon from '../../widgets/playlists/ExtraIcon.svelte';
  import CandidatePickerDialog from './CandidatePickerDialog.svelte';

  let { playlistName, truncated, matches }: { playlistName: string; truncated: boolean; matches: TrackMatch[] } = $props();

  let name = $state(untrack(() => playlistName));
  let picking = $state<number | null>(null);

  const matched = $derived(matches.filter((m) => m.selectedId !== null).length);
  const missing = $derived(matches.length - matched);
  const selectedSongs = $derived(
    matches.map((m) => (m.selectedId === null ? null : (m.candidates.find((c) => c.song.id === m.selectedId)?.song ?? null))),
  );

  function pick(index: number, song: Song | null): void {
    picking = null;
    void attempt(api.importSetSelection(index, song?.id ?? null, song));
  }

  function commit(): void {
    const n = name.trim();
    void attempt(api.importCommit(n === '' ? null : n));
  }
</script>

<div class="review">
  <input class="name" bind:value={name} aria-label="Playlist name" spellcheck="false" />
  <div class="stats">
    <span>{matched} of {matches.length} matched</span>
    {#if missing > 0}<span class="warn">{missing} need attention</span>{/if}
  </div>
  {#if truncated}
    <div class="banner">
      <Icon name="warning" size={14} />
      <span>Spotify only exposes the first ~100 tracks for this playlist — the rest are not visible without login.</span>
    </div>
  {/if}
  <div class="list">
    <VirtualList count={matches.length} rowHeight={56}>
      {#snippet row(i)}
        {@const m = matches[i]!}
        {@const sel = selectedSongs[i] ?? null}
        <button class="match" onclick={() => (picking = i)}>
          <span class="idx">{i + 1}</span>
          <span class="col">
            <span class="title">{m.source.title}</span>
            <span class="sub">{m.source.artist}</span>
          </span>
          <ExtraIcon name="arrow_forward" size={14} color="var(--color-text-secondary)" />
          <span class="col">
            {#if sel}
              <span class="title">{sel.title}</span>
              <span class="sub">{sel.artist ?? sel.albumArtist ?? ''}</span>
            {:else}
              <span class="title none">No match — tap to choose</span>
            {/if}
          </span>
          {#if sel}
            <Icon name="check_circle" size={16} color="#69f0ae" />
          {:else}
            <ExtraIcon name="error_outline" size={16} color="#ffab40" />
          {/if}
        </button>
      {/snippet}
    </VirtualList>
  </div>
  <div class="footer">
    <Button variant="text" onclick={() => void attempt(api.importReset())}>Cancel</Button>
    <Button variant="primary" icon="check" disabled={matched === 0} onclick={commit}>Create playlist ({matched})</Button>
  </div>
</div>

{#if picking !== null}
  {@const index = picking}
  <CandidatePickerDialog match={matches[index]!} onpick={(song) => pick(index, song)} onclose={() => (picking = null)} />
{/if}

<style>
  .review {
    display: flex;
    flex-direction: column;
    height: 100%;
  }
  .name {
    width: 100%;
    padding: 0;
    border: none;
    outline: none;
    background: transparent;
    font: inherit;
    font-size: 18px;
    font-weight: 700;
    color: var(--color-text-primary);
  }
  .stats {
    display: flex;
    gap: 12px;
    margin-top: 4px;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .warn {
    color: #ffab40;
  }
  .banner {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 8px;
    padding: 8px;
    border-radius: 6px;
    background: rgba(255, 152, 0, 0.12);
    color: #ffab40;
    font-size: 11px;
  }
  .list {
    flex: 1;
    min-height: 0;
    margin-top: 16px;
    --scroll-bottom-inset: 0px;
  }
  .match {
    display: flex;
    align-items: center;
    gap: 16px;
    width: 100%;
    height: 100%;
    padding: 0 8px;
    border: none;
    border-bottom: 0.5px solid var(--color-glass-border);
    background: transparent;
    font: inherit;
    text-align: left;
    color: inherit;
  }
  .match:hover {
    background: rgba(255, 255, 255, 0.03);
  }
  .idx {
    width: 24px;
    margin-right: -16px;
    flex: none;
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .col {
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
  .title.none {
    color: #ffab40;
    font-style: italic;
  }
  .sub {
    font-size: 11px;
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .footer {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--color-glass-border);
  }
</style>
