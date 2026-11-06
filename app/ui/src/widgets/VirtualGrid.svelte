<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import { createVirtualizer } from '@tanstack/svelte-virtual';

  /**
   * Virtualized responsive grid (SliverGridDelegateWithMaxCrossAxisExtent). Columns =
   * ceil(available / (maxExtent + gap)); each cell is `itemWidth` wide and
   * `itemWidth + extraHeight` tall (square cover + caption). Rows are virtualized;
   * `onRangeChange(start, end)` reports item indices (end exclusive).
   */
  let {
    count,
    item,
    maxExtent = 200,
    extraHeight = 44,
    gap = 16,
    padding = 24,
    onRangeChange,
    overscan = 3,
    header,
  }: {
    count: number;
    item: Snippet<[number, number]>;
    maxExtent?: number;
    extraHeight?: number;
    gap?: number;
    padding?: number;
    onRangeChange?: (start: number, end: number) => void;
    overscan?: number;
    header?: Snippet;
  } = $props();

  let scrollEl = $state<HTMLDivElement>();
  let width = $state(0);
  let headerHeight = $state(0);

  const avail = $derived(Math.max(0, width - padding * 2));
  const columns = $derived(Math.max(1, Math.ceil((avail + gap) / (maxExtent + gap))));
  const itemWidth = $derived(Math.max(0, (avail - gap * (columns - 1)) / columns));
  const rowHeight = $derived(itemWidth + extraHeight + gap);
  const rows = $derived(Math.ceil(count / columns));

  const virtualizer = createVirtualizer<HTMLDivElement, HTMLDivElement>({
    count: 0,
    getScrollElement: () => scrollEl ?? null,
    estimateSize: () => 240,
  });

  // Untracked: measure() republishes the store, which would re-run this effect forever.
  $effect(() => {
    const h = rowHeight;
    const opts = { count: rows, estimateSize: () => h, overscan, scrollMargin: headerHeight + padding };
    untrack(() => {
      $virtualizer.setOptions(opts);
      $virtualizer.measure();
    });
  });

  // The virtualizer learns a shrunken count one effect later; never render rows past it.
  const vrows = $derived($virtualizer.getVirtualItems().filter((r) => r.index < rows));

  let lastRange = '';
  $effect(() => {
    if (!onRangeChange || vrows.length === 0) return;
    const start = vrows[0]!.index * columns;
    const end = Math.min(count, (vrows[vrows.length - 1]!.index + 1) * columns);
    const key = `${start}:${end}:${count}`;
    if (key === lastRange) return;
    lastRange = key;
    onRangeChange(start, end);
  });

  export function scrollToIndex(index: number, align: 'start' | 'center' | 'end' | 'auto' = 'auto'): void {
    $virtualizer.scrollToIndex(Math.floor(index / columns), { align });
  }
  export function scrollToTop(): void {
    scrollEl?.scrollTo({ top: 0 });
  }
</script>

<div class="vg" bind:this={scrollEl} bind:clientWidth={width} style:padding-top="{padding}px">
  {#if header}<div bind:clientHeight={headerHeight}>{@render header()}</div>{/if}
  <div class="inner" style:height="{$virtualizer.getTotalSize()}px">
    {#each vrows as r (r.key)}
      <div
        class="row"
        style:transform="translateY({r.start - $virtualizer.options.scrollMargin}px)"
        style:padding="0 {padding}px"
        style:gap="{gap}px"
        style:grid-template-columns="repeat({columns}, {itemWidth}px)"
      >
        {#each { length: Math.min(columns, count - r.index * columns) } as _, c (c)}
          <div style:height="{itemWidth + extraHeight}px">{@render item(r.index * columns + c, itemWidth)}</div>
        {/each}
      </div>
    {/each}
  </div>
  <div class="inset"></div>
</div>

<style>
  .vg {
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
    display: grid;
  }
  .inset {
    height: var(--scroll-bottom-inset);
  }
</style>
