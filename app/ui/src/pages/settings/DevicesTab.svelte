<script lang="ts">
  import * as api from '../../lib/api';
  import type { DeviceSettings, FolderStructure } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import DeviceSettingsDialog from '../device/DeviceSettingsDialog.svelte';
  import { errorOf } from './connection';

  const FOLDER_LABELS: Record<FolderStructure, string> = {
    artistAlbum: 'Artist / Album',
    artistAlbumYear: 'Artist / Year - Album',
    artistOnly: 'Artist',
    flat: 'Flat',
    custom: 'Custom',
  };

  type Stored = { status: 'loading' } | { status: 'error'; message: string } | { status: 'ok'; items: DeviceSettings[] };

  let stored = $state<Stored>({ status: 'loading' });
  let editPath = $state<string | null>(null);

  async function load(): Promise<void> {
    try {
      stored = { status: 'ok', items: await api.deviceSettingsAll() };
    } catch (e) {
      stored = { status: 'error', message: errorOf(e).message };
    }
  }

  $effect(() => {
    void load();
  });

  const connected = $derived(new Set(devices.list.map((d) => d.path)));

  const rows = $derived(
    stored.status === 'ok'
      ? stored.items.map((s) => {
          const parts: string[] = [];
          if (s.musicRootFolder !== '') parts.push(`Root: ${s.musicRootFolder}`);
          parts.push(FOLDER_LABELS[s.folderStructure]);
          return {
            settings: s,
            label: s.devicePath.split(/[\\/]/).filter((p) => p !== '').at(-1) ?? s.devicePath,
            summary: parts.join(' · '),
            isConnected: connected.has(s.devicePath),
          };
        })
      : [],
  );

  function closeDialog(): void {
    editPath = null;
    void load();
  }
</script>

{#if stored.status === 'loading'}
  <div class="center"><Spinner /></div>
{:else if stored.status === 'error'}
  <div class="center msg">{stored.message}</div>
{:else if rows.length === 0}
  <EmptyState
    icon="usb"
    title="No devices configured yet"
    message="Connect a device and open its settings via the Device page"
  />
{:else}
  <div class="tab">
    {#each rows as r (r.settings.devicePath)}
      <div class="tile">
        <span class="usb" class:on={r.isConnected}><Icon name="usb" size={18} /></span>
        <div class="text">
          <div class="label">{r.label}</div>
          <div class="path">{r.settings.devicePath}</div>
          <div class="summary">{r.summary}</div>
        </div>
        <span class="badge" class:on={r.isConnected}>{r.isConnected ? 'Connected' : 'Not connected'}</span>
        {#if r.isConnected}
          <IconButton
            icon="settings"
            size={16}
            label="Edit settings"
            color="var(--color-text-secondary)"
            onclick={() => (editPath = r.settings.devicePath)}
          />
        {/if}
      </div>
    {/each}
  </div>
{/if}

{#if editPath !== null}
  <DeviceSettingsDialog devicePath={editPath} onClose={closeDialog} />
{/if}

<style>
  .tab {
    padding: 24px 24px var(--scroll-bottom-inset);
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .msg {
    color: var(--color-text-secondary);
    user-select: text;
    -webkit-user-select: text;
  }
  .tile {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 8px;
    padding: 12px 12px 12px 16px;
    border-radius: 8px;
    background: var(--color-surface-variant);
    border: 1px solid var(--color-glass-border);
  }
  .usb {
    margin-right: 4px;
    color: var(--color-text-secondary);
    opacity: 0.6;
  }
  .usb.on {
    color: var(--color-accent);
    opacity: 1;
  }
  .text {
    flex: 1;
    min-width: 0;
  }
  .label {
    font-size: 13px;
  }
  .path {
    font-size: 10px;
    color: var(--color-text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .summary {
    margin-top: 4px;
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .badge {
    padding: 3px 8px;
    border-radius: 10px;
    background: var(--color-divider);
    color: var(--color-text-secondary);
    font-size: 10px;
    white-space: nowrap;
  }
  .badge.on {
    background: rgba(76, 175, 80, 0.12);
    color: #4caf50;
  }
</style>
