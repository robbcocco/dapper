<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';
  import Icon from './Icon.svelte';

  let {
    value = $bindable(''),
    search = false,
    label,
    error,
    input = $bindable(),
    onclear,
    ...rest
  }: Omit<HTMLInputAttributes, 'value'> & {
    value?: string;
    /** Search variant: magnifier prefix + clear button. */
    search?: boolean;
    label?: string;
    error?: string | null;
    input?: HTMLInputElement;
    onclear?: () => void;
  } = $props();

  function clear(): void {
    value = '';
    onclear?.();
    input?.focus();
  }
</script>

<label class="tf">
  {#if label}<span class="label">{label}</span>{/if}
  <span class="box" class:search class:invalid={!!error}>
    {#if search}<Icon name="search" size={14} />{/if}
    <input bind:this={input} bind:value spellcheck="false" autocomplete="off" {...rest} />
    {#if search && value}
      <button type="button" class="clear" aria-label="Clear" tabindex="-1" onclick={clear}><Icon name="cancel" size={14} /></button>
    {/if}
  </span>
  {#if error}<span class="error">{error}</span>{/if}
</label>

<style>
  .tf {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .label {
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .box {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 10px;
    border-radius: 7px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid var(--color-glass-border);
    color: var(--color-text-secondary);
  }
  .box:focus-within {
    border-color: var(--color-accent);
  }
  .search {
    border-radius: 15px;
    height: 28px;
  }
  .invalid {
    border-color: #ff453a;
  }
  input {
    flex: 1;
    min-width: 0;
    border: none;
    outline: none;
    background: transparent;
    font: inherit;
    color: var(--color-text-primary);
  }
  input::placeholder {
    color: var(--color-text-secondary);
  }
  .clear {
    display: grid;
    place-items: center;
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-secondary);
  }
  .error {
    font-size: 11px;
    color: #ff453a;
  }
</style>
