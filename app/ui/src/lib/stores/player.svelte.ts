import type { UnlistenFn } from '@tauri-apps/api/event';
import * as api from '../api';
import { toAppError } from '../ipc';
import type { PlayerPosition, PlayerState } from '../types';
import { toast } from './toast.svelte';

const idle: PlayerState = {
  currentSong: null,
  queue: [],
  currentIndex: -1,
  isPlaying: false,
  isBuffering: false,
  durationMs: 0,
  volume: 1,
  isShuffled: false,
  repeatMode: 'none',
  errorMessage: null,
};

/**
 * Mirror of the backend player (playback_notifier.dart). `state` follows `player-state`;
 * `position` follows the ~4 Hz `player-position` ticks separately so only position-bound
 * views re-render on ticks.
 */
class PlayerStore {
  state = $state<PlayerState>(idle);
  position = $state<PlayerPosition>({ positionMs: 0, durationMs: 0 });

  hasPrevious = $derived(this.state.currentIndex > 0 || this.state.repeatMode === 'all');
  hasNext = $derived(
    this.state.currentIndex < this.state.queue.length - 1 || this.state.repeatMode === 'all',
  );
  /** Ticks carry the decoder's duration; fall back to the state's until the first tick. */
  durationMs = $derived(this.position.durationMs > 0 ? this.position.durationMs : this.state.durationMs);

  toggle = (): void => run(api.playerToggle());
  next = (): void => run(api.playerNext());
  previous = (): void => run(api.playerPrevious());
  toggleShuffle = (): void => run(api.playerToggleShuffle());
  cycleRepeat = (): void => run(api.playerCycleRepeat());

  seek = (positionMs: number): void => {
    this.position = { ...this.position, positionMs };
    run(api.playerSeek(Math.round(positionMs)));
  };

  /** Applied locally first so the slider tracks the drag without waiting for the echo. */
  setVolume = (volume: number): void => {
    this.state = { ...this.state, volume };
    run(api.playerSetVolume(volume));
  };
}

function run(p: Promise<void>): void {
  p.catch((e: unknown) => toast(toAppError(e).message, { kind: 'error' }));
}

export const player = new PlayerStore();

/** Subscribes to the player events; returns the unsubscriber. Called once by the shell. */
export function startPlayerSync(): () => void {
  let disposed = false;
  let statePushed = false;
  let positionPushed = false;
  const subs: Promise<UnlistenFn>[] = [
    api.onPlayerState((s) => {
      statePushed = true;
      const songChanged = s.currentSong?.id !== player.state.currentSong?.id;
      player.state = s;
      if (songChanged) player.position = { positionMs: 0, durationMs: s.durationMs };
    }),
    api.onPlayerPosition((p) => {
      positionPushed = true;
      player.position = p;
    }),
  ];
  api
    .playerState()
    .then(({ state, position }) => {
      // Events that raced the initial fetch are newer; keep them.
      if (disposed) return;
      if (!statePushed) player.state = state;
      if (!positionPushed && !statePushed) player.position = position;
    })
    .catch((e: unknown) => console.warn('player: initial state failed', e));
  return () => {
    disposed = true;
    subs.forEach((s) => void s.then((un) => un()));
  };
}
