import { mount, unmount, type Component } from 'svelte';
import ConfirmDialog from './ConfirmDialog.svelte';
import PromptDialog from './PromptDialog.svelte';

/** Mounts a dialog component on <body> and resolves with what it reports via `onresult`. */
function show<P extends { onresult: (r: R) => void }, R>(component: Component<P>, props: Omit<P, 'onresult'>): Promise<R> {
  return new Promise((resolve) => {
    const target = document.createElement('div');
    document.body.appendChild(target);
    const app = mount(component, {
      target,
      props: {
        ...props,
        onresult: (r: R) => {
          void unmount(app).then(() => target.remove());
          resolve(r);
        },
      } as P,
    });
  });
}

export interface ConfirmOptions {
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
}

/** showConfirmDialog port: true on confirm, false on cancel/dismiss. */
export function confirm(opts: ConfirmOptions): Promise<boolean> {
  return show(ConfirmDialog, opts);
}

export interface PromptOptions {
  title: string;
  message?: string;
  label?: string;
  placeholder?: string;
  initial?: string;
  confirmLabel?: string;
  cancelLabel?: string;
}

/** Text-input dialog; resolves the trimmed non-empty value, or null when cancelled. */
export function prompt(opts: PromptOptions): Promise<string | null> {
  return show(PromptDialog, opts);
}
