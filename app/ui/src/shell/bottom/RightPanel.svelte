<script lang="ts">
  import Icon from '../../widgets/Icon.svelte';
  import Slider from '../../widgets/Slider.svelte';
  import Glyph from './Glyph.svelte';
  import TransferButton from '../TransferButton.svelte';
  import { player } from '../../lib/stores/player.svelte';

  const volume = $derived(player.state.volume);
</script>

<div class="right">
  <span class="vol-icon">
    {#if volume === 0}
      <Icon name="volume_off" size={14} />
    {:else if volume < 0.5}
      <Glyph name="volume_down" size={14} />
    {:else}
      <Icon name="volume" size={14} />
    {/if}
  </span>
  <div class="volume">
    <Slider value={volume} label="Volume" onChange={player.setVolume} />
  </div>
  <TransferButton />
</div>

<style>
  .right {
    height: 100%;
    padding: 0 12px;
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .vol-icon {
    flex: none;
    color: color-mix(in srgb, var(--color-text-secondary) 70%, transparent);
  }
  .volume {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    padding: 0 4px;
  }
  .volume :global(input[type='range'])::-webkit-slider-runnable-track {
    background: linear-gradient(
      to right,
      var(--color-text-secondary) var(--pct),
      var(--color-surface-variant) var(--pct)
    );
  }
  .volume :global(input[type='range'])::-webkit-slider-thumb {
    background: var(--color-text-secondary);
    opacity: 1;
    width: 8px;
    height: 8px;
    margin-top: -3px;
  }
</style>
