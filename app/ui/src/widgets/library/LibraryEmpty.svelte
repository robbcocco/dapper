<script lang="ts">
  import EmptyState from '../EmptyState.svelte';
  import Spinner from '../Spinner.svelte';
  import type { IconName } from '../icons';
  import { librarySync } from '../../lib/stores/library-sync.svelte';

  /** Empty library view; says "syncing" instead while the first cache sync is still running. */
  let { icon, title, message }: { icon?: IconName; title: string; message?: string } = $props();
</script>

{#if librarySync.firstSync}
  <div class="syncing">
    <Spinner />
    <div class="title">Syncing your library…</div>
    <div class="msg">This only takes a while the first time.</div>
  </div>
{:else}
  <EmptyState {icon} {title} {message} />
{/if}

<style>
  .syncing {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    color: var(--color-text-secondary);
  }
  .title {
    font-size: 15px;
    color: var(--color-text-primary);
  }
  .msg {
    font-size: 12px;
  }
</style>
