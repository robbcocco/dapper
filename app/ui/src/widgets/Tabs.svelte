<script lang="ts" generics="T extends string">
  let {
    value = $bindable(),
    tabs,
    onchange,
  }: { value: T; tabs: readonly { value: T; label: string; badge?: number }[]; onchange?: (v: T) => void } = $props();
</script>

<div class="tabs" role="tablist">
  {#each tabs as t (t.value)}
    <button
      type="button"
      role="tab"
      aria-selected={t.value === value}
      class:sel={t.value === value}
      onclick={() => {
        value = t.value;
        onchange?.(t.value);
      }}
    >
      {t.label}{#if t.badge}<span class="badge">{t.badge}</span>{/if}
    </button>
  {/each}
</div>

<style>
  .tabs {
    display: inline-flex;
    padding: 2px;
    gap: 2px;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.06);
  }
  button {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 24px;
    padding: 0 12px;
    border: none;
    border-radius: 6px;
    background: transparent;
    font: inherit;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  button:hover {
    color: var(--color-text-primary);
  }
  .sel {
    background: var(--color-surface-variant);
    color: var(--color-text-primary);
  }
  .badge {
    min-width: 16px;
    padding: 0 4px;
    border-radius: 8px;
    background: var(--color-accent);
    color: #fff;
    font-size: 10px;
    line-height: 16px;
  }
</style>
