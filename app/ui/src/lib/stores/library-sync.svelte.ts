import * as api from '../api';
import type { SyncProgress } from '../types';
import { session } from './session.svelte';

/**
 * Background library-cache sync state (`library_sync_status` + `library-sync`). The cache
 * is empty until the first pass lands, so empty library pages read `syncing` to say so.
 */
class LibrarySyncStore {
  status = $state<SyncProgress | null>(null);

  /** True while a pass runs and nothing has ever been synced for this server. */
  get firstSync(): boolean {
    return this.status !== null && this.status.running && this.status.lastSyncedAt === null;
  }

  start(): void {
    void api.librarySync(false).catch((e: unknown) => console.warn('library_sync failed', e));
  }
}

export const librarySync = new LibrarySyncStore();

$effect.root(() => {
  const un = api.onLibrarySync((s) => {
    librarySync.status = s;
  });
  $effect(() => {
    void session.serverId;
    api
      .librarySyncStatus()
      .then((s) => {
        librarySync.status = s;
      })
      .catch((e: unknown) => console.warn('library_sync_status failed', e));
  });
  return () => void un.then((f) => f());
});
