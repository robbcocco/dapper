<script lang="ts">
  // Device page "Transfer Queue" tab (device_page.dart `_QueueList`, `_TaskRow`, `_AlbumGroupRow`).
  import * as api from '../../lib/api';
  import type { TransferTask } from '../../lib/types';
  import { confirm } from '../../widgets/dialogs';
  import Button from '../../widgets/Button.svelte';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import ProgressBar from '../../widgets/ProgressBar.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { buildQueueRows, groupProgress, isActive, isFinished, statusLabel, summarizeGroup } from '../../widgets/device/grouping';
  import { transfers } from '../../widgets/device/transfers.svelte';
  import StatusIcon from './StatusIcon.svelte';

  const isMac = typeof navigator !== 'undefined' && /mac/i.test(navigator.platform || navigator.userAgent);

  const queue = $derived(transfers.tasks);
  const rows = $derived(buildQueueRows(queue));
  const hasPermissionError = $derived(queue.some((t) => t.errorMessage === 'permission_denied'));
  const hasActive = $derived(queue.some(isActive));
  const hasFailed = $derived(queue.some((t) => t.status === 'failed'));
  const hasFinished = $derived(queue.some(isFinished));

  const statusColor = (s: TransferTask['status']): string =>
    s === 'completed' ? '#4caf50' : s === 'failed' ? '#ff5252' : 'var(--color-text-secondary)';

  async function cancelAll(): Promise<void> {
    const ok = await confirm({
      title: 'Cancel all transfers?',
      message: 'In-progress downloads will be aborted and queued transfers will be removed.',
      confirmLabel: 'Cancel all',
      destructive: true,
    });
    if (ok) await api.transferCancelAll(null);
  }

  function retryGroup(group: TransferTask[]): void {
    for (const t of group) if (t.status === 'failed') void api.transferRetry(t.id);
  }
</script>

{#if queue.length === 0}
  <EmptyState icon="queue_music" title="No transfers queued" message="Right-click songs or albums in the library to add them" />
{:else}
  <div class="queue">
    {#if hasPermissionError}
      <div class="perm">
        <Icon name="lock" size={16} />
        <span class="perm-text">
          {#if isMac}
            macOS blocked write access to the device.<br />Grant Full Disk Access to Dapper in System Settings.
          {:else}
            Write access to the device was denied.<br />Check file permissions.
          {/if}
        </span>
        {#if isMac}
          <button type="button" class="perm-btn" onclick={() => void api.openFullDiskAccessSettings()}>Open Settings</button>
        {/if}
      </div>
    {/if}

    {#if hasActive || hasFailed || hasFinished || transfers.anyPaused}
      <div class="bulk">
        {#if hasActive || transfers.anyPaused}
          <Button
            variant="text"
            small
            icon={transfers.anyPaused ? 'play' : 'pause'}
            onclick={() => void (transfers.anyPaused ? api.transferResume(null) : api.transferPause(null))}
          >
            {transfers.anyPaused ? 'Resume all' : 'Pause all'}
          </Button>
        {/if}
        {#if hasFailed}
          <Button variant="text" small icon="refresh" onclick={() => void api.transferRetryFailed(null)}>Retry all</Button>
        {/if}
        {#if hasActive}
          <Button variant="text" small icon="cancel" onclick={() => void cancelAll()}>Cancel all</Button>
        {/if}
        {#if hasFinished}
          <Button variant="text" small onclick={() => void api.transferClearCompleted()}>Clear finished</Button>
        {/if}
      </div>
    {/if}

    <div class="list">
      <VirtualList count={rows.length} rowHeight={56} paddingTop={8}>
        {#snippet row(i)}
          {@const r = rows[i]}
          {#if r?.kind === 'single'}
            {@const t = r.task}
            {@const bytes = transfers.progress[t.id]}
            <div class="row">
              <StatusIcon status={t.status} />
              <div class="text">
                <div class="name">{t.song.title}</div>
                {#if t.status === 'inProgress'}
                  <div class="bar"><ProgressBar value={bytes && bytes[1] > 0 ? bytes[0] / bytes[1] : null} /></div>
                {:else}
                  <div class="sub" style:color={statusColor(t.status)}>{statusLabel(t.status, t.errorMessage)}</div>
                {/if}
              </div>
              {#if isActive(t)}
                <IconButton icon="close" size={14} label="Cancel" color="var(--color-text-secondary)" onclick={() => void api.transferCancel(t.id)} />
              {:else if t.status === 'failed'}
                <IconButton icon="refresh" size={14} label="Retry" color="var(--color-text-secondary)" onclick={() => void api.transferRetry(t.id)} />
              {/if}
            </div>
          {:else if r?.kind === 'group'}
            {@const g = summarizeGroup(r.tasks)}
            <div class="row">
              <StatusIcon status={g.status} />
              <div class="text">
                <div class="name group">{g.artist} — {g.album}</div>
                {#if g.status === 'inProgress' || g.status === 'queued'}
                  <div class="bar"><ProgressBar value={groupProgress(g, transfers.progress)} /></div>
                  <div class="sub">{g.completed} / {g.total} songs</div>
                {:else if g.status === 'completed'}
                  <div class="sub" style:color={statusColor(g.status)}>Done — {g.total} songs</div>
                {:else}
                  <div class="sub" style:color={statusColor(g.status)}>
                    {statusLabel(g.status, g.firstError)} ({g.completed} / {g.total})
                  </div>
                {/if}
              </div>
              {#if g.status === 'queued' || g.status === 'inProgress'}
                <IconButton
                  icon="close"
                  size={14}
                  label="Cancel album"
                  color="var(--color-text-secondary)"
                  onclick={() => void api.transferCancel(g.leader.id)}
                />
              {:else if g.status === 'failed'}
                <IconButton
                  icon="refresh"
                  size={14}
                  label="Retry failed songs"
                  color="var(--color-text-secondary)"
                  onclick={() => retryGroup(r.tasks)}
                />
              {/if}
            </div>
          {/if}
        {/snippet}
      </VirtualList>
    </div>
  </div>
{/if}

<style>
  .queue {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .perm {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 10px 16px 0;
    padding: 10px 14px;
    border: 1px solid rgba(255, 82, 82, 0.4);
    border-radius: 8px;
    background: rgba(255, 82, 82, 0.12);
    color: #ff5252;
  }
  .perm-text {
    flex: 1;
    font-size: 11px;
  }
  .perm-btn {
    padding: 6px 10px;
    border: none;
    border-radius: 6px;
    background: transparent;
    font: inherit;
    font-size: 11px;
    color: #ff5252;
  }
  .perm-btn:hover {
    background: rgba(255, 82, 82, 0.12);
  }
  .bulk {
    display: flex;
    justify-content: flex-end;
    gap: 2px;
    padding: 6px 20px 0;
  }
  .bulk :global(.btn) {
    color: var(--color-text-secondary);
    font-size: 11px;
  }
  .list {
    flex: 1;
    min-height: 0;
  }
  .row {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 24px;
    border-bottom: 0.5px solid var(--color-divider);
  }
  .text {
    flex: 1;
    min-width: 0;
  }
  .name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 12px;
  }
  .group {
    font-weight: 500;
  }
  .bar {
    margin-top: 3px;
  }
  .sub {
    margin-top: 2px;
    font-size: 10px;
    color: var(--color-text-secondary);
  }
</style>
