<script lang="ts">
  import Icon from './Icon.svelte';

  /** 0–5 stars; clicking the current rating clears it to 0 (iTunes behaviour). */
  let {
    rating,
    onRate,
    size = 14,
    compact = false,
  }: { rating: number; onRate?: (rating: number) => void; size?: number; compact?: boolean } = $props();
</script>

<span class="rs" role="group" aria-label="Rating {rating} of 5">
  {#each [1, 2, 3, 4, 5] as star (star)}
    <button
      type="button"
      style:padding="0 {compact ? 1 : 2}px"
      aria-label="{star} star{star > 1 ? 's' : ''}"
      disabled={!onRate}
      onclick={(e) => {
        e.stopPropagation();
        onRate?.(star === rating ? 0 : star);
      }}
    >
      <Icon name={star <= rating ? 'star' : 'star_border'} {size} color={star <= rating ? '#ffc107' : 'rgba(142,142,147,0.4)'} />
    </button>
  {/each}
</span>

<style>
  .rs {
    display: inline-flex;
    align-items: center;
  }
  button {
    border: none;
    background: none;
    display: grid;
  }
  button:disabled {
    cursor: default;
  }
</style>
