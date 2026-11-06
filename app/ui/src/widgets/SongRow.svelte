<script lang="ts" module>
  export function formatDuration(s: number): string {
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { Song } from '../lib/types';
  import Icon from './Icon.svelte';

  /** Presentational port of song_row.dart. `song` null → loading placeholder (lazy windows). */
  let {
    song,
    index,
    showArtist = false,
    selected = false,
    playing = false,
    starred = false,
    onclick,
    ondblclick,
    oncontextmenu,
    onToggleStar,
    trailing,
  }: {
    song: Song | null;
    index?: number;
    showArtist?: boolean;
    selected?: boolean;
    playing?: boolean;
    starred?: boolean;
    onclick?: (e: MouseEvent) => void;
    ondblclick?: (e: MouseEvent) => void;
    oncontextmenu?: (e: MouseEvent) => void;
    onToggleStar?: () => void;
    trailing?: Snippet;
  } = $props();
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div
  class="row"
  class:selected
  class:playing
  style:height="{showArtist ? 48 : 40}px"
  role="row"
  tabindex="-1"
  aria-selected={selected}
  {onclick}
  {ondblclick}
  oncontextmenu={(e) => {
    if (!oncontextmenu) return;
    e.preventDefault();
    oncontextmenu(e);
  }}
>
  <span class="num">
    {#if playing}<Icon name="volume" size={14} color="var(--color-accent)" />{:else}{index != null ? index + 1 : (song?.track ?? '·')}{/if}
  </span>
  <span class="main">
    {#if song}
      <span class="title">{song.title}</span>
      {#if showArtist && song.artist}<span class="artist">{song.artist}</span>{/if}
    {:else}
      <span class="skeleton"></span>
    {/if}
  </span>
  {#if song}
    <button
      type="button"
      class="star"
      aria-label={starred ? 'Unstar' : 'Star'}
      onclick={(e) => {
        e.stopPropagation();
        onToggleStar?.();
      }}
    >
      <Icon name={starred ? 'star' : 'star_border'} size={14} color={starred ? '#ffc107' : 'rgba(142,142,147,0.4)'} />
    </button>
    {@render trailing?.()}
    {#if song.duration != null}<span class="dur">{formatDuration(song.duration)}</span>{/if}
  {/if}
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    padding: 0 24px;
    border-bottom: 1px solid #2a2a2a;
    outline: none;
  }
  .playing {
    background: rgba(10, 132, 255, 0.08);
  }
  .selected {
    background: var(--color-selection-background);
  }
  .num {
    width: 28px;
    flex: none;
    display: flex;
    justify-content: flex-end;
    font-size: 12px;
    color: var(--color-text-secondary);
    font-variant-numeric: tabular-nums;
  }
  .main {
    flex: 1;
    min-width: 0;
    margin-left: 16px;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .title,
  .artist {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-size: 13px;
  }
  .playing .title {
    color: var(--color-accent);
  }
  .artist {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .skeleton {
    width: 40%;
    height: 10px;
    border-radius: 3px;
    background: rgba(255, 255, 255, 0.06);
  }
  .star {
    border: none;
    background: none;
    padding: 0 6px;
    display: grid;
  }
  .dur {
    font-size: 12px;
    color: var(--color-text-secondary);
    font-variant-numeric: tabular-nums;
  }
</style>
