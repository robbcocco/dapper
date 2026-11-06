<script lang="ts">
  // device_folder_picker_dialog.dart: folder-only tree scoped to the device; resolves the
  // chosen folder relative to the device root (slots into musicRootFolder), null on cancel.
  import { untrack } from 'svelte';
  import * as api from '../../lib/api';
  import Button from '../../widgets/Button.svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { musicRootParts } from '../../widgets/device/preview';
  import { DeviceTree } from '../../widgets/device/tree.svelte';

  let {
    devicePath,
    initialRelative = '',
    onResult,
  }: { devicePath: string; initialRelative?: string; onResult: (relative: string | null) => void } = $props();

  const tree = new DeviceTree('', '(device root)', (rel) => untrack(() => api.deviceListDirs(devicePath, rel)));
  void tree.toggle('');

  let selected = $state(untrack(() => musicRootParts(initialRelative).join('/')));
  const rows = $derived(tree.rows.filter((r) => r.entry === null || r.entry.isDir));
</script>

<Dialog title="Choose music folder" width={520} onclose={() => onResult(null)}>
  <div class="picker">
    <div class="current">{selected === '' ? '(device root)' : selected}</div>
    <div class="tree">
      <VirtualList count={rows.length} rowHeight={26} paddingTop={6}>
        {#snippet row(i)}
          {@const r = rows[i]}
          {#if r}
            {@const open = tree.expanded.has(r.rel)}
            <!-- svelte-ignore a11y_click_events_have_key_events -->
            <div
              class="node"
              class:sel={r.rel === selected}
              role="treeitem"
              aria-selected={r.rel === selected}
              aria-expanded={open}
              tabindex="-1"
              style:padding-left="{10 + r.depth * 14}px"
              onclick={() => (selected = r.rel)}
              ondblclick={() => void tree.toggle(r.rel)}
            >
              <button
                type="button"
                class="chev"
                aria-label={open ? 'Collapse' : 'Expand'}
                onclick={(e) => {
                  e.stopPropagation();
                  void tree.toggle(r.rel);
                }}
                ondblclick={(e) => e.stopPropagation()}
              >
                {#if tree.loading.has(r.rel)}
                  <Spinner size={12} stroke={1.5} />
                {:else}
                  <Icon name={open ? 'chevron_down' : 'chevron_right'} size={14} />
                {/if}
              </button>
              <Icon name="folder" size={14} color="var(--color-accent)" />
              <span class="name">{r.name}</span>
            </div>
          {/if}
        {/snippet}
      </VirtualList>
    </div>
  </div>
  {#snippet footer()}
    <Button variant="text" onclick={() => onResult(null)}>Cancel</Button>
    <Button variant="primary" onclick={() => onResult(selected)}>Select</Button>
  {/snippet}
</Dialog>

<style>
  .picker {
    height: 440px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .current {
    padding: 6px 10px;
    border-radius: 6px;
    background: var(--color-surface-variant);
    font-size: 12px;
    color: var(--color-text-primary);
    overflow-wrap: anywhere;
  }
  .tree {
    flex: 1;
    min-height: 0;
    border: 1px solid var(--color-glass-border);
    border-radius: 6px;
    overflow: hidden;
    --scroll-bottom-inset: 6px;
  }
  .node {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 4px;
    padding-right: 10px;
    font-size: 12px;
    color: var(--color-text-primary);
  }
  .node:hover {
    background: rgba(255, 255, 255, 0.04);
  }
  .sel,
  .sel:hover {
    background: rgba(10, 132, 255, 0.16);
  }
  .chev {
    width: 16px;
    display: grid;
    place-items: center;
    padding: 0;
    border: none;
    background: none;
    color: var(--color-text-secondary);
  }
  .name {
    margin-left: 2px;
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
