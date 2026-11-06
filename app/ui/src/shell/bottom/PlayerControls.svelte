<script lang="ts">
  import IconButton from '../../widgets/IconButton.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Slider from '../../widgets/Slider.svelte';
  import Glyph from './Glyph.svelte';
  import { player } from '../../lib/stores/player.svelte';

  const dim = 'color-mix(in srgb, var(--color-text-secondary) 60%, transparent)';

  const hasSong = $derived(player.state.currentSong !== null);
  const repeat = $derived(player.state.repeatMode);

  /** Seek fraction while the thumb is held; ticks don't yank it back mid-drag. */
  let drag = $state<number | null>(null);
  const total = $derived(player.durationMs);
  const progress = $derived(
    drag ?? (total <= 0 ? 0 : Math.min(Math.max(player.position.positionMs / total, 0), 1)),
  );
  const shownMs = $derived(drag === null ? player.position.positionMs : drag * total);

  function fmt(ms: number): string {
    const secs = Math.floor(Math.max(ms, 0) / 1000);
    return `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
  }
</script>

<div class="controls">
  <div class="transport">
    <IconButton
      icon="shuffle"
      size={16}
      label="Shuffle"
      active={player.state.isShuffled}
      color={player.state.isShuffled ? undefined : dim}
      onclick={player.toggleShuffle}
    />
    <IconButton
      icon="skip_previous"
      size={22}
      label="Previous"
      color="var(--color-text-secondary)"
      disabled={!player.hasPrevious}
      onclick={player.previous}
    />
    <button
      class="play"
      class:enabled={hasSong}
      disabled={!hasSong}
      title={player.state.isPlaying ? 'Pause' : 'Play'}
      aria-label={player.state.isPlaying ? 'Pause' : 'Play'}
      onclick={player.toggle}
    >
      {#if player.state.isBuffering}
        <Icon name="hourglass" size={34} />
      {:else}
        <Glyph name={player.state.isPlaying ? 'pause_circle' : 'play_circle'} size={34} />
      {/if}
    </button>
    <IconButton
      icon="skip_next"
      size={22}
      label="Next"
      color="var(--color-text-secondary)"
      disabled={!player.hasNext}
      onclick={player.next}
    />
    <IconButton
      icon={repeat === 'one' ? 'repeat_one' : 'repeat'}
      size={16}
      label={repeat === 'none' ? 'Repeat off' : repeat === 'all' ? 'Repeat all' : 'Repeat one'}
      active={repeat !== 'none'}
      color={repeat === 'none' ? dim : undefined}
      onclick={player.cycleRepeat}
    />
  </div>
  <div class="seek">
    <span class="time">{hasSong ? fmt(shownMs) : '0:00'}</span>
    <div class="track">
      <Slider
        value={progress}
        label="Seek"
        disabled={!hasSong}
        onChange={(v) => (drag = v)}
        onChangeEnd={(v) => {
          drag = null;
          player.seek(total * v);
        }}
      />
    </div>
    <span class="time">{hasSong ? fmt(total) : '0:00'}</span>
  </div>
</div>

<style>
  .controls {
    height: 100%;
    padding: 0 20px;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 2px;
  }
  .transport {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
  }
  .play {
    display: grid;
    place-items: center;
    padding: 0;
    border: none;
    background: none;
    color: color-mix(in srgb, var(--color-text-secondary) 30%, transparent);
  }
  .play.enabled {
    color: var(--color-text-primary);
  }
  .play:focus-visible {
    outline: 2px solid var(--color-accent);
    border-radius: 50%;
  }
  .seek {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .time {
    flex: none;
    font-size: 10px;
    color: var(--color-text-secondary);
    font-variant-numeric: tabular-nums;
  }
  .track {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    height: 16px;
  }
  /* Seek progress is accent-coloured (bottom_bar_widget.dart SliderTheme). */
  .track :global(input[type='range'])::-webkit-slider-runnable-track {
    background: linear-gradient(
      to right,
      var(--color-accent) var(--pct),
      var(--color-surface-variant) var(--pct)
    );
  }
  .track :global(input[type='range'])::-webkit-slider-thumb {
    background: var(--color-accent);
    opacity: 1;
  }
</style>
