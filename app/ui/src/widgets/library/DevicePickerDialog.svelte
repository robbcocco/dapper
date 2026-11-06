<script lang="ts">
  import Dialog from '../Dialog.svelte';
  import Icon from '../Icon.svelte';
  import type { ConnectedDevice } from '../../lib/types';

  /** "Choose device" SimpleDialog from albums_page.dart `_pickDevicePath`. */
  let { devices, onresult }: { devices: ConnectedDevice[]; onresult: (path: string | null) => void } = $props();
</script>

<Dialog title="Choose device" width={320} onclose={() => onresult(null)}>
  {#each devices as d (d.path)}
    <button type="button" class="opt" onclick={() => onresult(d.path)}>
      <Icon name="usb" size={16} />
      <span>{d.label}</span>
    </button>
  {/each}
</Dialog>

<style>
  .opt {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 10px 6px;
    border: none;
    border-radius: 6px;
    background: none;
    font: inherit;
    color: var(--color-text-primary);
    text-align: left;
  }
  .opt:hover {
    background: rgba(255, 255, 255, 0.05);
  }
</style>
