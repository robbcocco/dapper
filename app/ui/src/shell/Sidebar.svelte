<script lang="ts">
  import * as api from '../lib/api';
  import type { LidarrInstance } from '../lib/types';
  import { SidebarSection, selectedSection } from '../lib/stores/navigation.svelte';
  import { search } from '../lib/stores/search.svelte';
  import { resetAlbumsNav, resetGenresNav } from '../lib/stores/library-nav.svelte';
  import { selectionNav } from '../lib/stores/selection-nav.svelte';
  import { playlists } from '../lib/stores/playlists.svelte';
  import { devices, selectDevice } from '../lib/stores/devices.svelte';
  import Icon from '../widgets/Icon.svelte';
  import type { IconName } from '../widgets/icons';
  import ProgressBar from '../widgets/ProgressBar.svelte';
  import SidebarSearch from '../widgets/sidebar/SidebarSearch.svelte';
  import ServerSwitcher from '../widgets/sidebar/ServerSwitcher.svelte';
  import SyncStatus from '../widgets/sidebar/SyncStatus.svelte';
  import ExtraIcon from '../widgets/playlists/ExtraIcon.svelte';
  import { prompt } from '../widgets/dialogs';
  import { ejectDevice } from '../widgets/device/eject';

  function go(section: SidebarSection): void {
    search.query = '';
    selectedSection.value = section;
  }

  const library: { icon: IconName; label: string; section: SidebarSection; onclick?: () => void }[] = [
    { icon: 'album', label: 'Recently Added', section: SidebarSection.recentlyAdded },
    { icon: 'person', label: 'Artists', section: SidebarSection.artists },
    {
      icon: 'library_music',
      label: 'Albums',
      section: SidebarSection.albums,
      onclick: () => {
        selectedSection.value = SidebarSection.albums;
        resetAlbumsNav();
      },
    },
    { icon: 'music_note', label: 'Songs', section: SidebarSection.songs },
    {
      icon: 'category',
      label: 'Genres',
      section: SidebarSection.genres,
      // Clearing the drill-down lands on the genre list, not a stale album from another section.
      onclick: () => {
        go(SidebarSection.genres);
        resetGenresNav();
      },
    },
  ];

  let lidarr = $state<LidarrInstance | null>(null);

  async function loadLidarr(): Promise<void> {
    try {
      const s = await api.lidarrInstances();
      lidarr = s.instances.find((i) => i.id === s.selectedId) ?? null;
    } catch (e) {
      console.warn('sidebar: lidarr_instances failed', e);
    }
  }

  $effect(() => {
    void loadLidarr();
    const un = api.onLidarrChanged(() => void loadLidarr());
    return () => void un.then((f) => f());
  });

  async function createPlaylist(): Promise<void> {
    const name = await prompt({ title: 'New Playlist', placeholder: 'Playlist name', confirmLabel: 'Create' });
    if (name !== null) void playlists.create(name);
  }

  function openPlaylist(id: string): void {
    search.query = '';
    selectionNav.selectedPlaylistId = id;
    selectedSection.value = SidebarSection.playlists;
  }

  function openDevice(path: string): void {
    search.query = '';
    selectDevice(path);
    selectedSection.value = SidebarSection.device;
  }
</script>

