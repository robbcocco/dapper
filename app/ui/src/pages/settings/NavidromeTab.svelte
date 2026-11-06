<script lang="ts">
  import * as api from '../../lib/api';
  import type { NavidromeServer, ServersState } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Button from '../../widgets/Button.svelte';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import { confirm } from '../../widgets/dialogs';
  import ConnectionTile from './ConnectionTile.svelte';
  import ServerFormDialog from './ServerFormDialog.svelte';
  import { errorOf } from './connection';

  let servers = $state<ServersState | null>(null);
  /** `undefined` = closed, `null` = add, server = edit. */
  let form = $state<NavidromeServer | null | undefined>(undefined);

  async function load(): Promise<void> {
    try {
      servers = await api.serversList();
    } catch (e) {
      toast(errorOf(e).message, { kind: 'error' });
    }
  }

  $effect(() => {
    void load();
    const un = api.onServerChanged(() => void load());
    return () => void un.then((f) => f());
  });

  async function run(action: Promise<void>): Promise<void> {
    try {
      await action;
    } catch (e) {
      toast(errorOf(e).message, { kind: 'error' });
    }
    await load();
  }

  async function remove(server: NavidromeServer): Promise<void> {
    const ok = await confirm({
      title: 'Remove Server',
      message: `Remove "${server.name}"? This cannot be undone.`,
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (ok) await run(api.serverRemove(server.id));
  }

  function closeForm(saved: boolean): void {
    form = undefined;
    if (saved) void load();
  }
</script>

<div class="tab">
  <div class="head">
    <h3>Navidrome Servers</h3>
    <Button variant="primary" icon="add" onclick={() => (form = null)}>Add Server</Button>
  </div>

  {#if servers === null}
    <div class="center"><Spinner /></div>
  {:else if servers.servers.length === 0}
    <div class="empty">
      <EmptyState icon="library_music" title="No servers configured" message="Add a Navidrome server to get started" />
    </div>
  {:else}
    {#each servers.servers as s (s.id)}
      <ConnectionTile
        name={s.name}
        lines={[s.url, s.username]}
        active={s.id === servers.selectedId}
        onconnect={() => void run(api.serverSelect(s.id))}
        onedit={() => (form = s)}
        onremove={() => void remove(s)}
      />
    {/each}
  {/if}
</div>

{#if form !== undefined}
  <ServerFormDialog existing={form} onclose={closeForm} />
{/if}

<style>
  .tab {
    padding: 24px 24px var(--scroll-bottom-inset);
  }
  .head {
    display: flex;
    align-items: center;
    margin-bottom: 16px;
  }
  h3 {
    flex: 1;
    margin: 0;
    font-size: 18px;
    font-weight: 600;
  }
  .center {
    display: grid;
    place-items: center;
    padding-top: 48px;
  }
  .empty {
    padding-top: 24px;
  }
</style>
