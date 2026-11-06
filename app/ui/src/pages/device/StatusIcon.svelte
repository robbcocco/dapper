<script lang="ts">
  import Icon from '../../widgets/Icon.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import type { TransferStatus } from '../../lib/types';

  let { status }: { status: TransferStatus } = $props();
</script>

{#if status === 'queued'}
  <Icon name="schedule" size={16} color="var(--color-text-secondary)" />
{:else if status === 'inProgress'}
  <span class="spin"><Spinner size={16} /></span>
{:else if status === 'completed'}
  <Icon name="check_circle" size={16} color="#4caf50" />
{:else if status === 'failed'}
  <Icon name="error" size={16} color="#ff5252" />
{:else}
  <Icon name="cancel" size={16} color="var(--color-text-secondary)" />
{/if}

<style>
  .spin {
    display: inline-grid;
    flex: none;
  }
  .spin :global(.sp) {
    color: var(--color-accent);
  }
</style>
