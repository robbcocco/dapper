import { invoke as tauriInvoke, Channel } from '@tauri-apps/api/core';
import { listen, type EventCallback, type UnlistenFn } from '@tauri-apps/api/event';

/** Serialized `dapper_domain::AppError` (mirrors lib/core/errors/app_exception.dart). */
export interface AppError {
  kind: string;
  message: string;
  code?: number;
}

export function isAppError(e: unknown): e is AppError {
  return typeof e === 'object' && e !== null && 'kind' in e && 'message' in e;
}

/** Normalises any rejection (AppError object, bare string, JS Error) into an AppError. */
export function toAppError(e: unknown): AppError {
  if (isAppError(e)) return e;
  if (typeof e === 'string') return { kind: 'other', message: e };
  if (e instanceof Error) return { kind: 'other', message: e.message };
  return { kind: 'other', message: String(e) };
}

export class IpcError extends Error {
  readonly error: AppError;
  constructor(error: AppError) {
    super(error.message);
    this.name = 'IpcError';
    this.error = error;
  }
}

/** Typed `invoke`; rejections are always `IpcError` carrying an `AppError`. */
export async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  try {
    return await tauriInvoke<T>(cmd, args);
  } catch (e) {
    throw new IpcError(toAppError(e));
  }
}

/** Subscribes to a backend event; returns the unlisten function. */
export function onEvent<T>(event: string, handler: (payload: T) => void): Promise<UnlistenFn> {
  const cb: EventCallback<T> = (e) => handler(e.payload);
  return listen<T>(event, cb);
}

/** Creates a Channel for streaming command output (pass it as a command arg). */
export function channel<T>(onMessage: (msg: T) => void): Channel<T> {
  const ch = new Channel<T>();
  ch.onmessage = onMessage;
  return ch;
}

export const ping = (): Promise<string> => invoke<string>('ping');