{#snippet tile(icon: IconName, label: string, section: SidebarSection, onclick?: () => void)}
  {@const sel = selectedSection.value === section}
  <button class="tile" class:sel onclick={onclick ?? (() => go(section))}>
    <span class="ic" class:accent={sel}><Icon name={icon} size={16} /></span>
    <span class="label">{label}</span>
  </button>
{/snippet}

{#snippet header(label: string)}
  <div class="header">{label}</div>
{/snippet}

<nav class="sidebar">
  <div class="drag" data-tauri-drag-region></div>
  <div class="scroll">
    <SidebarSearch />
    <ServerSwitcher />
    <SyncStatus />

    {@render header('LIBRARY')}
    {#each library as l (l.section)}{@render tile(l.icon, l.label, l.section, l.onclick)}{/each}

    <div class="gap"></div>
    <div class="header row">
      <span class="grow">PLAYLISTS</span>
      <button class="hdr-btn" title="Import from Spotify" aria-label="Import from Spotify" onclick={() => go(SidebarSection.spotifyImport)}>
        <Icon name="cloud_download" size={14} />
      </button>
      <button class="hdr-btn" title="New Playlist" aria-label="New Playlist" onclick={createPlaylist}>
        <Icon name="add" size={14} />
      </button>
    </div>
    {#if playlists.items}
      {#each playlists.items as p (p.id)}
        {@const sel = selectedSection.value === SidebarSection.playlists && selectionNav.selectedPlaylistId === p.id}
        <button class="tile playlist" class:sel onclick={() => openPlaylist(p.id)}>
          <span class="ic"><Icon name="queue_music" size={14} /></span>
          <span class="label small">{p.name}</span>
        </button>
      {/each}
    {:else if playlists.loading}
      <div class="loading"><ProgressBar /></div>
    {/if}

    <div class="gap"></div>
    {#if lidarr}
      {@render header('LIDARR')}
      {@render tile('queue_music', lidarr.name, SidebarSection.lidarr)}
      <div class="gap"></div>
    {/if}

    {@render header('DEVICE')}
    {#if devices.list.length === 0}
      <div class="tile none">
        <span class="ic"><ExtraIcon name="usb_off" size={16} /></span>
        <span class="label">No device</span>
      </div>
    {:else}
      {#each devices.list as d (d.path)}
        {@const sel = selectedSection.value === SidebarSection.device && devices.selected?.path === d.path}
        <div class="tile device" class:sel>
          <button class="device-main" onclick={() => openDevice(d.path)}>
            <span class="ic" class:accent={sel}><Icon name="usb" size={16} /></span>
            <span class="label">{d.label}</span>
          </button>
          <button class="eject" title="Eject" aria-label="Eject {d.label}" onclick={() => void ejectDevice(d.path)}>
            <Icon name="eject" size={14} />
          </button>
        </div>
      {/each}
    {/if}

    <div class="divider"></div>
    {@render tile('settings', 'Settings', SidebarSection.settings)}
  </div>
</nav>

<style>
  .sidebar {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-sidebar-overlay);
  }
  .drag {
    height: 20px;
    flex: none;
  }
  .scroll {
    flex: 1;
    overflow-y: auto;
    padding-bottom: 8px;
  }
  .header {
    padding: 8px 16px 4px;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.8px;
    color: var(--color-text-secondary);
  }
  .header.row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding-right: 12px;
  }
  .grow {
    flex: 1;
  }
  .hdr-btn {
    display: grid;
    place-items: center;
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-secondary);
  }
  .hdr-btn:hover {
    color: var(--color-text-primary);
  }
  .gap {
    height: 16px;
  }
  .loading {
    padding: 16px;
  }
  .tile {
    display: flex;
    align-items: center;
    gap: 8px;
    width: calc(100% - 16px);
    height: 32px;
    margin: 1px 8px;
    padding: 0 16px;
    border: none;
    border-radius: 6px;
    background: transparent;
    color: var(--color-text-secondary);
    font: inherit;
    font-size: 13px;
    text-align: left;
  }
  button.tile:hover,
  .device:hover {
    background: rgba(255, 255, 255, 0.05);
  }
  .tile.sel,
  .tile.sel:hover {
    background: var(--color-selection-background);
    color: var(--color-text-primary);
    font-weight: 500;
  }
  .tile.playlist {
    height: 28px;
  }
  .tile.playlist.sel {
    font-weight: normal;
  }
  .ic {
    display: grid;
    place-items: center;
    color: var(--color-text-secondary);
  }
  .ic.accent {
    color: var(--color-accent);
  }
  .label {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .label.small {
    font-size: 12px;
  }
  .none {
    opacity: 0.4;
  }
  .device {
    padding-right: 8px;
  }
  .device-main {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: 1;
    min-width: 0;
    height: 100%;
    padding: 0;
    border: none;
    background: none;
    color: inherit;
    font: inherit;
    text-align: left;
  }
  .eject {
    display: grid;
    place-items: center;
    padding: 4px;
    border: none;
    border-radius: 4px;
    background: none;
    color: inherit;
  }
  .eject:hover {
    background: rgba(255, 255, 255, 0.08);
  }
  .divider {
    height: 1px;
    margin: 16px 0 15px;
    background: var(--color-glass-border);
  }
</style>
