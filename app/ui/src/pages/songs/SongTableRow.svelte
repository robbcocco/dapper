<script lang="ts">
  import Icon from '../../widgets/Icon.svelte';
  import RatingStars from '../../widgets/RatingStars.svelte';
  import SyncDot from '../../widgets/SyncDot.svelte';
  import { fmtDuration } from '../../widgets/library/actions';
  import { ratings } from '../../widgets/library/ratings.svelte';
  import { libraryStatus } from '../../widgets/library/status.svelte';
  import type { Song } from '../../lib/types';
  import { player } from '../../lib/stores/player.svelte';
  import { starred } from '../../lib/stores/starred.svelte';

  /** songs_page.dart `_SongTableRow`; `song` null while its window is loading. */
  let {
    song,
    index,
    selected,
    onDevice,
    onclick,
    oncontextmenu,
  }: {
    song: Song | null;
    index: number;
    selected: boolean;
    onDevice: boolean;
    onclick: (e: MouseEvent) => void;
    oncontextmenu: (e: MouseEvent) => void;
  } = $props();

  const playing = $derived(song !== null && player.state.currentSong?.id === song.id);
  const q = $derived(song ? libraryStatus.songQueue(song.id) : null);
  const isStarred = $derived(song !== null && starred.has(song.id));
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div
  class="row"
  class:selected
  class:playing
  role="row"
  tabindex="-1"
  aria-selected={selected}
  {onclick}
  oncontextmenu={(e) => {
    e.preventDefault();
    if (song) oncontextmenu(e);
  }}
>
  {#if song}
    <span class="num">
      {#if playing}<Icon name="volume" size={13} color="var(--color-accent)" />{:else}{song.track ?? index + 1}{/if}
    </span>
    <span class="cell title">{song.title}</span>
    <span class="cell sec">{song.artist ?? ''}</span>
    <span class="cell sec">{song.album ?? ''}</span>
    <span class="year">{song.year ?? ''}</span>
    <span class="time">{song.duration != null ? fmtDuration(song.duration) : ''}</span>
    <span class="sync">
      {#if q && (q.active || q.queued)}
        <SyncDot state="queued" pulse={q.active} />
      {:else if onDevice}
        <SyncDot state="full" />
      {/if}
    </span>
    <span class="rating">
      <RatingStars compact size={11} rating={ratings.get(song.id, song.userRating)} onRate={(r) => void ratings.set(song.id, r)} />
    </span>
    <button
      type="button"
      class="star"
      aria-label={isStarred ? 'Unstar' : 'Star'}
      onclick={(e) => {
        e.stopPropagation();
        void starred.toggle(song.id);
      }}
    >
      <Icon name={isStarred ? 'star' : 'star_border'} size={13} color={isStarred ? '#ffc107' : 'rgba(142,142,147,0.35)'} />
    </button>
  {:else}
    <span class="num"></span>
    <span class="skeleton"></span>
  {/if}
</div>

<style>
  .row {
    height: 36px;
    display: flex;
    align-items: center;
    padding: 0 16px;
    border-bottom: 1px solid #2a2a2a;
    outline: none;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .playing {
    background: rgba(10, 132, 255, 0.08);
  }
  .selected {
    background: var(--color-selection-background);
  }
  .num {
    width: 40px;
    flex: none;
    display: flex;
    justify-content: flex-end;
    padding-right: 12px;
    font-variant-numeric: tabular-nums;
  }
  .cell {
    min-width: 0;
    padding-right: 12px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    flex: 3;
    font-size: 13px;
    color: var(--color-text-primary);
  }
  .playing .title {
    color: var(--color-accent);
  }
  .sec {
    flex: 2;
  }
  .year {
    width: 48px;
    flex: none;
    font-variant-numeric: tabular-nums;
  }
  .time {
    width: 55px;
    flex: none;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .sync {
    width: 20px;
    flex: none;
    display: flex;
    justify-content: center;
  }
  .rating {
    width: 76px;
    flex: none;
    display: flex;
    justify-content: center;
  }
  .star {
    width: 36px;
    flex: none;
    display: grid;
    place-items: center;
    border: none;
    background: none;
  }
  .skeleton {
    width: 30%;
    height: 10px;
    border-radius: 3px;
    background: rgba(255, 255, 255, 0.06);
  }
</style>
