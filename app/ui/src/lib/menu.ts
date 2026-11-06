import { Menu, MenuItem as NativeItem, CheckMenuItem, Submenu, PredefinedMenuItem } from '@tauri-apps/api/menu';
import { LogicalPosition } from '@tauri-apps/api/dpi';

/** `checked` set → check item; `submenu` set → nested menu; `{ separator: true }` → divider. */
export type MenuItem =
  | { id: string; label: string; enabled?: boolean; checked?: boolean; submenu?: MenuItem[] }
  | { separator: true };
export const separator: MenuItem = { separator: true };

type Native = NativeItem | CheckMenuItem | Submenu | PredefinedMenuItem;

async function build(items: MenuItem[], pick: (id: string) => void): Promise<Native[]> {
  return Promise.all(
    items.map(async (it): Promise<Native> => {
      if ('separator' in it) return PredefinedMenuItem.new({ item: 'Separator' });
      const enabled = it.enabled ?? true;
      if (it.submenu) return Submenu.new({ text: it.label, enabled, items: await build(it.submenu, pick) });
      const action = (): void => pick(it.id);
      if (it.checked !== undefined) return CheckMenuItem.new({ id: it.id, text: it.label, enabled, checked: it.checked, action });
      return NativeItem.new({ id: it.id, text: it.label, enabled, action });
    }),
  );
}

declare global {
  /** Dev-only seam for the e2e harness (app/e2e/prelude.js): native menus can't be driven from the DOM. */
  interface Window {
    __e2eMenu?: (items: MenuItem[]) => Promise<string | null>;
  }
}

/**
 * Pops a native context menu at `at` (client coords; defaults to the cursor) and
 * resolves with the chosen item id, or null when dismissed.
 */
export async function showContextMenu(items: MenuItem[], at?: { x: number; y: number }): Promise<string | null> {
  if (import.meta.env.DEV && window.__e2eMenu) return window.__e2eMenu(items);
  let chosen: string | null = null;
  const menu = await Menu.new({ items: await build(items, (id) => (chosen = id)) });
  try {
    // popup() resolves once the menu closes; item actions arrive via IPC just before/after,
    // so yield a tick to let the action callback land.
    await menu.popup(at ? new LogicalPosition(at.x, at.y) : undefined);
    await new Promise((r) => setTimeout(r, 30));
    return chosen;
  } finally {
    void menu.close();
  }
}
