<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';
  import Icon from './Icon.svelte';
  import type { IconName } from './icons';

  let {
    variant = 'secondary',
    icon,
    small = false,
    children,
    ...rest
  }: HTMLButtonAttributes & {
    variant?: 'primary' | 'secondary' | 'destructive' | 'text';
    icon?: IconName;
    small?: boolean;
    children?: Snippet;
  } = $props();
</script>

<button type="button" class="btn {variant}" class:small {...rest}>
  {#if icon}<Icon name={icon} size={small ? 13 : 15} />{/if}
  {@render children?.()}
</button>

<style>
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    height: 30px;
    padding: 0 14px;
    border-radius: 8px;
    border: none;
    font: inherit;
    font-size: 13px;
    font-weight: 500;
    color: var(--color-text-primary);
    background: var(--color-surface-variant);
    white-space: nowrap;
  }
  .small {
    height: 24px;
    padding: 0 10px;
    font-size: 12px;
  }
  .btn:not(:disabled):hover {
    filter: brightness(1.15);
  }
  .btn:disabled {
    opacity: 0.4;
  }
  .btn:focus-visible {
    outline: 2px solid var(--color-accent);
    outline-offset: 1px;
  }
  .primary {
    background: var(--color-accent);
  }
  .destructive {
    background: #d9382f;
  }
  .text {
    background: transparent;
    color: var(--color-accent);
    padding: 0 8px;
  }
  .text:not(:disabled):hover {
    background: rgba(255, 255, 255, 0.06);
    filter: none;
  }
</style>
