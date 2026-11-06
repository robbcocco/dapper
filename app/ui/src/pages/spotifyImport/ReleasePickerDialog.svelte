<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrRelease } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import ExtraIcon from '../../widgets/playlists/ExtraIcon.svelte';
  import MetaChip from './MetaChip.svelte';
  import { errMsg, formattedSize } from './lidarr';

  /**
   * Interactive release picker: every indexer hit for `albumId`, grab a specific one.
   * Mirrors the Lidarr page's interactive search, as a dialog inside the import flow.
   */
  let { albumId, albumTitle, onclose }: { albumId: number; albumTitle: string; onclose: () => void } = $props();

  let releases = $state<LidarrRelease[] | null>(null);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let grabbing = $state<string | null>(null);
  let grabbed = $state<ReadonlySet<string>>(new Set());

  async function fetchReleases(): Promise<void> {
    loading = true;
    error = null;
    try {
      const list = await api.lidarrReleases(albumId);
      // Approved + most-seeded first so the obvious pick floats up.
      list.sort((a, b) => (a.rejected !== b.rejected ? (a.rejected ? 1 : -1) : (b.seeders ?? 0) - (a.seeders ?? 0)));
      releases = list;
    } catch (e) {
      error = errMsg(e);
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    void fetchReleases();
  });

  async function grab(r: LidarrRelease): Promise<void> {
    grabbing = r.guid;
    try {
      await api.lidarrGrab(r);
      grabbed = new Set([...grabbed, r.guid]);
    } catch (e) {
      toast(`Grab failed: ${errMsg(e)}`, { kind: 'error' });
    } finally {
      grabbing = null;
    }
  }
</script>

<Dialog width={620} {onclose}>
  <div class="frame">
    <div class="head">
      <ExtraIcon name="manage_search" size={18} color="var(--color-text-secondary)" />
      <span class="title">{albumTitle}</span>
      {#if !loading}
        <IconButton label="Refresh" icon="refresh" size={16} color="var(--color-text-secondary)" onclick={() => void fetchReleases()} />
      {/if}
    </div>
    <div class="body">
      {#if loading}
        <div class="center"><Spinner size={28} /></div>
      {:else if error !== null}
        <div class="center"><span class="err">{error}</span></div>
      {:else if !releases || releases.length === 0}
        <div class="center"><span class="muted">No releases found from indexers.</span></div>
      {:else}
        {@const list = releases}
        <VirtualList count={list.length} rowHeight={68}>
          {#snippet row(i)}
          {@const r = list[i]!}
          <div class="rel">
            <div class="main">
              <div class="rtitle" class:rejected={r.rejected}>{r.title}</div>
              <div class="chips">
                <MetaChip label={r.indexer} />
                <MetaChip label={formattedSize(r)} />
                <MetaChip label={r.quality} />
                {#if r.protocol === 'torrent' && r.seeders !== null}
                  <MetaChip label="{r.seeders}↑ {r.leechers ?? 0}↓" />
                {/if}
                {#if r.ageInDays > 0}<MetaChip label="{r.ageInDays}d old" />{/if}
                {#if r.rejected}
                  <MetaChip label={r.rejections[0] ?? 'rejected'} color="#ffab40" />
                {/if}
              </div>
            </div>
            <span class="trail">
              {#if grabbed.has(r.guid)}
                <Icon name="check_circle" size={16} color="#4caf50" />
              {:else if grabbing === r.guid}
                <Spinner size={16} stroke={1.5} />
              {:else}
                <IconButton
                  label={r.rejected ? 'Grab anyway' : 'Grab this release'}
                  icon="download"
                  size={18}
                  color={r.rejected ? '#ffab40' : 'var(--color-accent)'}
                  onclick={() => void grab(r)}
                />
              {/if}
            </span>
          </div>
          {/snippet}
        </VirtualList>
      {/if}
    </div>
  </div>
  {#snippet footer()}
    <Button variant="text" onclick={onclose}>Close</Button>
  {/snippet}
</Dialog>

<style>
  .frame {
    display: flex;
    flex-direction: column;
    height: 470px;
    margin: -4px -22px 0;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 12px 8px 22px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 16px;
    font-weight: 700;
    color: var(--color-text-primary);
  }
  .body {
    --scroll-bottom-inset: 0px;
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
    padding: 24px;
    text-align: center;
  }
  .err {
    font-size: 12px;
    color: #ff5252;
  }
  .muted {
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .rel {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 22px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .main {
    flex: 1;
    min-width: 0;
  }
  .rtitle {
    font-size: 12px;
    color: var(--color-text-primary);
    display: -webkit-box;
    line-clamp: 2;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    word-break: break-word;
  }
  .rtitle.rejected {
    color: var(--color-text-secondary);
  }
  .chips {
    display: flex;
    flex-wrap: nowrap;
    overflow: hidden;
    gap: 2px 8px;
    margin-top: 4px;
  }
  .trail {
    display: grid;
    place-items: center;
    min-width: 30px;
  }
</style>
