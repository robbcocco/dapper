<script lang="ts">
  import CoverArt from '../../widgets/CoverArt.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import { player } from '../../lib/stores/player.svelte';
  import { starred } from '../../lib/stores/starred.svelte';
  import LyricsDialog from './LyricsDialog.svelte';
  import type { Song } from '../../lib/types';

  const song = $derived(player.state.currentSong);
  const isStarred = $derived(song !== null && starred.has(song.id));
  let lyricsFor = $state<Song | null>(null);
</script>

<div class="now-playing">
  <CoverArt coverArtId={song?.coverArtId} size={88} radius={6} display="44px" />
  <div class="text">
    <span class="title" class:playing={song !== null}>{song?.title ?? 'Not Playing'}</span>
    {#if song?.artist}
      <span class="artist">{song.artist}</span>
    {/if}
  </div>
  {#if song}
    <div class="glyphs">
      <button
        class="glyph"
        class:starred={isStarred}
        title={isStarred ? 'Unstar' : 'Star'}
        onclick={() => void starred.toggle(song.id)}
      >
        <Icon name={isStarred ? 'heart' : 'heart_border'} size={14} />
      </button>
      <button class="glyph lyrics" title="Lyrics" onclick={() => (lyricsFor = song)}>
        <Icon name="lyrics" size={14} />
      </button>
    </div>
  {/if}
</div>

{#if lyricsFor}
  <LyricsDialog song={lyricsFor} onclose={() => (lyricsFor = null)} />
{/if}

<style>
  .now-playing {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px;
    min-width: 0;
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .title,
  .artist {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .title.playing {
    font-weight: 600;
    color: var(--color-text-primary);
  }
  .artist {
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .glyph {
    flex: none;
    background: none;
    border: none;
    padding: 4px 6px;
    display: grid;
    place-items: center;
    color: color-mix(in srgb, var(--color-text-secondary) 45%, transparent);
  }
  .glyphs {
    flex: none;
    display: flex;
  }
  .glyph.starred {
    color: #ff4081;
  }
  .glyph.lyrics {
    color: color-mix(in srgb, var(--color-text-secondary) 60%, transparent);
  }
  .glyph:hover {
    color: var(--color-text-primary);
  }
  .glyph.starred:hover {
    color: #ff4081;
  }
</style>
