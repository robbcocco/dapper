<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';

  // Material visibility / visibility_off glyphs (not in the shared icon set).
  const EYE =
    'M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z';
  const EYE_OFF =
    'M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C10.74 7.13 11.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z';

  let {
    value = $bindable(''),
    label,
    error,
    ...rest
  }: Omit<HTMLInputAttributes, 'value' | 'type'> & { value?: string; label?: string; error?: string | null } = $props();

  let obscured = $state(true);
</script>

<label class="tf">
  {#if label}<span class="label">{label}</span>{/if}
  <span class="box" class:invalid={!!error}>
    <input type={obscured ? 'password' : 'text'} bind:value spellcheck="false" autocomplete="off" {...rest} />
    <button
      type="button"
      class="eye"
      tabindex="-1"
      aria-label={obscured ? 'Show' : 'Hide'}
      title={obscured ? 'Show' : 'Hide'}
      onclick={() => (obscured = !obscured)}
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d={obscured ? EYE_OFF : EYE} /></svg>
    </button>
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
    padding: 0 4px 0 10px;
    border-radius: 7px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid var(--color-glass-border);
    color: var(--color-text-secondary);
  }
  .box:focus-within {
    border-color: var(--color-accent);
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
  .eye {
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    padding: 0;
    border: none;
    border-radius: 5px;
    background: none;
    color: var(--color-text-secondary);
  }
  .eye:hover {
    background: rgba(255, 255, 255, 0.08);
  }
  .error {
    font-size: 11px;
    color: #ff453a;
  }
</style>
