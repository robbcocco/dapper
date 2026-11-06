<script lang="ts">
  import type { Snippet } from 'svelte';

  /** Bottom bar shell shown while rows are selected (selection_action_bar.dart); actions go in `children`. */
  let { count, onClear, children }: { count: number; onClear: () => void; children?: Snippet } = $props();
</script>

{#if count > 0}
  <div class="bar">
    <span class="count">{count} selected</span>
    {@render children?.()}
    <span class="spacer"></span>
    <button type="button" class="clear" onclick={onClear}>Clear</button>
  </div>
{/if}

<style>
  .bar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 16px;
    background: rgba(44, 44, 46, 0.96);
    border-top: 1px solid var(--color-glass-border);
    font-size: 12px;
  }
  .spacer {
    flex: 1;
  }
  .clear {
    border: none;
    background: none;
    font: inherit;
    color: var(--color-text-secondary);
  }
  .clear:hover {
    color: var(--color-text-primary);
  }
</style>
