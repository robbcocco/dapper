<script lang="ts">
  import Icon from '../../widgets/Icon.svelte';

  /** Remote Lidarr poster / cover with the album (or round person) placeholder on miss. */
  let { url, size, person = false }: { url: string | null; size: number; person?: boolean } = $props();

  let failed = $state(false);
  $effect(() => {
    void url;
    failed = false;
  });
</script>

<span class="cover" class:person style:width="{size}px" style:height="{size}px">
  {#if url && !failed}
    <img src={url} alt="" loading="lazy" draggable="false" onerror={() => (failed = true)} />
  {:else}
    <Icon name={person ? 'person' : 'album'} size={Math.round(size / 2)} />
  {/if}
</span>

<style>
  .cover {
    flex: none;
    display: grid;
    place-items: center;
    overflow: hidden;
    border-radius: 4px;
    background: var(--color-surface-variant);
    color: var(--color-text-secondary);
  }
  .person {
    border-radius: 50%;
  }
  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
</style>
