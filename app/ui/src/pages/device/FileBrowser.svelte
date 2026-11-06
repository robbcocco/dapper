<script lang="ts">
  // "On Device" tab (device_file_browser.dart): expand-on-tap tree rooted at the music root.
  import { onDestroy, untrack } from 'svelte';
  import * as api from '../../lib/api';
  import type { DeviceEntry } from '../../lib/types';
  import Button from '../../widgets/Button.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { basename, musicRootParts, resolvedMusicRoot } from '../../widgets/device/preview';
  import { DeviceTree, type TreeRow } from '../../widgets/device/tree.svelte';

  let { devicePath, musicRootFolder }: { devicePath: string; musicRootFolder: string } = $props();

  const rootPath = $derived(resolvedMusicRoot(devicePath, musicRootFolder));
  const rootName = $derived(basename(rootPath) || rootPath);

  let generation = $state(0);

  // A new tree (collapsed to the root) whenever the root changes or Refresh is pressed.
  const tree = $derived.by(() => {
    void generation;
    const path = devicePath;
    return new DeviceTree(musicRootParts(musicRootFolder).join('/'), rootName, (rel) => api.deviceBrowse(path, rel));
  });

  $effect(() => {
    const t = tree;
    untrack(() => void t.toggle(t.root));
  });

  // Entries Dart renders as nothing (non-audio, non-playlist files) are skipped.
  const rows = $derived(tree.rows.filter((r) => r.entry === null || r.entry.kind !== 'other'));
  const rootError = $derived(tree.errors.get(tree.root));

  // Transfers and prunes change the device; re-list open folders without collapsing them.
  let unlisten: (() => void) | undefined;
  void api.onManifestRevision(() => void tree.reload()).then((u) => (unlisten = u));
  onDestroy(() => unlisten?.());

  function summary(entries: DeviceEntry[]): string {
    let dirs = 0;
    let tracks = 0;
    let playlists = 0;
    for (const e of entries) {
      if (e.isDir) dirs++;
      else if (e.kind === 'audio') tracks++;
      else if (e.kind === 'playlist') playlists++;
    }
    const parts: string[] = [];
    if (dirs > 0) parts.push(`${dirs} folder${dirs === 1 ? '' : 's'}`);
    if (tracks > 0) parts.push(`${tracks} track${tracks === 1 ? '' : 's'}`);
    if (playlists > 0) parts.push(`${playlists} playlist${playlists === 1 ? '' : 's'}`);
    return parts.join(', ');
  }

  function splitExt(name: string): [string, string] {
    const i = name.lastIndexOf('.');
    return i <= 0 ? [name, ''] : [name.slice(0, i), name.slice(i + 1)];
  }

  const indent = (r: TreeRow): string => `${16 + r.depth * 16}px`;
</script>

{#if rootError && tree.children.size === 0}
  <div class="missing">
    <Icon name="folder" size={36} color="var(--color-text-secondary)" />
    <div class="m-title">{rootError.kind === 'notFound' ? 'Folder not found on device' : rootError.message}</div>
    <div class="m-path">{rootPath}</div>
    <Button small icon="refresh" onclick={() => generation++}>Retry</Button>
  </div>
{:else}
  <div class="browser">
    <div class="toolbar">
      <span class="root">{rootName}</span>
      <IconButton icon="refresh" size={15} label="Refresh" color="var(--color-text-secondary)" onclick={() => generation++} />
    </div>
    <div class="tree">
      <VirtualList count={rows.length} rowHeight={24} paddingTop={8}>
        {#snippet row(i)}
          {@const r = rows[i]}
          {#if r}
            {#if r.entry === null || r.entry.isDir}
              {@const open = tree.expanded.has(r.rel)}
              {@const kids = tree.children.get(r.rel)}
              {@const err = tree.errors.get(r.rel)}
              <button type="button" class="dir" style:padding-left={indent(r)} onclick={() => void tree.toggle(r.rel)}>
                {#if tree.loading.has(r.rel)}
                  <span class="spin"><Spinner size={14} stroke={1.5} /></span>
                {:else}
                  <Icon name="folder" size={14} color="var(--color-accent)" />
                {/if}
                <span class="dir-name">{r.name}</span>
                {#if err}
                  <span title={err.message}><Icon name="error" size={12} color="#ff5252" /></span>
                {:else if open && kids}
                  <span class="summary">{summary(kids)}</span>
                {/if}
              </button>
            {:else}
              {@const [base, ext] = splitExt(r.name)}
              <div class="file" style:padding-left={indent(r)}>
                <Icon name={r.entry.kind === 'playlist' ? 'queue_music' : 'music_note'} size={12} />
                <span class="file-name">{base}</span>
                <span class="badge">{r.entry.kind === 'playlist' ? 'M3U' : ext.toUpperCase()}</span>
              </div>
            {/if}
          {/if}
        {/snippet}
      </VirtualList>
    </div>
  </div>
{/if}

<style>
  .browser {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .toolbar {
    display: flex;
    align-items: center;
    padding: 4px 8px 0 20px;
    border-bottom: 1px solid var(--color-divider);
  }
  .root {
    flex: 1;
    font-size: 10px;
    color: var(--color-text-secondary);
  }
  .tree {
    flex: 1;
    min-height: 0;
  }
  .dir,
  .file {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    gap: 6px;
    padding-right: 16px;
  }
  .dir {
    border: none;
    background: transparent;
    font: inherit;
    text-align: left;
    color: var(--color-text-primary);
  }
  .dir:hover {
    background: rgba(255, 255, 255, 0.04);
  }
  .spin :global(.sp) {
    display: block;
  }
  .dir-name,
  .file-name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .dir-name {
    font-size: 12px;
    font-weight: 500;
  }
  .summary {
    font-size: 10px;
    color: var(--color-text-secondary);
  }
  .file {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .badge {
    padding: 1px 4px;
    border-radius: 3px;
    background: var(--color-surface-variant);
    font-size: 9px;
  }
  .missing {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    color: var(--color-text-secondary);
  }
  .m-title {
    margin-top: 8px;
    font-size: 13px;
  }
  .m-path {
    margin-bottom: 12px;
    font-size: 10px;
  }
</style>
