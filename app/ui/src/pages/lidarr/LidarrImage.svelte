<script lang="ts">
  import Icon from '../../widgets/Icon.svelte';
  import type { IconName } from '../../widgets/icons';

  /** Remote Lidarr artwork with a placeholder for missing/broken URLs. */
  let {
    url,
    size,
    radius,
    icon,
    iconSize,
  }: { url: string | null; size: number; radius: number; icon: IconName; iconSize: number } = $props();

  let failed = $state(false);

  $effect(() => {
    void url;
    failed = false;
  });
</script>

<span class="img" style:width="{size}px" style:height="{size}px" style:border-radius="{radius}px">
  {#if url && !failed}
    <img src={url} alt="" loading="lazy" decoding="async" draggable="false" onerror={() => (failed = true)} />
  {:else}
    <Icon name={icon} size={iconSize} />
  {/if}
</span>

<style>
  .img {
    flex: none;
    display: grid;
    place-items: center;
    overflow: hidden;
    background: var(--color-surface-variant);
    color: var(--color-text-secondary);
  }
  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
</style>
