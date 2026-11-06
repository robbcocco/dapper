<script lang="ts">
  import type { Snippet } from 'svelte';
  import { portal } from '../lib/portal';

  let {
    open = $bindable(true),
    title,
    width = 420,
    onclose,
    dismissible = true,
    children,
    footer,
  }: {
    open?: boolean;
    title?: string;
    width?: number;
    /** Called after Esc / backdrop / explicit close. */
    onclose?: () => void;
    /** Esc and backdrop clicks close when true (barrierDismissible). */
    dismissible?: boolean;
    children?: Snippet;
    footer?: Snippet;
  } = $props();

  let panel = $state<HTMLDivElement>();
  let restore: Element | null = null;

  function close(): void {
    open = false;
    onclose?.();
  }

  const FOCUSABLE = 'button:not([disabled]),[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

  $effect(() => {
    if (!open || !panel) return;
    restore = document.activeElement;
    const first = panel.querySelector<HTMLElement>('[autofocus]') ?? panel.querySelector<HTMLElement>(FOCUSABLE) ?? panel;
    first.focus();
    return () => {
      if (restore instanceof HTMLElement) restore.focus();
    };
  });

  function onkeydown(e: KeyboardEvent): void {
    // Keep app shortcuts (space/arrows/⌘A) from firing behind the modal.
    e.stopPropagation();
    if (e.key === 'Escape') {
      e.preventDefault();
      if (dismissible) close();
      return;
    }
    if (e.key !== 'Tab' || !panel) return;
    const items = [...panel.querySelectorAll<HTMLElement>(FOCUSABLE)];
    if (items.length === 0) {
      e.preventDefault();
      return;
    }
    const first = items[0]!;
    const last = items[items.length - 1]!;
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
  <div class="backdrop" use:portal onclick={(e) => dismissible && e.target === e.currentTarget && close()} {onkeydown}>
    <div class="panel" bind:this={panel} role="dialog" aria-modal="true" aria-label={title} tabindex="-1" style:width="{width}px">
      {#if title}<h2>{title}</h2>{/if}
      <div class="body">{@render children?.()}</div>
      {#if footer}<div class="footer">{@render footer()}</div>{/if}
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(0, 0, 0, 0.45);
    display: grid;
    place-items: center;
  }
  .panel {
    max-width: calc(100vw - 48px);
    max-height: calc(100vh - 48px);
    display: flex;
    flex-direction: column;
    background: var(--color-surface);
    border: 1px solid var(--color-glass-border);
    border-radius: var(--dialog-radius);
    box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
    padding: 20px 22px 16px;
    outline: none;
  }
  h2 {
    margin: 0 0 12px;
    font-size: 15px;
    font-weight: 600;
  }
  .body {
    overflow: auto;
    min-height: 0;
    color: var(--color-text-secondary);
    font-size: 13px;
  }
  .footer {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 18px;
  }
</style>
