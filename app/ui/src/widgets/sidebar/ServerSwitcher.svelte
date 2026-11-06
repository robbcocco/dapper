<script lang="ts">
  import * as api from '../../lib/api';
  import type { NavidromeServer } from '../../lib/types';
  import { showContextMenu } from '../../lib/menu';
  import { selectedSection } from '../../lib/stores/navigation.svelte';
  import { toast } from '../../lib/stores/toast.svelte';
  import ExtraIcon from '../playlists/ExtraIcon.svelte';

  let servers = $state<NavidromeServer[]>([]);
  let selectedId = $state<string | null>(null);
  const active = $derived(servers.find((s) => s.id === selectedId) ?? null);

  async function load(): Promise<void> {
    try {
      const s = await api.serversList();
      servers = s.servers;
      selectedId = s.selectedId;
    } catch (e) {
      console.warn('sidebar: servers_list failed', e);
    }
  }

  $effect(() => {
    const un = api.onServerChanged((e) => {
      selectedId = e.selectedId;
      void load();
    });
    return () => void un.then((f) => f());
  });

  // Servers are added / renamed on the Settings page; refresh whenever the section changes.
  $effect(() => {
    void selectedSection.value;
    void load();
  });

  async function openMenu(e: MouseEvent): Promise<void> {
    const id = await showContextMenu(
      servers.map((s) => ({ id: s.id, label: s.name, checked: s.id === active?.id })),
      { x: e.clientX, y: e.clientY },
    );
    if (id === null || id === active?.id) return;
    try {
      await api.serverSelect(id);
    } catch (err) {
      toast(`Could not switch server: ${err instanceof Error ? err.message : String(err)}`, { kind: 'error' });
    }
  }
</script>

{#if servers.length > 0}
  <button class="switcher" onclick={openMenu}>
    <ExtraIcon name="dns" size={13} />
    <span class="name" class:none={active === null}>{active?.name ?? 'No Server'}</span>
    <ExtraIcon name="unfold_more" size={12} />
  </button>
{/if}

<style>
  .switcher {
    display: flex;
    align-items: center;
    gap: 6px;
    width: calc(100% - 16px);
    height: 32px;
    margin: 4px 8px 0;
    padding: 0 16px;
    border: none;
    border-radius: 6px;
    background: transparent;
    color: var(--color-text-secondary);
    font: inherit;
    text-align: left;
  }
  .switcher:hover {
    background: rgba(255, 255, 255, 0.05);
  }
  .name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 12px;
    font-weight: 500;
    color: var(--color-text-primary);
  }
  .name.none {
    color: var(--color-text-secondary);
  }
</style>
