<script lang="ts">
  import type { Snippet } from 'svelte';
  import VirtualGrid from '../VirtualGrid.svelte';
  import type { Album } from '../../lib/types';
  import AlbumCard from './AlbumCard.svelte';
  import { libraryStatus } from './status.svelte';

  /**
   * Album grid (SliverGridDelegateWithMaxCrossAxisExtent, albumCardSize + 16). Either a
   * static `albums` list or a lazily loaded one via `count` + `get` + `onRangeChange`.
   */
  let {
    albums,
    count,
    get,
    onRangeChange,
    plain = false,
    header,
  }: {
    albums?: Album[];
    count?: number;
    get?: (index: number) => Album | null;
    onRangeChange?: (start: number, end: number) => void;
    plain?: boolean;
    header?: Snippet;
  } = $props();

  $effect(() => {
    if (!plain) return libraryStatus.watchAlbumSync();
  });

  const n = $derived(albums?.length ?? count ?? 0);
  const at = (i: number): Album | null => (albums ? (albums[i] ?? null) : (get?.(i) ?? null));
</script>

<VirtualGrid count={n} maxExtent={196} extraHeight={44} {onRangeChange} {header}>
  {#snippet item(i: number, width: number)}
    <AlbumCard album={at(i)} {width} {plain} />
  {/snippet}
</VirtualGrid>
