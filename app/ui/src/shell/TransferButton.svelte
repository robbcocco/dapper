<script lang="ts">
  // Bottom-bar transfer status button + popup (bottom_bar_widget.dart `_TransferButton`).
  import * as api from '../lib/api';
  import type { TransferTask } from '../lib/types';
  import { confirm } from '../widgets/dialogs';
  import Icon from '../widgets/Icon.svelte';
  import IconButton from '../widgets/IconButton.svelte';
  import ProgressBar from '../widgets/ProgressBar.svelte';
  import VirtualList from '../widgets/VirtualList.svelte';
  import { buildQueueRows, groupProgress, isActive, isFinished, summarizeGroup } from '../widgets/device/grouping';
  import { transfers } from '../widgets/device/transfers.svelte';
  import { portal } from '../lib/portal';

  const POPUP_W = 300;
  const POPUP_H = 360;

  let open = $state(false);
  let anchor = $state({ right: 0, bottom: 0 });
  let button = $state<HTMLButtonElement>();
  let popup = $state<HTMLDivElement>();

  // Failed/cancelled tasks don't count toward the arc so a failure can't stall it short of full.
  const counts = $derived.by(() => {
    let completed = 0;
    let total = 0;
    for (const t of transfers.tasks) {
      if (t.status === 'cancelled' || t.status === 'failed') continue;
      total++;
      if (t.status === 'completed') completed++;
    }
    return { completed, total };
  });

  // Each downloading song contributes its partial byte progress as a fraction of one song.
  const progress = $derived.by(() => {
    const entries = Object.values(transfers.progress);
    if (entries.length === 0 || counts.total === 0) return counts.total > 0 ? counts.completed / counts.total : 0;
    let received = 0;
    let totalBytes = 0;
    for (const [r, t] of entries) {
      received += r;
      totalBytes += t;
    }
    const fraction = totalBytes > 0 ? received / totalBytes : 0;
    return (counts.completed + fraction * entries.length) / counts.total;
  });

  const active = $derived(transfers.activeCount);
  const hasActive = $derived(active > 0);
  const hasFailed = $derived(transfers.tasks.some((t) => t.status === 'failed'));
  const hasFinished = $derived(transfers.tasks.some(isFinished));
  const visible = $derived(transfers.tasks.filter((t) => t.status !== 'cancelled'));
  const rows = $derived(buildQueueRows(visible));

  function toggle(): void {
    if (open) {
      open = false;
      return;
    }
    const r = button?.getBoundingClientRect();
    if (!r) return;
    // Popup's bottom-right corner sits on the icon and extends up-and-left.
    anchor = {
      right: Math.max(8, window.innerWidth - (r.left + r.width / 2)),
      bottom: Math.max(8, window.innerHeight - (r.top + r.height / 2)),
    };
    open = true;
  }

  function onWindowPointerDown(e: PointerEvent): void {
    if (!open) return;
    const target = e.target as Node;
    if (popup?.contains(target) || button?.contains(target)) return;
    open = false;
  }

  async function cancelAll(): Promise<void> {
    const ok = await confirm({
      title: 'Cancel all transfers?',
      message: 'In-progress downloads will be aborted and queued transfers will be removed.',
      confirmLabel: 'Cancel all',
      destructive: true,
    });
    if (ok) await api.transferCancelAll(null);
  }

  const pct = (t: TransferTask): [number, number] => transfers.progress[t.id] ?? [0, 0];

  // SVG arc for the spinning ring.
  const R = 5.5;
  const C = 2 * Math.PI * R;
</script>

<svelte:window
  onpointerdown={onWindowPointerDown}
  onkeydown={(e) => {
    if (open && e.key === 'Escape') open = false;
  }}
/>

