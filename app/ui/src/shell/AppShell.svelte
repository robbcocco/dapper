<script lang="ts">
  import Sidebar from './Sidebar.svelte';
  import MainPanel from './MainPanel.svelte';
  import BottomBar from './BottomBar.svelte';
  import SetupPage from '../pages/setup/SetupPage.svelte';
  import Toaster from '../widgets/Toaster.svelte';
  import * as api from '../lib/api';
  import { handleShortcut, shortcuts } from '../lib/stores/shortcuts.svelte';
  import { session } from '../lib/stores/session.svelte';
  import { selectedSection, SidebarSection } from '../lib/stores/navigation.svelte';
  import { player, startPlayerSync } from '../lib/stores/player.svelte';
  import { startDevicesSync } from '../lib/stores/devices.svelte';
  import { starred } from '../lib/stores/starred.svelte';
  import { toast } from '../lib/stores/toast.svelte';

  shortcuts.playPause = player.toggle;
  shortcuts.next = player.next;
  shortcuts.previous = player.previous;

  /** serverCredentialsProvider loading state: nothing renders until the first answer. */
  let serversLoaded = $state(false);

  $effect(() => {
    let pushed = false;
    const subs = [
      api.onServerChanged(({ selectedId }) => {
        pushed = true;
        session.serverId = selectedId;
        serversLoaded = true;
      }),
      // Background failures (e.g. playlist edits) surface as a snackbar.
      api.onActionError(({ message }) => toast(message, { kind: 'error' })),
    ];
    api
      .serversList()
      .then(({ selectedId }) => {
        // A server-changed event that raced this fetch is newer; keep it.
        if (!pushed) session.serverId = selectedId;
      })
      .catch((e: unknown) => console.warn('servers_list failed', e))
      .finally(() => (serversLoaded = true));
    const stopPlayer = startPlayerSync();
    const stopDevices = startDevicesSync();
    return () => {
      subs.forEach((s) => void s.then((un) => un()));
      stopPlayer();
      stopDevices();
    };
  });

  // Section switches remount their page (which refetches); the Songs tab also picks up
  // stars changed on other clients (app_shell.dart _MainPanel listener).
  let prevSection = selectedSection.value;
  $effect(() => {
    const section = selectedSection.value;
    if (section === prevSection) return;
    prevSection = section;
    if (section === SidebarSection.songs) void starred.reload();
  });
</script>

<svelte:window onkeydown={handleShortcut} />

{#if !serversLoaded}
  <div class="blank"></div>
{:else if session.serverId === null}
  <div class="setup"><SetupPage /></div>
{:else}
  <div class="shell">
    <main class="main"><MainPanel /></main>
    <aside class="card sidebar"><Sidebar /></aside>
    <div class="bottom-area">
      <div class="card bottom-bar"><BottomBar /></div>
    </div>
  </div>
{/if}

<Toaster />

<style>
  .blank,
  .setup {
    height: 100%;
    background: var(--color-background);
  }
  .shell {
    position: relative;
    height: 100%;
  }
  /* Content runs under the floating bar; pages pad with --scroll-bottom-inset. */
  .main {
    position: absolute;
    left: calc(var(--sidebar-width) + var(--shell-margin) * 2);
    right: 0;
    top: 0;
    bottom: 0;
    background: var(--color-background);
    overflow: hidden;
  }
  .card {
    border: 1px solid var(--color-glass-border);
    box-shadow: var(--card-shadow);
    overflow: hidden;
  }
  .sidebar {
    position: absolute;
    left: var(--shell-margin);
    top: var(--shell-margin);
    bottom: var(--shell-margin);
    width: var(--sidebar-width);
    border-radius: var(--card-radius);
  }
  .bottom-area {
    position: absolute;
    left: calc(var(--sidebar-width) + var(--shell-margin) * 2);
    right: var(--shell-margin);
    bottom: var(--shell-margin);
    height: var(--bottom-bar-height);
    display: flex;
    justify-content: center;
    pointer-events: none;
  }
  .bottom-bar {
    width: clamp(620px, 65%, 1000px);
    flex: none;
    border-radius: var(--bar-radius);
    background: var(--color-bottom-bar);
    backdrop-filter: blur(24px) saturate(1.6);
    -webkit-backdrop-filter: blur(24px) saturate(1.6);
    pointer-events: auto;
  }
</style>
