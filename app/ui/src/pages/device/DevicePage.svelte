<script lang="ts">
  // device_page.dart
  import * as api from '../../lib/api';
  import { devices } from '../../lib/stores/devices.svelte';
  import type { DeviceSettings } from '../../lib/types';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import ProgressBar from '../../widgets/ProgressBar.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import Tabs from '../../widgets/Tabs.svelte';
  import { ejectDevice } from '../../widgets/device/eject';
  import { formatCapacity } from '../../widgets/device/format';
  import { transfers } from '../../widgets/device/transfers.svelte';
  import DeviceSettingsDialog from './DeviceSettingsDialog.svelte';
  import FileBrowser from './FileBrowser.svelte';
  import LibrarySyncDialog from './LibrarySyncDialog.svelte';
  import QueueList from './QueueList.svelte';
  import ScanDialog from './ScanDialog.svelte';
  import ScrobbleBanner from './ScrobbleBanner.svelte';

  type Tab = 'device' | 'queue';
  type OpenDialog = { kind: 'sync' | 'scan' | 'settings'; path: string } | null;

  let tab = $state<Tab>('device');
  let dialog = $state<OpenDialog>(null);
  let settings = $state<DeviceSettings | null>(null);
  let settingsReady = $state(false);

  const selected = $derived(devices.selected);
  const selectedPath = $derived(selected?.path ?? null);

  // Per-device settings drive the music root (file browser + capacity line).
  $effect(() => {
    const path = selectedPath;
    settings = null;
    settingsReady = false;
    if (path === null) return;
    let stale = false;
    api
      .deviceSettingsGet(path)
      .then((s) => {
        if (!stale) settings = s;
      })
      .catch(() => {
        // Without settings the browser falls back to the device root.
      })
      .finally(() => {
        if (!stale) settingsReady = true;
      });
    return () => {
      stale = true;
    };
  });

  const usedFraction = $derived(
    selected && selected.totalBytes > 0 ? (selected.totalBytes - selected.availableBytes) / selected.totalBytes : 0,
  );
  const tabs = $derived([
    { value: 'device' as const, label: 'On Device' },
    { value: 'queue' as const, label: 'Transfer Queue', badge: transfers.activeCount },
  ]);
</script>

{#if !devices.loaded}
  <div class="center"><Spinner size={28} /></div>
{:else if devices.list.length === 0}
  <EmptyState icon="usb" title="No device connected" message="Connect a USB drive or SD card to get started" />
{:else}
  <section class="page">
    <header class="header">
      <Icon name="usb" size={15} color={selected ? 'var(--color-accent)' : 'var(--color-text-secondary)'} />
      <span class="label" class:none={!selected}>{selected?.label ?? 'Select a device from the sidebar'}</span>
      {#if selected}
        {@const path = selected.path}
        <IconButton icon="sync" size={16} label="Sync library to device" color="var(--color-text-secondary)" onclick={() => (dialog = { kind: 'sync', path })} />
        <IconButton icon="search" size={16} label="Scan device library" color="var(--color-text-secondary)" onclick={() => (dialog = { kind: 'scan', path })} />
        <IconButton icon="eject" size={16} label="Eject device" color="var(--color-text-secondary)" onclick={() => void ejectDevice(path)} />
        <IconButton icon="settings" size={16} label="Device settings" color="var(--color-text-secondary)" onclick={() => (dialog = { kind: 'settings', path })} />
      {/if}
    </header>

    {#if selected}
      <div class="capacity">
        <ProgressBar value={usedFraction} height={6} />
        <div class="cap-line">
          <span>{formatCapacity(selected.availableBytes)} available of {formatCapacity(selected.totalBytes)}</span>
          {#if settings && settings.musicRootFolder !== ''}
            <span class="root">Root: {settings.musicRootFolder}</span>
          {/if}
        </div>
      </div>
      <ScrobbleBanner devicePath={selected.path} />
    {/if}

    <div class="tabs"><Tabs bind:value={tab} {tabs} /></div>

    <div class="content">
      {#if tab === 'device'}
        {#if selected === null}
          <div class="center muted">Select a device above</div>
        {:else if !settingsReady}
          <div class="center"><Spinner /></div>
        {:else}
          {#key selected.path}
            <FileBrowser devicePath={selected.path} musicRootFolder={settings?.musicRootFolder ?? ''} />
          {/key}
        {/if}
      {:else}
        <QueueList />
      {/if}
    </div>
  </section>
{/if}

{#if dialog?.kind === 'sync'}
  <LibrarySyncDialog devicePath={dialog.path} onClose={() => (dialog = null)} />
{:else if dialog?.kind === 'scan'}
  <ScanDialog devicePath={dialog.path} onClose={() => (dialog = null)} />
{:else if dialog?.kind === 'settings'}
  {@const path = dialog.path}
  <DeviceSettingsDialog
    devicePath={path}
    onClose={() => (dialog = null)}
    onSaved={(s) => {
      if (selectedPath === path) settings = s;
    }}
  />
{/if}

<style>
  .page {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .muted {
    color: var(--color-text-secondary);
  }
  .header {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 10px 12px 10px 20px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .label {
    flex: 1;
    min-width: 0;
    margin-left: 4px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13px;
    font-weight: 600;
  }
  .label.none {
    font-weight: normal;
    color: var(--color-text-secondary);
  }
  .capacity {
    padding: 10px 24px 0;
  }
  .capacity :global(.pb) {
    border-radius: 4px;
    background: var(--color-surface-variant);
  }
  .cap-line {
    display: flex;
    justify-content: space-between;
    margin-top: 4px;
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .root {
    font-size: 10px;
  }
  .tabs {
    display: flex;
    justify-content: center;
    padding: 10px 0 8px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .content {
    flex: 1;
    min-height: 0;
  }
</style>
