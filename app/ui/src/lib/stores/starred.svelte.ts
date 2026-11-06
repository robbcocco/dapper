import { starredIds, starSet } from '../api';
import { session } from './session.svelte';

/** Starred song ids (port of starred_notifier.dart); reset and reloaded when the active server changes. */
class StarredStore {
  ids = $state<ReadonlySet<string>>(new Set());
  #loadSeq = 0;

  has(id: string): boolean {
    return this.ids.has(id);
  }

  async reload(): Promise<void> {
    const seq = ++this.#loadSeq;
    if (session.serverId === null) return;
    try {
      const ids = await starredIds();
      // A newer reload (or server switch) superseded this one.
      if (seq === this.#loadSeq) this.ids = new Set(ids);
    } catch (e) {
      console.warn('starred: failed to load starred songs', e);
    }
  }

  /** Optimistic flip so the heart responds instantly; rolled back if the server rejects it. */
  async toggle(id: string): Promise<void> {
    if (session.serverId === null) return;
    const wasStarred = this.ids.has(id);
    this.#apply(id, !wasStarred);
    try {
      await starSet(id, !wasStarred);
    } catch (e) {
      this.#apply(id, wasStarred);
      console.warn(`starred: toggle(${id}) failed`, e);
    }
  }

  #apply(id: string, starred: boolean): void {
    const next = new Set(this.ids);
    if (starred) next.add(id);
    else next.delete(id);
    this.ids = next;
  }
}

export const starred = new StarredStore();

$effect.root(() => {
  $effect(() => {
    void session.serverId;
    starred.ids = new Set();
    void starred.reload();
  });
});
