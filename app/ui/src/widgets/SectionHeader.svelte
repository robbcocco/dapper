<script lang="ts">
  import type { Snippet } from 'svelte';

  /** Page/section title row with optional subtitle and trailing actions. */
  let { title, subtitle, large = false, actions }: { title: string; subtitle?: string; large?: boolean; actions?: Snippet } = $props();
</script>

<header class="sh" class:large>
  <div class="text">
    <h2>{title}</h2>
    {#if subtitle}<span class="sub">{subtitle}</span>{/if}
  </div>
  {#if actions}<div class="actions">{@render actions()}</div>{/if}
</header>

<style>
  .sh {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 24px 8px;
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: baseline;
    gap: 10px;
  }
  h2 {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .large {
    padding-top: 20px;
  }
  .large h2 {
    font-size: 22px;
    font-weight: 700;
  }
  .sub {
    font-size: 12px;
    color: var(--color-text-secondary);
    white-space: nowrap;
  }
  .actions {
    display: flex;
    align-items: center;
    gap: 6px;
  }
</style>
