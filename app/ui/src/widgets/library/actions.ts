import * as api from '../../lib/api';
import { toAppError } from '../../lib/ipc';
import type { Album, ConnectedDevice, Song } from '../../lib/types';
import { player } from '../../lib/stores/player.svelte';
import { toast } from '../../lib/stores/toast.svelte';

/** Runs a backend action, surfacing failures as an error snackbar (actionErrorProvider). */
export async function attempt<T>(p: Promise<T>, failMessage?: string): Promise<T | undefined> {
  try {
    return await p;
  } catch (e) {
    const msg = toAppError(e).message;
    toast(failMessage ? `${failMessage}: ${msg}` : msg, { kind: 'error' });
    return undefined;
  }
}

export const playSongs = (songs: Song[], index: number): void => {
  if (songs.length === 0) return;
  void attempt(api.playerPlaySongs(songs, index));
};

export const playAlbum = (albumId: string): void => {
  void attempt(api.playerPlayAlbum(albumId, 0));
};

export const playArtist = (artistId: string): void => {
  void attempt(api.playerPlayArtist(artistId));
};

/** Artist "Shuffle": turn shuffle on (never off) then play everything. */
export async function shuffleArtist(artistId: string): Promise<void> {
  if (!player.state.isShuffled) await attempt(api.playerToggleShuffle());
  await attempt(api.playerPlayArtist(artistId));
}

/** Backend picks zip vs per-song from the device settings (useZipDownload && !transcoding). */
export const transferAlbum = (devicePath: string, albumId: string): void => {
  void attempt(api.transferEnqueueAlbum(devicePath, albumId), 'Could not queue album');
};

/** Skips albums already fully on the device unless the device overwrites existing files. */
export const transferArtist = (devicePath: string, artistId: string): void => {
  void attempt(api.transferEnqueueArtist(devicePath, artistId), 'Could not queue artist');
};

export const transferSongs = (devicePath: string, songs: Song[]): void => {
  if (songs.length === 0) return;
  void attempt(api.transferEnqueueSongs(devicePath, songs), 'Could not queue songs');
};

/** Full album (with songs) or undefined after surfacing the error. */
export const fetchAlbum = (albumId: string): Promise<Album | undefined> => attempt(api.albumGet(albumId));

/** Album/artist menu label: single device reads "Transfer <noun>", several name the device. */
export const transferLabel = (devices: ConnectedDevice[], d: ConnectedDevice, noun: string): string =>
  devices.length === 1 ? `Transfer ${noun}` : `Transfer to ${d.label}`;

export const plural = (n: number, word: string): string => `${n} ${word}${n === 1 ? '' : 's'}`;

/** m:ss (song_row.dart `_fmt`). */
export function fmtDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}
