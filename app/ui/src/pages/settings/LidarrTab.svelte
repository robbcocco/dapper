<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrInstance, LidarrInstancesState } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Button from '../../widgets/Button.svelte';
  import EmptyState from '../../widgets/EmptyState.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import { confirm } from '../../widgets/dialogs';
  import ConnectionTile from './ConnectionTile.svelte';
  import LidarrDefaults from './LidarrDefaults.svelte';
  import LidarrFormDialog from './LidarrFormDialog.svelte';
  import { errorOf } from './connection';

  let instances = $state<LidarrInstancesState | null>(null);
  /** `undefined` = closed, `null` = add, instance = edit. */
  let form = $state<LidarrInstance | null | undefined>(undefined);

  const active = $derived(instances?.instances.find((i) => i.id === instances?.selectedId) ?? null);

  async function load(): Promise<void> {
    try {
      instances = await api.lidarrInstances();
    } catch (e) {
      toast(errorOf(e).message, { kind: 'error' });
    }
  }

  $effect(() => {
    void load();
    const un = api.onLidarrChanged(() => void load());
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

  async function remove(instance: LidarrInstance): Promise<void> {
    const ok = await confirm({
      title: 'Remove Instance',
      message: `Remove "${instance.name}"? This cannot be undone.`,
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (ok) await run(api.lidarrRemove(instance.id));
  }

  function closeForm(saved: boolean): void {
    form = undefined;
    if (saved) void load();
  }
</script>

<div class="tab">
  <div class="head">
    <h3>Lidarr Instances</h3>
    <Button variant="primary" icon="add" onclick={() => (form = null)}>Add Instance</Button>
  </div>

  {#if instances === null}
    <div class="center"><Spinner /></div>
  {:else if instances.instances.length === 0}
    <div class="empty">
      <EmptyState
        icon="album"
        title="No Lidarr instances configured"
        message="Add a Lidarr instance to enable download management"
      />
    </div>
  {:else}
    {#each instances.instances as inst (inst.id)}
      <ConnectionTile
        name={inst.name}
        lines={[inst.url]}
        active={inst.id === active?.id}
        onconnect={() => void run(api.lidarrSelect(inst.id))}
        onedit={() => (form = inst)}
        onremove={() => void remove(inst)}
      />
    {/each}
  {/if}

  {#if active}
    <hr />
    <h4>Default settings for new artists</h4>
    <p class="help">Used when adding an artist from the library via {active.name}.</p>
    {#key active.id}
      <LidarrDefaults {active} onsaved={() => void load()} />
    {/key}
  {/if}
</div>

{#if form !== undefined}
  <LidarrFormDialog existing={form} onclose={closeForm} />
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
  h4 {
    margin: 0 0 4px;
    font-size: 15px;
    font-weight: 600;
  }
  .help {
    margin: 0 0 20px;
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  hr {
    margin: 24px 0 16px;
    border: none;
    border-top: 1px solid var(--color-glass-border);
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
