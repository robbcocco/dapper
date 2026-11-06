<script lang="ts">
  import type { HTMLButtonAttributes } from 'svelte/elements';
  import Icon from './Icon.svelte';
  import type { IconName } from './icons';

  let {
    icon,
    size = 18,
    label,
    active = false,
    color,
    ...rest
  }: HTMLButtonAttributes & {
    icon: IconName;
    size?: number;
    /** Tooltip + accessible name. */
    label: string;
    /** Accent-coloured (e.g. shuffle/repeat on). */
    active?: boolean;
    color?: string;
  } = $props();
</script>

<button type="button" class="ib" class:active title={label} aria-label={label} style:width="{size + 12}px" style:height="{size + 12}px" style:color={color} {...rest}>
  <Icon name={icon} {size} />
</button>

<style>
  .ib {
    display: inline-grid;
    place-items: center;
    flex: none;
    padding: 0;
    border: none;
    border-radius: 6px;
    background: transparent;
    color: var(--color-text-primary);
  }
  .ib:not(:disabled):hover {
    background: rgba(255, 255, 255, 0.08);
  }
  .ib:disabled {
    opacity: 0.35;
  }
  .ib:focus-visible {
    outline: 2px solid var(--color-accent);
  }
  .active {
    color: var(--color-accent);
  }
</style>
