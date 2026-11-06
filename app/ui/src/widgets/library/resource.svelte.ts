import { untrack } from 'svelte';
import { session } from '../../lib/stores/session.svelte';
import { libraryStatus } from './status.svelte';

/**
 * FutureProvider-style fetch bound to the component that constructs it. Refetches when
 * `key()` or the server changes (clearing the old value) and on `library-changed`
 * (keeping the old value visible until the new one lands).
 */
export class Resource<T> {
  value = $state.raw<T | undefined>(undefined);
  error = $state<unknown>(null);
  #seq = 0;
  #lastKey: string | null = null;
  #retry = $state(0);

  constructor(fetch: (key: string) => Promise<T>, key: () => string = () => '') {
    $effect(() => {
      const k = `${session.serverId ?? ''}\u0000${key()}`;
      void libraryStatus.libraryRev;
      void this.#retry;
      untrack(() => {
        if (k !== this.#lastKey) {
          this.#lastKey = k;
          this.value = undefined;
        }
        this.error = null;
        const mine = ++this.#seq;
        fetch(key())
          .then((v) => {
            if (mine === this.#seq) this.value = v;
          })
          .catch((e: unknown) => {
            if (mine === this.#seq) this.error = e;
          });
      });
    });
  }

  get loading(): boolean {
    return this.value === undefined && this.error === null;
  }

  retry(): void {
    this.#retry++;
  }
}
