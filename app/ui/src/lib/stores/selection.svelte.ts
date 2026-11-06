import { session } from './session.svelte';

/**
 * Scope-keyed multi-select (port of song_selection_notifier.dart). `scopeKey` identifies
 * the visible list so navigating elsewhere clears the selection; `anchorIndex` is the
 * last single-clicked row, the fixed end of shift-click ranges. Ordered lists are ids in
 * display order.
 */
class SelectionStore {
  scopeKey = $state<string | null>(null);
  selectedIds = $state<ReadonlySet<string>>(new Set());
  anchorIndex = $state<number | null>(null);

  get isEmpty(): boolean {
    return this.selectedIds.size === 0;
  }
  get count(): number {
    return this.selectedIds.size;
  }
  isSelected(id: string): boolean {
    return this.selectedIds.has(id);
  }
  matches(key: string | null | undefined): boolean {
    return key != null && this.scopeKey === key;
  }
  /** Selected ids of `scopeKey`, in `ordered` display order. */
  selectedIn(scopeKey: string, ordered: readonly string[]): string[] {
    return this.matches(scopeKey) ? ordered.filter((id) => this.selectedIds.has(id)) : [];
  }

  #set(scopeKey: string | null, ids: ReadonlySet<string>, anchor: number | null): void {
    this.scopeKey = scopeKey;
    this.selectedIds = ids;
    this.anchorIndex = anchor;
  }

  reset(): void {
    this.#set(null, new Set(), null);
  }
  setScope(scopeKey: string): void {
    if (this.scopeKey !== scopeKey) this.#set(scopeKey, new Set(), null);
  }
  clear(): void {
    this.#set(this.scopeKey, new Set(), null);
  }
  selectOnly(scopeKey: string, id: string, index: number): void {
    this.#set(scopeKey, new Set([id]), index);
  }
  /** Anchor moves to `index` regardless of result so shift-click ranges from the latest toggle. */
  toggle(scopeKey: string, id: string, index: number): void {
    const next = new Set(this.matches(scopeKey) ? this.selectedIds : []);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    this.#set(scopeKey, next, index);
  }
  selectAll(scopeKey: string, ordered: readonly string[]): void {
    if (ordered.length === 0) return;
    this.#set(scopeKey, new Set(ordered), ordered.length - 1);
  }
  /** Adds anchor..toIndex inclusive; anchor is kept so later shift-clicks range from it (Finder). */
  selectRange(scopeKey: string, ordered: readonly string[], toIndex: number): void {
    if (toIndex < 0 || toIndex >= ordered.length) return;
    const scoped = this.matches(scopeKey);
    // Clamp: the anchor may come from a longer list that has since shrunk.
    const anchor = Math.min(Math.max((scoped ? this.anchorIndex : null) ?? toIndex, 0), ordered.length - 1);
    const next = new Set(scoped ? this.selectedIds : []);
    for (let i = Math.min(anchor, toIndex); i <= Math.max(anchor, toIndex); i++) next.add(ordered[i]!);
    this.#set(scopeKey, next, scoped ? this.anchorIndex : null);
  }
  /** Row click dispatch: shift → range, ⌘/Ctrl → toggle, else select-only. */
  click(scopeKey: string, ordered: readonly string[], index: number, e: MouseEvent | KeyboardEvent): void {
    const id = ordered[index];
    if (id === undefined) return;
    if (e.shiftKey) this.selectRange(scopeKey, ordered, index);
    else if (isMac ? e.metaKey : e.ctrlKey) this.toggle(scopeKey, id, index);
    else this.selectOnly(scopeKey, id, index);
  }
}

const isMac = navigator.platform.toUpperCase().includes('MAC');

export const selection = new SelectionStore();

// Ids are server-scoped: drop the selection when the active server changes.
$effect.root(() => {
  let prev = session.serverId;
  $effect(() => {
    const id = session.serverId;
    if (id !== prev) {
      prev = id;
      selection.reset();
    }
  });
});

function isTextInput(el: Element | null): boolean {
  if (!(el instanceof HTMLElement)) return false;
  if (el.isContentEditable || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) return true;
  if (!(el instanceof HTMLInputElement)) return false;
  return !['button', 'checkbox', 'radio', 'range', 'submit', 'reset', 'color', 'file'].includes(el.type);
}

/**
 * ⌘A / Ctrl+A select-all (select_all_shortcut.dart). Registers a window keydown handler
 * and returns its remover — call from `$effect` in a page:
 * `$effect(() => selectAllShortcut(scope, () => ids))`. Skipped while a text field has focus.
 */
export function selectAllShortcut(scopeKey: string, ordered: () => readonly string[]): () => void {
  const onKey = (e: KeyboardEvent): void => {
    if (e.defaultPrevented || e.key.toLowerCase() !== 'a' || e.altKey || e.shiftKey) return;
    if (!e.metaKey && !e.ctrlKey) return;
    if (isTextInput(document.activeElement)) return;
    e.preventDefault();
    selection.selectAll(scopeKey, ordered());
  };
  window.addEventListener('keydown', onKey);
  return () => window.removeEventListener('keydown', onKey);
}
