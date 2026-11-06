<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon from './Icon.svelte';
  import type { IconName } from './icons';

  let { icon, title, message, children }: { icon?: IconName; title: string; message?: string; children?: Snippet } = $props();
</script>

<div class="es">
  {#if icon}<span class="icon"><Icon name={icon} size={40} /></span>{/if}
  <div class="title">{title}</div>
  {#if message}<div class="msg">{message}</div>{/if}
  {#if children}<div class="actions">{@render children()}</div>{/if}
</div>

<style>
  .es {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 24px;
    text-align: center;
    color: var(--color-text-secondary);
  }
  .icon {
    opacity: 0.6;
    margin-bottom: 12px;
  }
  .title {
    font-size: 15px;
    font-weight: 600;
    color: var(--color-text-primary);
  }
  .msg {
    margin-top: 6px;
    font-size: 12px;
    max-width: 420px;
  }
  .actions {
    margin-top: 16px;
    display: flex;
    gap: 8px;
  }
</style>
