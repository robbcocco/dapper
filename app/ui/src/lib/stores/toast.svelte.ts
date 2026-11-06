/** Snackbar state (ScaffoldMessenger port): showing a toast replaces the current one. */
export interface Toast {
  id: number;
  message: string;
  kind: 'info' | 'error' | 'success';
  action?: { label: string; run: () => void };
}

export const toasts = $state<{ current: Toast | null }>({ current: null });

let seq = 0;
let timer: ReturnType<typeof setTimeout> | undefined;

export interface ToastOptions {
  kind?: Toast['kind'];
  action?: Toast['action'];
  /** Milliseconds; Flutter SnackBar default is 4 s. */
  duration?: number;
}

export function toast(message: string, opts: ToastOptions = {}): void {
  clearTimeout(timer);
  const t: Toast = { id: ++seq, message, kind: opts.kind ?? 'info', action: opts.action };
  toasts.current = t;
  timer = setTimeout(() => {
    if (toasts.current?.id === t.id) toasts.current = null;
  }, opts.duration ?? 4000);
}

export function dismissToast(): void {
  clearTimeout(timer);
  toasts.current = null;
}
