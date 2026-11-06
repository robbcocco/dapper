import { focusSearch, search } from './search.svelte';

/**
 * Global shortcut actions (lib/ui/shell/app_shortcuts.dart). Playback handlers are
 * no-ops until the playback feature assigns them, e.g. `shortcuts.playPause = () => player.toggle()`.
 */
export const shortcuts = {
  playPause: (): void => {},
  next: (): void => {},
  previous: (): void => {},
  focusSearch,
  /** Returns true when it consumed the key (a query was active). */
  clearSearch: (): boolean => {
    if (search.query === '') return false;
    search.query = '';
    search.input?.blur();
    return true;
  },
};

const isMac = navigator.platform.toUpperCase().includes('MAC');

function isTextInput(el: Element | null): boolean {
  if (!(el instanceof HTMLElement)) return false;
  if (el.isContentEditable || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) return true;
  if (!(el instanceof HTMLInputElement)) return false;
  return !['button', 'checkbox', 'radio', 'range', 'submit', 'reset', 'color', 'file'].includes(el.type);
}

export function handleShortcut(e: KeyboardEvent): void {
  if (e.defaultPrevented || e.isComposing) return;
  const accel = isMac ? e.metaKey && !e.ctrlKey : e.ctrlKey && !e.metaKey;
  if (accel && !e.altKey && !e.shiftKey && e.key.toLowerCase() === 'f') {
    e.preventDefault();
    shortcuts.focusSearch();
    return;
  }
  if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;
  if (e.key === 'Escape') {
    // Only intercept Escape with an active query so dialogs keep their dismiss behaviour.
    if (shortcuts.clearSearch()) e.preventDefault();
    return;
  }
  if (isTextInput(document.activeElement)) return;
  const action = e.key === ' ' ? shortcuts.playPause : e.key === 'ArrowRight' ? shortcuts.next : e.key === 'ArrowLeft' ? shortcuts.previous : null;
  if (!action) return;
  e.preventDefault();
  action();
}
