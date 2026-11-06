<script lang="ts">
  import * as api from '../../lib/api';
  import type { ImportState } from '../../lib/types';
  import { SidebarSection, selectedSection } from '../../lib/stores/navigation.svelte';
  import { playlists } from '../../lib/stores/playlists.svelte';
  import { attempt } from '../../widgets/library/actions';
  import Button from '../../widgets/Button.svelte';
  import Icon from '../../widgets/Icon.svelte';
  import ProgressBar from '../../widgets/ProgressBar.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import TextField from '../../widgets/TextField.svelte';
  import ExtraIcon from '../../widgets/playlists/ExtraIcon.svelte';
  import ReviewView from './ReviewView.svelte';

  let imp = $state<ImportState | null>(null);

  $effect(() => {
    let pushed = false;
    const un = api.onImportState((s) => {
      pushed = true;
      imp = s;
      // The created playlist should show up in the sidebar right away.
      if (s.kind === 'done') playlists.invalidate();
    });
    api
      .importState()
      .then((s) => {
        // An event that raced the initial fetch is newer; keep it.
        if (!pushed) imp = s;
      })
      .catch((e: unknown) => {
        if (!pushed) imp = { kind: 'error', message: e instanceof Error ? e.message : String(e), tracks: null };
      });
    return () => void un.then((f) => f());
  });

  let url = $state('');
  const valid = $derived(url.trim() !== '');

  function start(): void {
    const text = url.trim();
    if (text === '') return;
    void attempt(api.importStart(text));
  }

  const reset = (): void => void attempt(api.importReset());
</script>

<section class="page">
  {#if imp === null}
    <div class="center"><Spinner size={28} /></div>
  {:else if imp.kind === 'idle'}
    <div class="idle">
      <h1>Import from a playlist</h1>
      <p class="lead">
        Paste a public Spotify or Tidal playlist link. Dapper scrapes the track list and matches each song against your
        Navidrome library — you can fix any misses before the playlist is created.
      </p>
      <form
        class="url"
        onsubmit={(e) => {
          e.preventDefault();
          start();
        }}
      >
        <TextField bind:value={url} placeholder="open.spotify.com/playlist/… or tidal.com/playlist/…" autofocus />
      </form>
      <div class="row">
        <Button variant="primary" icon="cloud_download" disabled={!valid} onclick={start}>Import</Button>
        <Button variant="text" onclick={() => (selectedSection.value = SidebarSection.playlists)}>Cancel</Button>
      </div>
      <div class="info">
        <ExtraIcon name="info_outline" size={14} color="var(--color-text-secondary)" />
        <span
          >Only public playlists work. Spotify caps embedded playlists at the first ~100 tracks; Tidal returns the full list. The
          importer warns you if it sees a truncated list.</span
        >
      </div>
    </div>
  {:else if imp.kind === 'scraping' || imp.kind === 'creating'}
    <div class="center">
      <div class="stack">
        <Spinner size={28} />
        <span class="msg">{imp.kind === 'scraping' ? 'Fetching playlist from Spotify…' : 'Creating Navidrome playlist…'}</span>
      </div>
    </div>
  {:else if imp.kind === 'matching'}
    <div class="center">
      <div class="stack">
        <span class="heading">{imp.playlistName}</span>
        <div class="bar"><ProgressBar value={imp.total === 0 ? 0 : imp.done / imp.total} height={4} /></div>
        <span class="small">Matching {imp.done} of {imp.total} tracks…</span>
      </div>
    </div>
  {:else if imp.kind === 'review'}
    <ReviewView playlistName={imp.playlistName} truncated={imp.truncated} matches={imp.matches} />
  {:else if imp.kind === 'done'}
    <div class="center">
      <div class="stack">
        <Icon name="check_circle" size={56} color="#69f0ae" />
        <span class="heading">Created "{imp.playlistName}"</span>
        <span class="small">{imp.importedCount} imported · {imp.skippedCount} skipped</span>
        <div class="row">
          <Button
            variant="primary"
            onclick={() => {
              reset();
              selectedSection.value = SidebarSection.playlists;
            }}>Go to playlists</Button
          >
          <Button variant="text" onclick={reset}>Import another</Button>
        </div>
      </div>
    </div>
  {:else}
    <div class="center">
      <div class="stack">
        <ExtraIcon name="error_outline" size={48} color="#ff5252" />
        <span class="error">{imp.message}</span>
        <Button variant="primary" onclick={reset}>Start over</Button>
      </div>
    </div>
  {/if}
</section>

<style>
  .page {
    height: 100%;
    padding: 24px 24px var(--scroll-bottom-inset);
    overflow: hidden;
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
  .stack {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
  }
  .idle {
    display: flex;
    flex-direction: column;
  }
  h1 {
    margin: 0;
    font-size: 22px;
    font-weight: 700;
    color: var(--color-text-primary);
  }
  .lead {
    margin: 8px 0 0;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .url {
    margin-top: 24px;
    font-size: 13px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 16px;
  }
  .stack .row {
    margin-top: 8px;
  }
  .info {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin-top: 32px;
    padding: 12px;
    border-radius: 8px;
    background: var(--color-surface);
    font-size: 11px;
    color: var(--color-text-secondary);
  }
  .msg {
    font-size: 13px;
    color: var(--color-text-secondary);
  }
  .heading {
    font-size: 16px;
    font-weight: 500;
    color: var(--color-text-primary);
  }
  .bar {
    width: 280px;
  }
  .small {
    margin-top: -8px;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .error {
    max-width: 420px;
    text-align: center;
    font-size: 13px;
    color: var(--color-text-primary);
  }
</style>
