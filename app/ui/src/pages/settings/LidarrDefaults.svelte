<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrInstance, LidarrQualityProfile, LidarrRootFolder } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Select from '../../widgets/Select.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import { errorOf } from './connection';

  /** Root folder + quality profile pickers for the selected instance (_DefaultsPickers). */
  let { active, onsaved }: { active: LidarrInstance; onsaved: () => void } = $props();

  type Loaded<T> = { status: 'loading' } | { status: 'error'; message: string } | { status: 'ok'; items: T[] };

  let folders = $state<Loaded<LidarrRootFolder>>({ status: 'loading' });
  let profiles = $state<Loaded<LidarrQualityProfile>>({ status: 'loading' });

  // Mounted under {#key active.id}, so this runs once per instance.
  $effect(() => {
    api
      .lidarrRootFolders()
      .then((items) => (folders = { status: 'ok', items }))
      .catch((e: unknown) => (folders = { status: 'error', message: errorOf(e).message }));
    api
      .lidarrQualityProfiles()
      .then((items) => (profiles = { status: 'ok', items }))
      .catch((e: unknown) => (profiles = { status: 'error', message: errorOf(e).message }));
  });

  const NONE = -1;
  const PLACEHOLDER = { value: NONE, label: 'Select…' };

  function options<T extends { id: number }>(items: T[], label: (t: T) => string, selected: number | undefined) {
    const opts = items.map((t) => ({ value: t.id, label: label(t) }));
    return items.some((t) => t.id === selected) ? opts : [PLACEHOLDER, ...opts];
  }

  const folderOptions = $derived(
    folders.status === 'ok' ? options(folders.items, (f) => f.path, active.defaultRootFolderId) : [],
  );
  const profileOptions = $derived(
    profiles.status === 'ok' ? options(profiles.items, (p) => p.name, active.defaultQualityProfileId) : [],
  );
  const folderValue = $derived(
    folderOptions.some((o) => o.value === active.defaultRootFolderId) ? (active.defaultRootFolderId ?? NONE) : NONE,
  );
  const profileValue = $derived(
    profileOptions.some((o) => o.value === active.defaultQualityProfileId)
      ? (active.defaultQualityProfileId ?? NONE)
      : NONE,
  );

  /** Bumped on failed saves so the Selects re-mount showing the persisted value. */
  let rev = $state(0);

  async function save(patch: Partial<LidarrInstance>): Promise<void> {
    try {
      await api.lidarrUpdate({ ...active, ...patch }, null);
      onsaved();
    } catch (e) {
      rev++;
      toast(errorOf(e).message, { kind: 'error' });
    }
  }

  function pickFolder(id: number): void {
    if (folders.status !== 'ok') return;
    const f = folders.items.find((x) => x.id === id);
    if (f) void save({ defaultRootFolderId: f.id, defaultRootFolderPath: f.path });
  }

  function pickProfile(id: number): void {
    if (profiles.status !== 'ok') return;
    const p = profiles.items.find((x) => x.id === id);
    if (p) void save({ defaultQualityProfileId: p.id, defaultQualityProfileName: p.name });
  }
</script>

<div class="row">
  <span class="row-label">Root folder</span>
  {#if folders.status === 'loading'}
    <Spinner size={16} stroke={1.5} />
  {:else if folders.status === 'error'}
    <span class="error">{folders.message}</span>
  {:else}
    {#key `${folderValue}:${rev}`}
      <Select value={folderValue} options={folderOptions} onchange={pickFolder} />
    {/key}
  {/if}
</div>
<div class="row">
  <span class="row-label">Quality profile</span>
  {#if profiles.status === 'loading'}
    <Spinner size={16} stroke={1.5} />
  {:else if profiles.status === 'error'}
    <span class="error">{profiles.message}</span>
  {:else}
    {#key `${profileValue}:${rev}`}
      <Select value={profileValue} options={profileOptions} onchange={pickProfile} />
    {/key}
  {/if}
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 28px;
    margin-bottom: 12px;
  }
  .row-label {
    width: 120px;
    flex: none;
    font-size: 13px;
    color: var(--color-text-secondary);
  }
  .error {
    font-size: 11px;
    color: #ff5252;
    user-select: text;
    -webkit-user-select: text;
  }
</style>
