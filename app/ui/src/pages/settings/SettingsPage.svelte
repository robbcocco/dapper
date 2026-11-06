<script lang="ts">
  import Tabs from '../../widgets/Tabs.svelte';
  import DevicesTab from './DevicesTab.svelte';
  import GeneralTab from './GeneralTab.svelte';
  import LidarrTab from './LidarrTab.svelte';
  import NavidromeTab from './NavidromeTab.svelte';

  type Tab = 'general' | 'navidrome' | 'lidarr' | 'devices';

  const TABS = [
    { value: 'general', label: 'General' },
    { value: 'navidrome', label: 'Navidrome' },
    { value: 'lidarr', label: 'Lidarr' },
    { value: 'devices', label: 'Devices' },
  ] as const satisfies readonly { value: Tab; label: string }[];

  let tab = $state<Tab>('general');
</script>

<section class="page">
  <header>
    <Tabs bind:value={tab} tabs={TABS} />
  </header>
  <div class="body">
    {#if tab === 'general'}
      <GeneralTab />
    {:else if tab === 'navidrome'}
      <NavidromeTab />
    {:else if tab === 'lidarr'}
      <LidarrTab />
    {:else}
      <DevicesTab />
    {/if}
  </div>
</section>

<style>
  .page {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  header {
    flex: none;
    display: flex;
    justify-content: center;
    padding: 12px 24px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .body {
    flex: 1;
    min-height: 0;
    overflow: auto;
  }
</style>
