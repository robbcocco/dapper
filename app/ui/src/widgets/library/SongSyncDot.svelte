<script lang="ts">
  import SyncDot from '../SyncDot.svelte';
  import { libraryStatus } from './status.svelte';

  /** Song row trailing dot: blue (pulsing while transferring) when queued, else green when on the selected device. */
  let { songId, onDevice }: { songId: string; onDevice: boolean } = $props();

  const q = $derived(libraryStatus.songQueue(songId));
</script>

{#if q.active || q.queued}
  <span class="slot"><SyncDot state="queued" pulse={q.active} /></span>
{:else if onDevice}
  <span class="slot"><SyncDot state="full" /></span>
{/if}

<style>
  .slot {
    display: inline-flex;
    margin-right: 6px;
  }
</style>
