// Lazily expanded device folder tree, flattened into rows for VirtualList. Shared by the
// device file browser and the music-folder picker (both expand-on-tap trees in Dart).
import { toAppError, type AppError } from '../../lib/ipc';
import type { DeviceEntry } from '../../lib/types';

export interface TreeRow {
  /** Path relative to the device root, `/`-separated ('' = the device root). */
  rel: string;
  name: string;
  depth: number;
  /** null for the tree root row. */
  entry: DeviceEntry | null;
}

export const childRel = (parent: string, name: string): string => (parent === '' ? name : `${parent}/${name}`);

export class DeviceTree {
  expanded = $state.raw<ReadonlySet<string>>(new Set());
  loading = $state.raw<ReadonlySet<string>>(new Set());
  children = $state.raw<ReadonlyMap<string, DeviceEntry[]>>(new Map());
  errors = $state.raw<ReadonlyMap<string, AppError>>(new Map());

  readonly root: string;
  readonly #rootName: string;
  readonly #load: (rel: string) => Promise<DeviceEntry[]>;

  rows = $derived.by(() => {
    const out: TreeRow[] = [{ rel: this.root, name: this.#rootName, depth: 0, entry: null }];
    const walk = (rel: string, depth: number): void => {
      if (!this.expanded.has(rel)) return;
      for (const e of this.children.get(rel) ?? []) {
        const r = childRel(rel, e.name);
        out.push({ rel: r, name: e.name, depth, entry: e });
        if (e.isDir) walk(r, depth + 1);
      }
    };
    walk(this.root, 1);
    return out;
  });

  constructor(root: string, rootName: string, load: (rel: string) => Promise<DeviceEntry[]>) {
    this.root = root;
    this.#rootName = rootName;
    this.#load = load;
  }

  async #fetch(rel: string): Promise<DeviceEntry[]> {
    // Hidden entries (dotfiles, `._*` sidecars) never show; dirs first, then
    // case-insensitive code-unit order, as in Dart.
    return (await this.#load(rel))
      .filter((e) => !e.name.startsWith('.'))
      .sort((a, b) => {
        if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
        const x = a.name.toLowerCase();
        const y = b.name.toLowerCase();
        return x < y ? -1 : x > y ? 1 : 0;
      });
  }

  async toggle(rel: string): Promise<void> {
    if (this.loading.has(rel)) return;
    if (this.expanded.has(rel)) {
      const next = new Set(this.expanded);
      next.delete(rel);
      this.expanded = next;
      return;
    }
    if (!this.children.has(rel)) {
      this.loading = new Set(this.loading).add(rel);
      try {
        this.children = new Map(this.children).set(rel, await this.#fetch(rel));
        const errs = new Map(this.errors);
        errs.delete(rel);
        this.errors = errs;
      } catch (e) {
        this.errors = new Map(this.errors).set(rel, toAppError(e));
        return;
      } finally {
        const next = new Set(this.loading);
        next.delete(rel);
        this.loading = next;
      }
    }
    this.expanded = new Set(this.expanded).add(rel);
  }

  /** Re-lists every expanded folder in place (device contents changed), keeping expansion. */
  async reload(): Promise<void> {
    const children = new Map<string, DeviceEntry[]>();
    for (const rel of this.expanded) {
      try {
        children.set(rel, await this.#fetch(rel));
      } catch {
        // Folder vanished; it collapses and a later expand surfaces the error.
      }
    }
    this.children = children;
    this.expanded = new Set([...this.expanded].filter((r) => children.has(r)));
  }
}
