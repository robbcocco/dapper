import { ratingSet } from '../../lib/api';
import { toAppError } from '../../lib/ipc';
import { session } from '../../lib/stores/session.svelte';
import { toast } from '../../lib/stores/toast.svelte';

/**
 * Session overlay of ratings the user set (ratings_notifier.dart): views show
 * `ratings.get(id, serverValue)` so edits apply before the library refetches.
 */
class RatingsStore {
  #overlay = $state<Record<string, number>>({});

  get(id: string, fallback: number | null): number {
    return this.#overlay[id] ?? fallback ?? 0;
  }

  async set(id: string, rating: number): Promise<void> {
    const prev = this.#overlay[id];
    this.#overlay = { ...this.#overlay, [id]: rating };
    try {
      await ratingSet(id, rating);
    } catch (e) {
      const next = { ...this.#overlay };
      if (prev === undefined) delete next[id];
      else next[id] = prev;
      this.#overlay = next;
      toast(`Could not set rating: ${toAppError(e).message}`, { kind: 'error' });
    }
  }

  reset(): void {
    this.#overlay = {};
  }
}

export const ratings = new RatingsStore();

$effect.root(() => {
  $effect(() => {
    void session.serverId;
    ratings.reset();
  });
});
