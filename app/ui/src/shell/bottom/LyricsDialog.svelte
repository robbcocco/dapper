<script lang="ts" module>
  import type { Lyrics } from '../../lib/types';

  // lyricsProvider is a non-disposing family: reopening the dialog for a song is instant.
  const cache = new Map<string, Lyrics | null>();
</script>

<script lang="ts">
  import { tick } from 'svelte';
  import Dialog from '../../widgets/Dialog.svelte';
  import Button from '../../widgets/Button.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import { lyricsGet } from '../../lib/api';
  import { player } from '../../lib/stores/player.svelte';
  import { session } from '../../lib/stores/session.svelte';
  import type { Song } from '../../lib/types';

  let { song, onclose }: { song: Song; onclose: () => void } = $props();

  type Load = { kind: 'loading' } | { kind: 'error'; error: unknown } | { kind: 'data'; lyrics: Lyrics | null };

  const key = $derived(`${session.serverId ?? ''}\u0000${song.id}`);
  let load = $state<Load>({ kind: 'loading' });
  let attempt = $state(0);

  $effect(() => {
    void attempt;
    const k = key;
    const id = song.id;
    if (cache.has(k)) {
      load = { kind: 'data', lyrics: cache.get(k) ?? null };
      return;
    }
    let live = true;
    load = { kind: 'loading' };
    lyricsGet(id).then(
      (lyrics) => {
        cache.set(k, lyrics);
        if (live) load = { kind: 'data', lyrics };
      },
      (error: unknown) => {
        if (live) load = { kind: 'error', error };
      },
    );
    return () => {
      live = false;
    };
  });

  const lyrics = $derived(load.kind === 'data' ? load.lyrics : null);
  const isCurrent = $derived(player.state.currentSong?.id === song.id);

  /** Index of the last line whose start is ≤ position; -1 when this song isn't playing. */
  const active = $derived.by(() => {
    if (!lyrics?.synced || !isCurrent) return -1;
    const pos = player.position.positionMs;
    let idx = -1;
    for (let i = 0; i < lyrics.lines.length; i++) {
      const s = lyrics.lines[i]!.startMs;
      if (s === null) continue;
      if (s <= pos) idx = i;
      else break;
    }
    return idx;
  });

  let scroller = $state<HTMLDivElement>();

  // Keep the active line a third from the top so upcoming lyrics stay visible.
  $effect(() => {
    const i = active;
    const el = scroller;
    if (i < 0 || !el) return;
    void tick().then(() => {
      const line = el.children[i];
      if (!(line instanceof HTMLElement)) return;
      el.scrollTo({ top: line.offsetTop - el.clientHeight / 3, behavior: 'smooth' });
    });
  });
</script>

<Dialog width={480} {onclose}>
  <div class="lyrics">
    <div class="title">{song.title}</div>
    {#if song.artist}<div class="artist">{song.artist}</div>{/if}
    <hr />
    <div class="content">
      {#if load.kind === 'loading'}
        <div class="center"><Spinner /></div>
      {:else if load.kind === 'error'}
        <div class="center"><ErrorRetry error={load.error} onRetry={() => (cache.delete(key), attempt++)} compact /></div>
      {:else if lyrics === null || lyrics.lines.length === 0}
        <div class="center empty">No lyrics available for this track.</div>
      {:else if lyrics.synced}
        <div class="scroll synced" bind:this={scroller}>
          {#each lyrics.lines as line, i (i)}
            <!-- Blank rows keep their height so instrumental gaps stay visible. -->
            <div class="line" class:active={i === active}>{line.text === '' ? '\u00a0' : line.text}</div>
          {/each}
        </div>
      {:else}
        <div class="scroll plain">{lyrics.lines.map((l) => l.text).join('\n')}</div>
      {/if}
    </div>
  </div>
  {#snippet footer()}
    <Button variant="text" onclick={onclose}>Close</Button>
  {/snippet}
</Dialog>

<style>
  .lyrics {
    height: min(472px, calc(100vh - 136px));
    display: flex;
    flex-direction: column;
  }
  .title {
    font-size: 15px;
    font-weight: 600;
    color: var(--color-text-primary);
  }
  .artist {
    margin-top: 2px;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  hr {
    margin: 14px 0 0;
    border: none;
    border-top: 1px solid var(--color-glass-border);
    flex: none;
  }
  .content {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .center {
    flex: 1;
    display: grid;
    place-items: center;
  }
  .empty {
    font-size: 13px;
    color: var(--color-text-secondary);
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 14px 0;
    line-height: 1.55;
    user-select: text;
    -webkit-user-select: text;
  }
  .plain {
    white-space: pre-wrap;
    font-size: 13px;
    color: var(--color-text-primary);
  }
  .synced {
    position: relative;
  }
  .line {
    padding: 4px 0;
    font-size: 13px;
    color: var(--color-text-secondary);
    transition:
      color 0.15s,
      font-size 0.15s;
  }
  .line.active {
    font-size: 14px;
    font-weight: 600;
    color: var(--color-text-primary);
  }
</style>
