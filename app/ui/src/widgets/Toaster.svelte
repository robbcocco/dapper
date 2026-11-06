<script lang="ts">
  import { toasts, dismissToast } from '../lib/stores/toast.svelte';
</script>

<!-- Mount once in the shell; floats above the bottom bar like Flutter's floating SnackBar. -->
{#if toasts.current}
  {@const t = toasts.current}
  {#key t.id}
    <div class="toast {t.kind}" role="status" aria-live="polite">
      <span class="msg">{t.message}</span>
      {#if t.action}
        <button
          type="button"
          onclick={() => {
            t.action?.run();
            dismissToast();
          }}>{t.action.label}</button
        >
      {/if}
    </div>
  {/key}
{/if}

<style>
  .toast {
    position: fixed;
    left: 50%;
    bottom: calc(var(--bottom-bar-height) + var(--shell-margin) * 2 + 8px);
    transform: translateX(-50%);
    z-index: 1100;
    display: flex;
    align-items: center;
    gap: 16px;
    max-width: min(560px, calc(100vw - 48px));
    padding: 12px 16px;
    border-radius: 8px;
    background: #3a3a3c;
    border: 1px solid var(--color-glass-border);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    font-size: 13px;
    animation: in 0.18s ease-out;
  }
  .error {
    background: #5c1f1c;
  }
  .success {
    background: #1f4524;
  }
  .msg {
    flex: 1;
  }
  button {
    border: none;
    background: none;
    color: var(--color-accent);
    font: inherit;
    font-weight: 600;
  }
  @keyframes in {
    from {
      opacity: 0;
      transform: translate(-50%, 8px);
    }
  }
</style>
