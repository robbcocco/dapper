import { untrack } from 'svelte';
import type { UnlistenFn } from '@tauri-apps/api/event';
import * as api from '../../lib/api';
import type { AlbumSyncStatus, ArtistSyncStatus, QueueItemStatus } from '../../lib/types';
import { devices } from '../../lib/stores/devices.svelte';
import { session } from '../../lib/stores/session.svelte';

const idle: QueueItemStatus = { active: false, queued: false };

/**
 * Shared library-row status: transfer-queue membership (queueAlbumStatusProvider /
 * queueSongStatusProvider), selected-device album/artist sync maps (albumFolderSyncProvider /
 * artistSyncProvider), and revision counters pages read to refetch on `library-changed` /
 * `manifest-revision`. Sync maps are only computed while a view watches them.
 */
class LibraryStatus {
  queueAlbums = $state<Record<string, QueueItemStatus>>({});
  queueSongs = $state<Record<string, QueueItemStatus>>({});
  albumSync = $state<Record<string, AlbumSyncStatus>>({});
  artistSync = $state<Record<string, ArtistSyncStatus>>({});
  /** Bumped on every `library-changed`; read inside load effects to refetch. */
  libraryRev = $state(0);
  /** Latest `manifest-revision`. */
  manifestRev = $state(0);
  albumSyncWatchers = $state(0);
  artistSyncWatchers = $state(0);

  albumQueue(id: string): QueueItemStatus {
    return this.queueAlbums[id] ?? idle;
  }
  songQueue(id: string): QueueItemStatus {
    return this.queueSongs[id] ?? idle;
  }

  /**
   * Call from a component `$effect`; returns the release function. Untracked: the
   * counter read inside `++` would otherwise make the caller's effect loop on itself.
   */
  watchAlbumSync(): () => void {
    untrack(() => this.albumSyncWatchers++);
    return () => untrack(() => this.albumSyncWatchers--);
  }
  watchArtistSync(): () => void {
    untrack(() => this.artistSyncWatchers++);
    return () => untrack(() => this.artistSyncWatchers--);
  }
}

export const libraryStatus = new LibraryStatus();

function loadQueue(): void {
  Promise.all([api.queueAlbumStatus(), api.queueSongStatus()])
    .then(([albums, songs]) => {
      libraryStatus.queueAlbums = albums;
      libraryStatus.queueSongs = songs;
    })
    .catch((e: unknown) => console.warn('library status: queue status failed', e));
}

$effect.root(() => {
  const subs: Promise<UnlistenFn>[] = [
    api.onQueueStatus((s) => {
      libraryStatus.queueAlbums = s.albums;
      libraryStatus.queueSongs = s.songs;
    }),
    api.onManifestRevision((rev) => {
      libraryStatus.manifestRev = rev;
    }),
    api.onLibraryChanged(() => {
      libraryStatus.libraryRev++;
    }),
  ];
  $effect(() => {
    void session.serverId;
    loadQueue();
  });

  $effect(() => {
    const path = devices.selected?.path ?? null;
    void libraryStatus.manifestRev;
    void libraryStatus.libraryRev;
    if (path === null || libraryStatus.albumSyncWatchers === 0) {
      if (path === null) libraryStatus.albumSync = {};
      return;
    }
    let stale = false;
    api
      .deviceAlbumSync(path)
      .then((m) => {
        if (!stale) libraryStatus.albumSync = m;
      })
      .catch((e: unknown) => console.warn('library status: album sync failed', e));
    return () => (stale = true);
  });

  $effect(() => {
    const path = devices.selected?.path ?? null;
    void libraryStatus.manifestRev;
    void libraryStatus.libraryRev;
    if (path === null || libraryStatus.artistSyncWatchers === 0) {
      if (path === null) libraryStatus.artistSync = {};
      return;
    }
    let stale = false;
    api
      .deviceArtistSync(path)
      .then((m) => {
        if (!stale) libraryStatus.artistSync = m;
      })
      .catch((e: unknown) => console.warn('library status: artist sync failed', e));
    return () => (stale = true);
  });

  return () => subs.forEach((s) => void s.then((un) => un()));
});

/**
 * Per-view on-device presence for a set of songs (songExistsOnDevice). Construct during
 * component init; refetches when the ids, the selected device or a manifest changes.
 */
export class SongPresence {
  #present = $state<Record<string, boolean>>({});

  constructor(ids: () => readonly string[]) {
    $effect(() => {
      const list = [...ids()];
      const path = devices.selected?.path ?? null;
      void libraryStatus.manifestRev;
      if (path === null || list.length === 0) {
        this.#present = {};
        return;
      }
      let stale = false;
      // Coalesce the bursts of range changes a scrolling list produces.
      const timer = setTimeout(() => {
        api
          .deviceSongPresence(path, list)
          .then((m) => {
            if (!stale) this.#present = m;
          })
          .catch((e: unknown) => console.warn('library status: song presence failed', e));
      }, 120);
      return () => {
        stale = true;
        clearTimeout(timer);
      };
    });
  }

  has(id: string): boolean {
    return this.#present[id] === true;
  }
}
