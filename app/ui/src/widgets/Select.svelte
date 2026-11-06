<script lang="ts" generics="T extends string | number">
  let {
    value = $bindable(),
    options,
    label,
    disabled = false,
    onchange,
  }: {
    value: T;
    options: readonly { value: T; label: string }[];
    label?: string;
    disabled?: boolean;
    onchange?: (v: T) => void;
  } = $props();

  function pick(e: Event): void {
    const i = (e.currentTarget as HTMLSelectElement).selectedIndex;
    const opt = options[i];
    if (!opt) return;
    value = opt.value;
    onchange?.(opt.value);
  }
</script>

<label class="sel">
  {#if label}<span class="label">{label}</span>{/if}
  <select {disabled} onchange={pick}>
    {#each options as o (o.value)}
      <option value={String(o.value)} selected={o.value === value}>{o.label}</option>
    {/each}
  </select>
</label>

<style>
  .sel {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .label {
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  select {
    height: 28px;
    padding: 0 26px 0 10px;
    border-radius: 7px;
    border: 1px solid var(--color-glass-border);
    background: rgba(255, 255, 255, 0.06)
      url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='%238e8e93'%3E%3Cpath d='M16.59 8.59L12 13.17 7.41 8.59 6 10l6 6 6-6z'/%3E%3C/svg%3E")
      no-repeat right 6px center / 16px;
    appearance: none;
    font: inherit;
    color: var(--color-text-primary);
    outline: none;
  }
  select:focus-visible {
    border-color: var(--color-accent);
  }
  select:disabled {
    opacity: 0.4;
  }
</style>
