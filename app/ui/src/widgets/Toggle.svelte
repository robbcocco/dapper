<script lang="ts">
  let {
    checked = $bindable(false),
    label,
    disabled = false,
    onchange,
  }: { checked?: boolean; label?: string; disabled?: boolean; onchange?: (v: boolean) => void } = $props();
</script>

<label class="tg" class:disabled>
  <input type="checkbox" role="switch" bind:checked {disabled} onchange={() => onchange?.(checked)} />
  <span class="track"><span class="thumb"></span></span>
  {#if label}<span>{label}</span>{/if}
</label>

<style>
  .tg {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }
  .disabled {
    opacity: 0.4;
  }
  input {
    position: absolute;
    opacity: 0;
    width: 0;
    height: 0;
  }
  .track {
    width: 32px;
    height: 18px;
    border-radius: 9px;
    background: var(--color-surface-variant);
    position: relative;
    transition: background 0.15s;
  }
  .thumb {
    position: absolute;
    top: 2px;
    left: 2px;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #fff;
    transition: transform 0.15s;
  }
  input:checked + .track {
    background: var(--color-accent);
  }
  input:checked + .track .thumb {
    transform: translateX(14px);
  }
  input:focus-visible + .track {
    outline: 2px solid var(--color-accent);
    outline-offset: 2px;
  }
</style>
