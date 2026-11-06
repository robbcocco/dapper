<script lang="ts">
  import * as api from '../../lib/api';
  import type { Playlist } from '../../lib/types';
  import { devices } from '../../lib/stores/devices.svelte';
  import { playlists } from '../../lib/stores/playlists.svelte';
  import { selectionNav } from '../../lib/stores/selection-nav.svelte';
  import { selectAllShortcut, selection } from '../../lib/stores/selection.svelte';
  import Button from '../../widgets/Button.svelte';
  import CoverArt from '../../widgets/CoverArt.svelte';
  import ErrorRetry from '../../widgets/ErrorRetry.svelte';
  import IconButton from '../../widgets/IconButton.svelte';
  import Spinner from '../../widgets/Spinner.svelte';
  import SyncDot from '../../widgets/SyncDot.svelte';
  import VirtualList from '../../widgets/VirtualList.svelte';
  import { toSafeFilename } from '../../widgets/device/preview';
  import SongRow from '../../widgets/library/SongRow.svelte';
  import SongSyncDot from '../../widgets/library/SongSyncDot.svelte';
  import SelectionActionBar from '../../widgets/library/SelectionActionBar.svelte';
  import { attempt, playSongs } from '../../widgets/library/actions';
  import { pickDevicePath, showAddToPlaylistDialog } from '../../widgets/library/dialogs';
  import { libraryStatus, SongPresence } from '../../widgets/library/status.svelte';

  let { playlistId }: { playlistId: string } = $props();

  let playlist = $state<Playlist | null>(null);
  let error = $state<unknown>(null);
  let reload = $state(0);

  // Refetch on open, retry, and every playlist mutation / library change.
  $effect(() => {
    void playlists.revision;
    void reload;
    let stale = false;
    error = null;
    api
      .playlistGet(playlistId)
      .then((p) => {
        if (!stale) playlist = p;
      })
      .catch((e: unknown) => {
        if (!stale) error = e;
      });
    return () => (stale = true);
  });

  const songs = $derived(playlist?.songs ?? []);
  const ids = $derived(songs.map((s) => s.id));
  const scopeKey = $derived(`playlist:${playlistId}`);

  $effect(() => selection.setScope(scopeKey));
  $effect(() => selectAllShortcut(scopeKey, () => ids));

  const presence = new SongPresence(() => ids);

  // playlistExistsOnDevice: <device>/<playlistFolder>/<name.toSafeFilename()>.m3u on the selected device.
  let onDevice = $state(false);
  $effect(() => {
    const path = devices.selected?.path ?? null;
    const name = playlist?.name ?? null;
    void libraryStatus.manifestRev;
    if (path === null || name === null) {
      onDevice = false;
      return;
    }
    let stale = false;
    const file = `${toSafeFilename(name)}.m3u`;
    api
      .deviceSettingsGet(path)
      .then((s) => api.deviceBrowse(path, s.playlistFolder))
      .then((entries) => {
        if (!stale) onDevice = entries.some((e) => !e.isDir && e.name === file);
      })
      .catch(() => {
        // A missing playlist folder means nothing has been synced yet.
        if (!stale) onDevice = false;
      });
    return () => (stale = true);
  });

  function fmtDuration(s: number): string {
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  }

  async function sync(p: Playlist): Promise<void> {
    const path = await pickDevicePath(devices.list);
    if (path === null) return;
    void attempt(api.transferEnqueuePlaylist(path, p.id), 'Could not queue playlist');
  }
</script>

{#if playlist}
  {@const p = playlist}
  <div class="detail">
    <VirtualList count={songs.length} rowHeight={48}>
      {#snippet header()}
        <div class="header">
          <span class="back">
            <IconButton label="Back" icon="chevron_left" size={18} color="var(--color-text-secondary)" onclick={() => (selectionNav.selectedPlaylistId = null)} />
          </span>
          <CoverArt coverArtId={p.coverArtId} size={240} display="120px" radius={8} />
          <div class="info">
            <h1>{p.name}</h1>
            <div class="meta">{p.songCount} songs · {fmtDuration(p.duration)}</div>
            {#if onDevice}
              <div class="on-device"><SyncDot state="full" /> Playlist on device</div>
            {/if}
            <div class="actions">
              {#if songs.length > 0}
                <Button small icon="play" onclick={() => playSongs(songs, 0)}>Play</Button>
              {/if}
              <Button
                small
                variant="primary"
                icon={onDevice ? 'sync' : 'download'}
                disabled={songs.length === 0 || devices.list.length === 0}
                onclick={() => void sync(p)}
              >
                {devices.list.length === 0 ? 'No device connected' : onDevice ? 'Re-sync' : 'Sync Playlist'}
              </Button>
              <IconButton
                label="Add songs to playlist"
                icon="playlist_add"
                size={20}
                color="var(--color-text-secondary)"
                onclick={() => showAddToPlaylistDialog(ids)}
              />
            </div>
          </div>
        </div>
      {/snippet}
      {#snippet row(i)}
        {@const song = songs[i]!}
        <SongRow
          {song}
          index={i}
          showArtist
          {scopeKey}
          allSongs={songs}
          onTap={() => playSongs(songs, i)}
          onRemove={() => void playlists.removeSong(p.id, i)}
        >
          {#snippet trailing()}
            <SongSyncDot songId={song.id} onDevice={presence.has(song.id)} />
          {/snippet}
        </SongRow>
      {/snippet}
    </VirtualList>
    <div class="bar"><SelectionActionBar {scopeKey} allSongs={songs} /></div>
  </div>
{:else if error !== null}
  <ErrorRetry {error} onRetry={() => reload++} />
{:else}
  <div class="center"><Spinner size={28} /></div>
{/if}

<style>
  .detail {
    position: relative;
    height: 100%;
  }
  .header {
    display: flex;
    align-items: flex-end;
    gap: 20px;
    padding: 24px;
  }
  .back {
    margin-right: -12px;
    align-self: flex-end;
  }
  .info {
    flex: 1;
    min-width: 0;
  }
  h1 {
    margin: 0;
    font-size: 22px;
    font-weight: 700;
    color: var(--color-text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .meta {
    margin-top: 4px;
    font-size: 12px;
    color: var(--color-text-secondary);
  }
  .on-device {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-top: 4px;
    font-size: 11px;
    color: #4caf50;
  }
  .actions {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 12px;
  }
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
