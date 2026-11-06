<script lang="ts">
  import Icon from './Icon.svelte';
  import { coverUrl } from '../lib/api';
  import { session } from '../lib/stores/session.svelte';

  /** `size` is the requested server size and default display size (cover_art_image.dart). */
  let {
    coverArtId,
    size = 256,
    radius = 4,
    display,
  }: { coverArtId: string | null | undefined; size?: number; radius?: number; display?: string } = $props();

  let failed = $state(false);
  const src = $derived(coverArtId && session.serverId ? coverUrl(session.serverId, coverArtId, size) : null);
  $effect(() => {
    void src;
    failed = false;
  });
  const dim = $derived(display ?? `${size}px`);
</script>

<div class="cover" style:width={dim} style:height={dim} style:border-radius="{radius}px">
  {#if src && !failed}
    <img {src} alt="" loading="lazy" decoding="async" draggable="false" onerror={() => (failed = true)} />
  {:else}
    <Icon name="album" size={Math.max(16, Math.min(48, Math.round(size / 4)))} />
  {/if}
</div>

<style>
  .cover {
    flex: none;
    overflow: hidden;
    background: var(--color-surface-variant);
    color: var(--color-text-secondary);
    display: grid;
    place-items: center;
  }
  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
</style>
