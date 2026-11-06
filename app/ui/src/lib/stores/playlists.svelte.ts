import { untrack } from 'svelte';
import * as api from '../api';
import type { Playlist } from '../types';
import { session } from './session.svelte';
import { toast } from './toast.svelte';

/**
 * playlistsProvider + PlaylistActionsNotifier. `revision` bumps on every playlist
 * mutation and `library-changed` so open playlist details refetch too.
 */
class PlaylistsStore {
  items = $state<Playlist[] | null>(null);
  loading = $state(false);
  error = $state<unknown>(null);
  revision = $state(0);
  #seq = 0;

  async load(): Promise<void> {
    const seq = ++this.#seq;
    this.loading = true;
    this.error = null;
    try {
      const list = await api.playlistsList();
      if (seq === this.#seq) this.items = list;
    } catch (e) {
      if (seq === this.#seq) this.error = e;
    } finally {
      if (seq === this.#seq) this.loading = false;
    }
  }

  invalidate(): void {
    this.revision++;
    void this.load();
  }

  /** Runs `body`; on failure surfaces `failMessage` (actionErrorProvider). True on success. */
  async #guard(failMessage: string, body: () => Promise<unknown>): Promise<boolean> {
    try {
      await body();
      return true;
    } catch {
      toast(failMessage, { kind: 'error' });
      return false;
    } finally {
      this.invalidate();
    }
  }

  create(name: string, songIds: string[] = []): Promise<boolean> {
    return this.#guard('Could not create playlist', () => api.playlistCreate(name, songIds));
  }
  rename(id: string, name: string): Promise<boolean> {
    return this.#guard('Could not rename playlist', () => api.playlistRename(id, name));
  }
  addSongs(id: string, songIds: string[]): Promise<boolean> {
    return this.#guard('Could not add songs to playlist', () => api.playlistAddSongs(id, songIds));
  }
  removeSong(id: string, index: number): Promise<boolean> {
    return this.#guard('Could not remove song from playlist', () => api.playlistRemoveSong(id, index));
  }
  delete(id: string): Promise<boolean> {
    return this.#guard('Could not delete playlist', () => api.playlistDelete(id));
  }
}

export const playlists = new PlaylistsStore();

$effect.root(() => {
  $effect(() => {
    // Refetch whenever the active server changes (including the first one).
    if (session.serverId === null) {
      playlists.items = null;
      return;
    }
    untrack(() => playlists.invalidate());
  });
});

void api.onLibraryChanged(() => {
  if (session.serverId !== null) playlists.invalidate();
});
