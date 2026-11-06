<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import { createVirtualizer } from '@tanstack/svelte-virtual';

  /**
   * Fixed-height virtualized list. `onRangeChange(start, end)` reports the visible (+overscan)
   * index range, end exclusive, so pages can fetch windows lazily. Bottom inset clears the
   * floating bottom bar.
   */
  let {
    count,
    rowHeight,
    row,
    onRangeChange,
    overscan = 10,
    header,
    paddingTop = 0,
  }: {
    count: number;
    rowHeight: number;
    row: Snippet<[number]>;
    onRangeChange?: (start: number, end: number) => void;
    overscan?: number;
    /** Non-virtualized content scrolled above the rows (e.g. album header). */
    header?: Snippet;
    paddingTop?: number;
  } = $props();

  let scrollEl = $state<HTMLDivElement>();
  let headerHeight = $state(0);

  const virtualizer = createVirtualizer<HTMLDivElement, HTMLDivElement>({
    count: 0,
    getScrollElement: () => scrollEl ?? null,
    estimateSize: () => 40,
  });

  // Untracked: measure() republishes the store, which would re-run this effect forever.
  $effect(() => {
    const h = rowHeight;
    const opts = { count, estimateSize: () => h, overscan, scrollMargin: headerHeight + paddingTop };
    untrack(() => {
      $virtualizer.setOptions(opts);
      $virtualizer.measure();
    });
  });

  // The virtualizer learns a shrunken count one effect later; never render rows past it.
  const items = $derived($virtualizer.getVirtualItems().filter((it) => it.index < count));

  let lastRange = '';
  $effect(() => {
    if (!onRangeChange || items.length === 0) return;
    const start = items[0]!.index;
    const end = items[items.length - 1]!.index + 1;
    const key = `${start}:${end}:${count}`;
    if (key === lastRange) return;
    lastRange = key;
    onRangeChange(start, end);
  });

  export function scrollToIndex(index: number, align: 'start' | 'center' | 'end' | 'auto' = 'auto'): void {
    $virtualizer.scrollToIndex(index, { align });
  }
  export function scrollToTop(): void {
    scrollEl?.scrollTo({ top: 0 });
  }
</script>

<div class="vl" bind:this={scrollEl} style:padding-top="{paddingTop}px">
  {#if header}<div bind:clientHeight={headerHeight}>{@render header()}</div>{/if}
  <div class="inner" style:height="{$virtualizer.getTotalSize()}px">
    {#each items as it (it.key)}
      <div class="row" style:height="{rowHeight}px" style:transform="translateY({it.start - $virtualizer.options.scrollMargin}px)">
        {@render row(it.index)}
      </div>
    {/each}
  </div>
  <div class="inset"></div>
</div>

<style>
  .vl {
    height: 100%;
    overflow-y: auto;
    overflow-x: hidden;
    contain: strict;
  }
  .inner {
    position: relative;
    width: 100%;
  }
  .row {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
  }
  .inset {
    height: var(--scroll-bottom-inset);
  }
</style>
