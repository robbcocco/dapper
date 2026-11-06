<script lang="ts">
  import * as api from '../../lib/api';
  import type { CacheCleanResult } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Button from '../../widgets/Button.svelte';
  import Tabs from '../../widgets/Tabs.svelte';
  import { confirm } from '../../widgets/dialogs';
  import { errorOf } from './connection';

  const CONCURRENCY = [1, 2, 3, 4].map((n) => ({ value: String(n), label: String(n) }));

  let concurrency = $state<string | null>(null);
  let cleaning = $state(false);

  $effect(() => {
    api
      .appSettingsGet()
      .then((s) => (concurrency = String(s.transferConcurrency)))
      .catch((e: unknown) => toast(errorOf(e).message, { kind: 'error' }));
  });

  async function setConcurrency(v: string): Promise<void> {
    try {
      const s = await api.appSettingsSetTransferConcurrency(Number(v));
      concurrency = String(s.transferConcurrency);
    } catch (e) {
      toast(errorOf(e).message, { kind: 'error' });
    }
  }

  /** Format matches lib/core/format/byte_format.dart. */
  function formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  function cleanMessage(r: CacheCleanResult): string {
    if (r.skippedStaging) return 'Cleared cover art. Skipped transfer staging — a transfer is in progress.';
    if (r.filesRemoved === 0) return 'Cache cleared';
    const plural = r.filesRemoved === 1 ? '' : 's';
    return `Cleared ${r.filesRemoved} leftover file${plural} (${formatBytes(r.bytesFreed)}) and cover art`;
  }

  async function cleanCache(): Promise<void> {
    cleaning = true;
    try {
      toast(cleanMessage(await api.cacheClean()));
    } catch (e) {
      toast(errorOf(e).message, { kind: 'error' });
    } finally {
      cleaning = false;
    }
  }

  async function confirmReset(): Promise<void> {
    const ok = await confirm({
      title: 'Reset all data',
      message:
        'This will remove all servers, credentials, device settings, and cached data. ' +
        'The app will return to the setup screen.\n\nThis cannot be undone.',
      confirmLabel: 'Reset',
      destructive: true,
    });
    if (!ok) return;
    try {
      // The backend emits `server-changed {selectedId: null}`; the shell then shows setup.
      await api.appReset();
    } catch (e) {
      toast(errorOf(e).message, { kind: 'error' });
    }
  }
</script>

<div class="tab">
  <h3>Transfer</h3>
  <p class="help">
    How many songs download from the server in parallel. Downloads are staged locally, then written to the device one
    at a time for the fastest, least-fragmented transfer.
  </p>
  <div class="row">
    <span class="row-label">Parallel downloads</span>
    {#if concurrency !== null}
      <Tabs value={concurrency} tabs={CONCURRENCY} onchange={(v) => void setConcurrency(v)} />
    {/if}
  </div>

  <hr />

  <h3>Cache</h3>
  <p class="help">Removes leftover temporary transfer files and cached cover art. Your servers, devices, and settings are kept.</p>
  <Button disabled={cleaning} onclick={() => void cleanCache()}>Clean cache</Button>

  <hr />

  <h3>Reset</h3>
  <p class="help">Clears all servers, credentials, device settings, and app data. The app will return to the setup screen.</p>
  <button type="button" class="reset" onclick={() => void confirmReset()}>Reset all data</button>
</div>

<style>
  .tab {
    padding: 24px 24px var(--scroll-bottom-inset);
  }
  h3 {
    margin: 0 0 4px;
    font-size: 15px;
    font-weight: 600;
  }
  .help {
    margin: 0 0 16px;
    font-size: 11px;
    line-height: 1.45;
    color: var(--color-text-secondary);
    max-width: 640px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 28px;
  }
  .row-label {
    width: 120px;
    font-size: 13px;
    color: var(--color-text-secondary);
  }
  hr {
    margin: 40px 0 20px;
    border: none;
    border-top: 1px solid var(--color-glass-border);
  }
  .reset {
    height: 34px;
    padding: 0 16px;
    border-radius: 8px;
    border: 1px solid #ff5252;
    background: transparent;
    color: #ff5252;
    font: inherit;
    font-size: 13px;
  }
  .reset:hover {
    background: rgba(255, 82, 82, 0.08);
  }
  .reset:focus-visible {
    outline: 2px solid var(--color-accent);
    outline-offset: 1px;
  }
</style>
