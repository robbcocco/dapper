<script lang="ts">
  import Button from '../../widgets/Button.svelte';
  import CoverArt from '../../widgets/CoverArt.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import SongRow from '../../widgets/library/SongRow.svelte';
  import SongSyncDot from '../../widgets/library/SongSyncDot.svelte';
  import SelectionActionBar from '../../widgets/library/SelectionActionBar.svelte';
  import { playSongs, transferAlbum } from '../../widgets/library/actions';
  import { showAddToPlaylistDialog, showAlbumInfoDialog } from '../../widgets/library/dialogs';
  import { Resource } from '../../widgets/library/resource.svelte';
  import { SongPresence } from '../../widgets/library/status.svelte';
  import * as api from '../../lib/api';
  import type { Album } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { closeAlbum, libraryNav } from '../../lib/stores/library-nav.svelte';
  import { selectedSection, SidebarSection } from '../../lib/stores/navigation.svelte';
  import { selection, selectAllShortcut } from '../../lib/stores/selection.svelte';

  /** album_detail_page.dart. Rendered inside the albums, artists and genres sections. */
  let { albumId }: { albumId: string } = $props();

  const album = new Resource<Album>((id) => api.albumGet(id), () => albumId);
  const songs = $derived(album.value?.songs ?? []);
  const scope = $derived(`album:${albumId}`);
  const ids = $derived(songs.map((s) => s.id));
  const presence = new SongPresence(() => ids);

  // Reset selection when navigating between albums.
  $effect(() => selection.setScope(scope));
  $effect(() => selectAllShortcut(scope, () => ids));

  const transferText = $derived(
    devices.list.length === 0 ? 'No device connected' : devices.selected === null ? 'Select a device' : 'Transfer',
  );

  function goToArtist(artistId: string | null): void {
    // Clear the drill-down before switching sections so the album doesn't flash there.
    libraryNav.albumId = null;
    if (artistId !== null) libraryNav.artistId = artistId;
    selectedSection.value = SidebarSection.artists;
  }

  function year(a: Album): string {
    return [a.year != null ? String(a.year) : null, `${a.songCount} songs`].filter(Boolean).join(' · ');
  }
</script>

{#if album.value}
  {@const a = album.value}
  <div class="detail">
    <VirtualList count={songs.length} rowHeight={40}>
      {#snippet header()}
        <header class="head">
          <IconButton icon="chevron_left" size={16} label="Back" onclick={closeAlbum} />
          <CoverArt coverArtId={a.coverArtId} size={240} radius={8} display="120px" />
          <div class="meta">
            <h1>{a.name}</h1>
            {#if a.artist}
              <button type="button" class="artist" onclick={() => goToArtist(a.artistId)}>{a.artist}</button>
            {/if}
            <div class="sub">{year(a)}</div>
            <div class="actions">
              {#if songs.length > 0}
                <Button icon="play" small onclick={() => playSongs(songs, 0)}>Play</Button>
              {/if}
              <Button
                variant="primary"
                icon="download"
                small
                disabled={songs.length === 0 || devices.selected === null}
                onclick={() => devices.selected && transferAlbum(devices.selected.path, a.id)}>{transferText}</Button
              >
              <IconButton
                icon="playlist_add"
                size={20}
                label="Add album to playlist"
                disabled={songs.length === 0}
                onclick={() => showAddToPlaylistDialog(ids)}
              />
              <IconButton icon="info" size={20} label="Get Info" onclick={() => showAlbumInfoDialog(a)} />
            </div>
          </div>
        </header>
      {/snippet}
      {#snippet row(i: number)}
        {@const s = songs[i]!}
        <SongRow song={s} scopeKey={scope} allSongs={songs} onTap={() => playSongs(songs, i)}>
          {#snippet trailing()}<SongSyncDot songId={s.id} onDevice={presence.has(s.id)} />{/snippet}
        </SongRow>
      {/snippet}
    </VirtualList>
    <div class="bar"><SelectionActionBar scopeKey={scope} allSongs={songs} /></div>
  </div>
{:else if album.error}
  <ErrorRetry error={album.error} onRetry={() => album.retry()} />
{:else}
  <div class="center"><Spinner /></div>
{/if}

<style>
  .detail {
    position: relative;
    height: 100%;
  }
  .head {
    display: flex;
    align-items: flex-end;
    gap: 8px;
    padding: 24px;
  }
  .meta {
    flex: 1;
    min-width: 0;
    margin-left: 12px;
  }
  h1 {
    margin: 0;
    font-size: 22px;
    font-weight: 700;
  }
  .artist {
    padding: 0;
    border: none;
    background: none;
    font: inherit;
    font-size: 14px;
    color: var(--color-accent);
    text-decoration: underline;
    text-decoration-thickness: 0.5px;
    cursor: pointer;
  }
  .sub {
    margin-top: 4px;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .actions {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 12px;
  }
  /* Floats above the shell's bottom player bar, which overlays page content. */
  .bar {
    position: absolute;
    left: 0;
    right: 0;
    bottom: var(--scroll-bottom-inset);
  }
  .center {
    height: 100%;
    display: grid;
    place-items: center;
  }
</style>
