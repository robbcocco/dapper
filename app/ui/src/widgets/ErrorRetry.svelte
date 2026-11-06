<script lang="ts">
  import Icon from './Icon.svelte';
  import type { IconName } from './icons';
  import { IpcError, toAppError } from '../lib/ipc';

  let { error, onRetry, compact = false }: { error: unknown; onRetry: () => unknown; compact?: boolean } = $props();

  /** Maps the IPC AppError kind to icon/title/detail (error_retry.dart `_classify`). */
  function classify(e: unknown): [IconName, string, string | null] {
    const err = e instanceof IpcError ? e.error : toAppError(e);
    switch (err.kind) {
      case 'auth':
        return ['lock', 'Sign-in failed', 'Your saved password no longer works. Update it in Settings.'];
      case 'subsonic':
        return ['warning', 'Server returned an error', err.message];
      case 'network':
        return /timed? ?out/i.test(err.message)
          ? ['cloud_off', 'Timed out', "The server didn't respond in time. Try again or check the server."]
          : ['cloud_off', "Can't reach the server", 'Check your connection or the server URL, then try again.'];
      default:
        return ['error', 'Something went wrong', err.message];
    }
  }

  const [icon, title, detail] = $derived(classify(error));
</script>

<div class="er" class:compact>
  <span class="icon"><Icon name={icon} size={compact ? 28 : 40} /></span>
  <div class="title">{title}</div>
  {#if detail}<div class="detail">{detail}</div>{/if}
  <button type="button" onclick={() => void onRetry()}>Retry</button>
</div>

<style>
  .er {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 24px;
    text-align: center;
  }
  .icon {
    color: var(--color-text-secondary);
    opacity: 0.7;
    margin-bottom: 14px;
  }
  .compact .icon {
    margin-bottom: 8px;
  }
  .title {
    font-size: 15px;
    font-weight: 600;
  }
  .compact .title {
    font-size: 13px;
  }
  .detail {
    margin-top: 6px;
    font-size: 12px;
    color: var(--color-text-secondary);
    max-width: 420px;
  }
  .compact .detail {
    font-size: 11px;
  }
  button {
    margin-top: 18px;
    padding: 12px 22px;
    border: none;
    border-radius: 8px;
    background: var(--color-surface-variant);
    color: var(--color-text-primary);
    font: inherit;
  }
  .compact button {
    margin-top: 12px;
    padding: 8px 16px;
  }
  button:hover {
    filter: brightness(1.15);
  }
</style>
