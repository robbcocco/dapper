import type { Page } from '../../lib/types';

/**
 * Lazily fetched, chunked view over a server-side sorted list (`albums_window` /
 * `songs_window`). Rows are fetched as the virtual list reports its visible range.
 */
export class Windowed<T> {
  total = $state<number | null>(null);
  error = $state<unknown>(null);
  #chunks = $state.raw<ReadonlyMap<number, T[]>>(new Map());
  #inflight = new Map<number, Promise<void>>();
  #gen = 0;
  readonly #fetch: (offset: number, limit: number) => Promise<Page<T>>;
  readonly #size: number;

  constructor(fetch: (offset: number, limit: number) => Promise<Page<T>>, chunkSize = 100) {
    this.#fetch = fetch;
    this.#size = chunkSize;
  }

  get loading(): boolean {
    return this.total === null && this.error === null;
  }

  get(index: number): T | null {
    return this.#chunks.get(Math.floor(index / this.#size))?.[index % this.#size] ?? null;
  }

  /** Drops everything and fetches the first chunk (server switch, sort change, library change). */
  reset(): Promise<void> {
    this.#gen++;
    this.#inflight.clear();
    this.#chunks = new Map();
    this.total = null;
    this.error = null;
    return this.#load(0);
  }

  /** Refetches the loaded chunks in place, keeping rows visible meanwhile (library-changed). */
  async refresh(): Promise<void> {
    const loaded = [...this.#chunks.keys()];
    this.#gen++;
    this.#inflight.clear();
    await Promise.all((loaded.length ? loaded : [0]).map((c) => this.#load(c)));
  }

  /** Ensures rows [start, end) are loaded. */
  ensure(start: number, end: number): Promise<void> {
    const last = this.total === null ? end : Math.min(end, this.total);
    const jobs: Promise<void>[] = [];
    for (let c = Math.floor(start / this.#size); c * this.#size < last; c++) {
      if (!this.#chunks.has(c)) jobs.push(this.#load(c));
    }
    return Promise.all(jobs).then(() => undefined);
  }

  #load(chunk: number): Promise<void> {
    const existing = this.#inflight.get(chunk);
    if (existing) return existing;
    const gen = this.#gen;
    const p = this.#fetch(chunk * this.#size, this.#size)
      .then((page) => {
        if (gen !== this.#gen) return;
        this.total = page.total;
        this.error = null;
        const next = new Map(this.#chunks);
        next.set(chunk, page.items);
        this.#chunks = next;
      })
      .catch((e: unknown) => {
        if (gen === this.#gen) this.error = e;
      })
      .finally(() => {
        if (this.#inflight.get(chunk) === p) this.#inflight.delete(chunk);
      });
    this.#inflight.set(chunk, p);
    return p;
  }
}
