<script lang="ts">
  import { untrack, type Snippet } from 'svelte';
  import { createVirtualizer } from '@tanstack/svelte-virtual';

  /**
   * Virtualized list whose rows have known but differing heights (e.g. album headers
   * mixed with song rows). Same contract as VirtualList otherwise.
   */
  let {
    count,
    rowHeight,
    row,
    onRangeChange,
    overscan = 8,
    header,
  }: {
    count: number;
    rowHeight: (index: number) => number;
    row: Snippet<[number]>;
    onRangeChange?: (start: number, end: number) => void;
    overscan?: number;
    header?: Snippet;
  } = $props();

  let scrollEl = $state<HTMLDivElement>();
  let headerHeight = $state(0);

  const virtualizer = createVirtualizer<HTMLDivElement, HTMLDivElement>({
    count: 0,
    getScrollElement: () => scrollEl ?? null,
    estimateSize: () => 40,
  });

  // Heights are read here so row-shape changes re-measure; the store update itself is
  // untracked because measure() republishes it, which would re-run this effect forever.
  $effect(() => {
    const sizes = Array.from({ length: count }, (_, i) => rowHeight(i));
    const opts = { count, estimateSize: (i: number) => sizes[i] ?? 40, overscan, scrollMargin: headerHeight };
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
</script>

<div class="vl" bind:this={scrollEl}>
  {#if header}<div bind:clientHeight={headerHeight}>{@render header()}</div>{/if}
  <div class="inner" style:height="{$virtualizer.getTotalSize()}px">
    {#each items as it (it.key)}
      <div class="row" style:height="{it.size}px" style:transform="translateY({it.start - $virtualizer.options.scrollMargin}px)">
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
