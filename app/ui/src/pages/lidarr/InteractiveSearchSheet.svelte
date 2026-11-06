<script lang="ts">
  import * as api from '../../lib/api';
  import type { LidarrRelease } from '../../lib/types';
  import { toast } from '../../lib/stores/toast.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { errorOf } from '../settings/connection';
  import { formatReleaseSize } from './lidarr-filters';

  /** Manual release search + grab for one Lidarr album (_InteractiveSearchSheet). */
  let { albumId, albumTitle, onclose }: { albumId: number; albumTitle: string; onclose: () => void } = $props();

  /** Fits a two-line title, the meta line and one rejections line. */
  const ROW_HEIGHT = 88;

  let releases = $state<LidarrRelease[] | null>(null);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let grabbingGuid = $state<string | null>(null);
  let grabbed = $state(new Set<string>());
  /** Sheet height as a fraction of the window (DraggableScrollableSheet 0.65 → max 0.92). */
  let fraction = $state(0.65);
  let panel = $state<HTMLDivElement>();

  async function fetchReleases(): Promise<void> {
    loading = true;
    error = null;
    try {
      const list = await api.lidarrReleases(albumId);
      list.sort((a, b) => {
        if (a.rejected !== b.rejected) return a.rejected ? 1 : -1;
        return (b.seeders ?? 0) - (a.seeders ?? 0);
      });
      releases = list;
    } catch (e) {
      error = errorOf(e).message;
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    void fetchReleases();
  });

  $effect(() => {
    panel?.focus();
  });

  async function grab(r: LidarrRelease): Promise<void> {
    grabbingGuid = r.guid;
    try {
      await api.lidarrGrab(r);
      grabbed = new Set(grabbed).add(r.guid);
    } catch (e) {
      toast(`Grab failed: ${errorOf(e).message}`, { kind: 'error' });
    } finally {
      grabbingGuid = null;
    }
  }

  function meta(r: LidarrRelease): string {
    const parts = [r.indexer];
    if (r.quality !== '') parts.push(r.quality);
    parts.push(formatReleaseSize(r.size), `${r.ageInDays}d`);
    if (r.protocol === 'torrent' && r.seeders !== null) parts.push(`${r.seeders}↑`);
    return parts.join(' · ');
  }

  function onkeydown(e: KeyboardEvent): void {
    // Keep app shortcuts from firing behind the sheet.
    e.stopPropagation();
    if (e.key === 'Escape') {
      e.preventDefault();
      onclose();
    }
  }

  function startDrag(e: PointerEvent): void {
    const handle = e.currentTarget as HTMLElement;
    handle.setPointerCapture(e.pointerId);
    const move = (ev: PointerEvent): void => {
      const f = (window.innerHeight - ev.clientY) / window.innerHeight;
      if (f < 0.25) {
        handle.removeEventListener('pointermove', move);
        onclose();
        return;
      }
      fraction = Math.min(0.92, f);
    };
    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', () => handle.removeEventListener('pointermove', move), { once: true });
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
<div class="backdrop" onclick={(e) => e.target === e.currentTarget && onclose()} {onkeydown}>
  <div
    class="sheet"
    bind:this={panel}
    role="dialog"
    aria-modal="true"
    aria-label={albumTitle}
    tabindex="-1"
    style:height="{fraction * 100}vh"
  >
    <div class="grip" onpointerdown={startDrag}><span></span></div>
    <div class="head">
      <Icon name="search" size={16} color="var(--color-text-secondary)" />
      <span class="title">{albumTitle}</span>
      {#if !loading}
        <IconButton icon="refresh" size={16} label="Refresh" color="var(--color-text-secondary)" onclick={() => void fetchReleases()} />
      {/if}
    </div>
    <div class="body">
      {#if loading}
        <div class="center"><Spinner size={28} /></div>
      {:else if error !== null}
        <div class="center"><p class="error">{error}</p></div>
      {:else if !releases || releases.length === 0}
        <div class="center"><p class="none">No results found from indexers.</p></div>
      {:else}
        {@const list = releases}
        <VirtualList count={list.length} rowHeight={ROW_HEIGHT} paddingTop={8}>
          {#snippet row(i)}
            {@const r = list[i]!}
            <div class="release" class:rejected={r.rejected} class:first={i === 0}>
              <span class="proto"><Icon name={r.protocol === 'torrent' ? 'sync' : 'cloud_download'} size={14} /></span>
              <div class="text">
                <div class="rtitle" title={r.title}>{r.title}</div>
                <div class="meta">{meta(r)}</div>
                {#if r.rejections.length > 0}
                  <div class="rejections" title={r.rejections.join('\n')}>{r.rejections.join(' · ')}</div>
                {/if}
              </div>
              <div class="action">
                {#if grabbed.has(r.guid)}
                  <Icon name="check_circle" size={18} color="#4caf50" />
                {:else if grabbingGuid === r.guid}
                  <Spinner size={16} stroke={1.5} />
                {:else}
                  <button type="button" class="grab" disabled={r.rejected} onclick={() => void grab(r)}>Grab</button>
                {/if}
              </div>
            </div>
          {/snippet}
        </VirtualList>
      {/if}
    </div>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(0, 0, 0, 0.45);
    display: flex;
    align-items: flex-end;
    justify-content: center;
  }
  .sheet {
    width: min(100%, 860px);
    display: flex;
    flex-direction: column;
    background: var(--color-surface);
    border: 1px solid var(--color-glass-border);
    border-bottom: none;
    border-radius: 16px 16px 0 0;
    box-shadow: 0 -10px 40px rgba(0, 0, 0, 0.4);
    outline: none;
  }
  .grip {
    display: grid;
    place-items: center;
    padding: 12px 0 10px;
    cursor: ns-resize;
    touch-action: none;
  }
  .grip span {
    width: 36px;
    height: 4px;
    border-radius: 2px;
    background: rgba(142, 142, 147, 0.3);
  }
  .head {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 36px;
    padding: 0 16px 4px 20px;
    border-bottom: 1px solid var(--color-glass-border);
  }
  .title {
    flex: 1;
    min-width: 0;
    font-size: 15px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
    padding: 24px;
  }
  .error {
    margin: 0;
    color: #ff5252;
    font-size: 12px;
    user-select: text;
    -webkit-user-select: text;
  }
  .none {
    margin: 0;
    color: var(--color-text-secondary);
    font-size: 13px;
  }
  .release {
    height: 100%;
    display: flex;
    align-items: flex-start;
    gap: 10px;
    padding: 10px 12px 10px 20px;
    border-top: 1px solid var(--color-glass-border);
    overflow: hidden;
  }
  .release.first {
    border-top: none;
  }
  .release.rejected {
    background: rgba(244, 67, 54, 0.04);
  }
  .proto {
    padding-top: 2px;
    color: var(--color-text-secondary);
  }
  .rejected .proto {
    opacity: 0.4;
  }
  .text {
    flex: 1;
    min-width: 0;
  }
  .rtitle {
    font-size: 12px;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    user-select: text;
    -webkit-user-select: text;
  }
  .rejected .rtitle {
    color: rgba(142, 142, 147, 0.5);
  }
  .meta {
    margin-top: 3px;
    font-size: 11px;
    color: rgba(142, 142, 147, 0.8);
  }
  .rejected .meta {
    color: rgba(142, 142, 147, 0.4);
  }
  .rejections {
    margin-top: 3px;
    font-size: 10px;
    color: #ff5252;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .action {
    width: 56px;
    flex: none;
    display: grid;
    place-items: center;
    min-height: 28px;
  }
  .grab {
    min-width: 48px;
    height: 28px;
    padding: 0 6px;
    border: none;
    border-radius: 6px;
    background: var(--color-accent);
    color: #fff;
    font: inherit;
    font-size: 11px;
  }
  .grab:not(:disabled):hover {
    filter: brightness(1.15);
  }
  .grab:disabled {
    background: var(--color-surface-variant);
    color: var(--color-text-secondary);
  }
</style>
