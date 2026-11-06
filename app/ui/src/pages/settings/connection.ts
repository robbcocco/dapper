// Shared connection-form helpers for the setup page and the server / Lidarr
// dialogs (ports of their _friendlyError / validators).
import { IpcError, toAppError, type AppError } from '../../lib/ipc';

const TIMEOUT_MS = 15_000;

/**
 * Outer hard timeout: the OS can pend a connection awaiting macOS Local Network
 * privacy approval, so guarantee the spinner stops within 15 s either way.
 */
export function withTimeout<T>(p: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new IpcError({ kind: 'network', message: 'TimeoutException' })), TIMEOUT_MS);
  });
  return Promise.race([p, timeout]).finally(() => clearTimeout(timer));
}

/** Errors raised while persisting rather than while reaching the server. */
export const isSaveError = (e: AppError): boolean => e.kind === 'storage' || e.kind === 'io';

export function errorOf(e: unknown): AppError {
  return e instanceof IpcError ? e.error : toAppError(e);
}

/** Trims and strips trailing slashes, like `replaceAll(RegExp(r'/+$'), '')`. */
export const normalizeUrl = (v: string): string => v.trim().replace(/\/+$/, '');

/** Dart `Uri.tryParse(v)?.hasScheme` validator. */
export function validateUrl(v: string): string | null {
  const t = v.trim();
  if (t === '') return 'Required';
  return /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(t) ? null : 'Enter a valid URL';
}

/** Navidrome connection failures → actionable copy (setup page + server dialog). */
export function friendlyServerError(e: AppError, separator: string): string {
  const raw = e.message;
  const lower = raw.toLowerCase();
  if (lower.includes('timeout') || lower.includes('timed out')) {
    return (
      'Timed out reaching the server. On macOS, check System ' +
      'Settings → Privacy & Security → Local Network and make sure ' +
      'Dapper is allowed. Also verify the URL includes the port ' +
      '(e.g. http://192.168.1.10:4533).'
    );
  }
  if (lower.includes('network is unreachable') || lower.includes('no route to host')) {
    return 'Network unreachable. Make sure this Mac is on the same network as your Navidrome server.';
  }
  if (e.kind === 'auth' || raw.includes('401') || raw.includes('Unauthorized')) {
    return 'Invalid username or password.';
  }
  if (e.kind === 'subsonic' || lower.includes('handshake') || lower.includes('certificate')) {
    return 'Connected, but authentication failed. Check your credentials.';
  }
  if (
    e.kind === 'network' ||
    lower.includes('connection refused') ||
    lower.includes('dns') ||
    lower.includes('failed to lookup')
  ) {
    return 'Could not reach the server. Check the URL and your network.';
  }
  return `Connection failed${separator}${raw}`;
}

/** Lidarr connection failures → actionable copy. */
export function friendlyLidarrError(e: AppError): string {
  const raw = e.message;
  if (e.kind === 'auth' || raw.includes('401') || raw.includes('Unauthorized')) return 'Invalid API key.';
  const lower = raw.toLowerCase();
  if (
    e.kind === 'network' ||
    lower.includes('timeout') ||
    lower.includes('timed out') ||
    lower.includes('connection refused') ||
    lower.includes('dns')
  ) {
    return "Couldn't reach Lidarr. Check the URL and that it's running.";
  }
  return `Connection failed: ${raw}`;
}