{#if transfers.tasks.length === 0}
  <span class="placeholder"></span>
{:else}
  <button
    bind:this={button}
    type="button"
    class="tb"
    title={hasActive ? `Transferring ${active} file${active === 1 ? '' : 's'}…` : 'Transfer complete — tap for details'}
    aria-label="Transfer queue"
    aria-expanded={open}
    onclick={toggle}
  >
    {#if hasActive}
      <svg class="ring" width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
        <circle
          cx="7"
          cy="7"
          r={R}
          fill="none"
          stroke="var(--color-accent)"
          stroke-width="1.5"
          stroke-dasharray={progress > 0 ? `${Math.min(progress, 1) * C} ${C}` : `${C * 0.3} ${C}`}
          transform="rotate(-90 7 7)"
        />
      </svg>
    {:else}
      <span class="done"><Icon name="cloud_done" size={15} /></span>
    {/if}
  </button>
{/if}

{#if open && transfers.tasks.length > 0}
  <div
    bind:this={popup}
    use:portal
    class="popup"
    role="dialog"
    aria-label="Transfer Queue"
    style:width="{POPUP_W}px"
    style:height="{POPUP_H}px"
    style:right="{anchor.right}px"
    style:bottom="{anchor.bottom}px"
  >
    <div class="head">
      <span class="title">Transfer Queue</span>
      {#if hasActive || transfers.anyPaused}
        <IconButton
          icon={transfers.anyPaused ? 'play' : 'pause'}
          size={14}
          label={transfers.anyPaused ? 'Resume all' : 'Pause all'}
          color="var(--color-text-secondary)"
          onclick={() => void (transfers.anyPaused ? api.transferResume(null) : api.transferPause(null))}
        />
      {/if}
      {#if hasFailed}
        <IconButton
          icon="refresh"
          size={14}
          label="Retry all failed"
          color="var(--color-text-secondary)"
          onclick={() => void api.transferRetryFailed(null)}
        />
      {/if}
      {#if hasActive}
        <IconButton icon="cancel" size={14} label="Cancel all" color="var(--color-text-secondary)" onclick={cancelAll} />
      {/if}
      {#if hasFinished}
        <button type="button" class="clear" onclick={() => void api.transferClearCompleted()}>Clear done</button>
      {/if}
    </div>
    <div class="list">
      {#if rows.length === 0}
        <div class="empty">No transfers</div>
      {:else}
        <VirtualList count={rows.length} rowHeight={40}>
          {#snippet row(i)}
            {@const r = rows[i]}
            {#if r?.kind === 'single'}
              {@const t = r.task}
              {@const [rec, tot] = t.status === 'inProgress' ? pct(t) : [0, 0]}
              <div class="row">
                {@render statusIcon(t.status)}
                <div class="text">
                  <div class="line">
                    <span class="name">{t.song.title}</span>
                    {#if tot > 0}<span class="pct">{Math.round((rec / tot) * 100)}%</span>{/if}
                  </div>
                  {#if t.status === 'inProgress'}
                    <div class="bar"><ProgressBar value={tot > 0 ? rec / tot : null} height={2} /></div>
                  {:else if t.status === 'failed'}
                    <div class="err">{t.errorMessage ?? 'Failed'}</div>
                  {/if}
                </div>
              </div>
            {:else if r?.kind === 'group'}
              {@const g = summarizeGroup(r.tasks)}
              <div class="row">
                {@render statusIcon(g.status)}
                <div class="text">
                  <div class="line">
                    <span class="name group">{g.artist} — {g.album}</span>
                    <span class="pct">{g.completed}/{g.total}</span>
                  </div>
                  {#if g.status === 'inProgress' || g.status === 'queued'}
                    <div class="bar"><ProgressBar value={groupProgress(g, transfers.progress)} height={2} /></div>
                  {:else if g.status === 'failed'}
                    <div class="err">{g.firstError ?? 'Failed'}</div>
                  {/if}
                </div>
              </div>
            {/if}
          {/snippet}
        </VirtualList>
      {/if}
    </div>
  </div>
{/if}

{#snippet statusIcon(status: TransferTask['status'])}
  {#if status === 'completed'}
    <Icon name="check_circle" size={13} color="#4caf50" />
  {:else if status === 'failed'}
    <Icon name="error" size={13} color="#ff5252" />
  {:else if status === 'inProgress'}
    <Icon name="sync" size={13} color="var(--color-accent)" />
  {:else}
    <Icon name="schedule" size={13} color="var(--color-text-secondary)" />
  {/if}
{/snippet}

<style>
  .placeholder {
    display: inline-block;
    width: 28px;
    height: 28px;
    flex: none;
  }
  .tb {
    display: inline-grid;
    place-items: center;
    width: 28px;
    height: 28px;
    flex: none;
    padding: 0;
    border: none;
    border-radius: 6px;
    background: transparent;
  }
  .tb:hover {
    background: rgba(255, 255, 255, 0.08);
  }
  .ring {
    animation: spin 3s linear infinite;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
  .done {
    display: inline-grid;
    color: var(--color-text-secondary);
    opacity: 0.55;
  }
  .popup {
    position: fixed;
    z-index: 900;
    display: flex;
    flex-direction: column;
    background: var(--color-surface);
    border: 1px solid var(--color-glass-border);
    border-radius: var(--menu-radius);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    overflow: hidden;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 2px;
    padding: 8px 6px 6px 14px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .title {
    flex: 1;
    font-size: 13px;
    font-weight: 600;
  }
  .clear {
    height: 28px;
    padding: 0 8px;
    border: none;
    border-radius: 6px;
    background: transparent;
    font: inherit;
    font-size: 11px;
    color: var(--color-accent);
  }
  .clear:hover {
    background: rgba(255, 255, 255, 0.06);
  }
  .list {
    flex: 1;
    min-height: 0;
    /* VirtualList's floating-bar inset is irrelevant inside the popup. */
    --scroll-bottom-inset: 6px;
  }
  .empty {
    height: 100%;
    display: grid;
    place-items: center;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .row {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 0 14px;
  }
  .text {
    flex: 1;
    min-width: 0;
  }
  .line {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 12px;
  }
  .group {
    font-weight: 500;
  }
  .pct {
    font-size: 10px;
    color: var(--color-accent);
  }
  .bar {
    margin-top: 3px;
  }
  .err {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 10px;
    color: #ff5252;
  }
</style>
