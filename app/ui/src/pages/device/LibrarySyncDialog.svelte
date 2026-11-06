<script lang="ts">
  // library_sync_dialog.dart: diff the library against the device manifests and offer to
  // enqueue every missing/partial album, honouring the device's bulk-zip setting.
  import * as api from '../../lib/api';
  import { toAppError } from '../../lib/ipc';
  import { session } from '../../lib/stores/session.svelte';
  import type { DeviceSettings, LibrarySyncPlan } from '../../lib/types';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Spinner from '../../widgets/Spinner.svelte';

  let { devicePath, onClose }: { devicePath: string; onClose: () => void } = $props();

  let scanning = $state(true);
  let scanned = $state(0);
  let status = $state('Scanning library…');
  let plan = $state<LibrarySyncPlan | null>(null);
  let error = $state<string | null>(null);
  let settings = $state<DeviceSettings | null>(null);
  let enqueueing = $state(false);

  async function scan(): Promise<void> {
    if (session.serverId === null) {
      scanning = false;
      error = 'No active server';
      return;
    }
    try {
      const [s, p] = await Promise.all([
        api.deviceSettingsGet(devicePath),
        api.deviceSyncPlan(devicePath, (pr) => {
          scanned = pr.scanned;
          status = `Scanning library… ${pr.scanned} albums`;
        }),
      ]);
      settings = s;
      plan = p;
    } catch (e) {
      error = toAppError(e).message;
    } finally {
      scanning = false;
    }
  }
  void scan();

  const folderUnsupported = $derived(
    settings !== null &&
      (settings.folderStructure === 'flat' ||
        settings.folderStructure === 'artistOnly' ||
        (settings.folderStructure === 'custom' && !settings.customFolderTemplate.includes('{album}'))),
  );
  const useZip = $derived(settings !== null && settings.useZipDownload && settings.transcodeFormat === 'original');

  async function enqueueAll(): Promise<void> {
    if (plan === null) return;
    enqueueing = true;
    status = `Queueing transfers… ${plan.unsynced.length} albums`;
    try {
      await api.transferEnqueueAlbums(
        devicePath,
        plan.unsynced.map((a) => a.id),
        useZip,
      );
      onClose();
    } catch (e) {
      error = toAppError(e).message;
    } finally {
      enqueueing = false;
    }
  }
</script>

<Dialog title="Sync library to device" width={468} dismissible={false} onclose={onClose}>
  <div class="body">
    {#if error !== null}
      <div class="error">{error}</div>
    {:else if folderUnsupported && !scanning}
      <p>
        Sync requires an Artist/Album folder structure. Per-album sync state cannot be determined for flat or artist-only
        layouts.
      </p>
    {:else if scanning || enqueueing}
      <div class="progress">
        <Spinner size={32} stroke={3} />
        <span>{status}</span>
        {#if scanning && scanned > 0}<span class="count">{scanned}</span>{/if}
      </div>
    {:else if plan !== null}
      <div class="stat"><span>Albums scanned</span><b>{scanned}</b></div>
      <div class="stat"><span>Albums missing or partial</span><b>{plan.missingAlbums}</b></div>
      <div class="stat"><span>Songs to transfer</span><b>~{plan.missingSongs}</b></div>
      <p class="hint">
        {#if plan.missingAlbums === 0}
          Everything is already synced.
        {:else if useZip}
          Transfers will use bulk-zip downloads (one request per album).
        {:else}
          Transfers will use per-song downloads. Enable bulk zip in device settings for fewer round-trips.
        {/if}
      </p>
    {/if}
  </div>
  {#snippet footer()}
    {#if scanning || enqueueing}
      <Button variant="text" onclick={onClose}>Cancel</Button>
    {:else if error !== null || folderUnsupported || plan === null}
      <Button variant="text" onclick={onClose}>Close</Button>
    {:else}
      <Button variant="text" onclick={onClose}>Cancel</Button>
      <Button variant="primary" disabled={plan.missingAlbums === 0} onclick={() => void enqueueAll()}>
        {plan.missingAlbums === 0 ? 'Up to date' : `Sync ${plan.missingAlbums} albums`}
      </Button>
    {/if}
  {/snippet}
</Dialog>

<style>
  .body {
    font-size: 12px;
  }
  p {
    margin: 8px 0;
  }
  .error {
    padding: 8px 0;
    color: #ff5252;
  }
  .progress {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 8px 0;
  }
  .progress :global(.sp) {
    color: var(--color-accent);
  }
  .count {
    margin-top: -8px;
    font-size: 11px;
  }
  .stat {
    display: flex;
    justify-content: space-between;
    padding: 3px 0;
  }
  .stat b {
    font-weight: 600;
    color: var(--color-text-primary);
  }
  .hint {
    margin-top: 10px;
    font-size: 11px;
  }
</style>
