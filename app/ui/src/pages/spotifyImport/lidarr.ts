import * as api from '../../lib/api';
import { toAppError } from '../../lib/ipc';
import type { LidarrAlbumType, LidarrInstance, LidarrRelease } from '../../lib/types';

export const albumTypeOrder: LidarrAlbumType[] = ['album', 'ep', 'single', 'other'];

export const albumTypeLabel: Record<LidarrAlbumType, string> = {
  album: 'Albums',
  ep: 'EPs',
  single: 'Singles',
  other: 'Other',
};

/** `LidarrAlbum.year` / `LidarrAlbumLookup.year`: leading year of `releaseDate`. */
export function releaseYear(releaseDate: string | null): number | null {
  if (!releaseDate) return null;
  const y = Number.parseInt(releaseDate.split('-')[0]!, 10);
  return Number.isNaN(y) ? null : y;
}

/** `LidarrRelease.formattedSize`. */
export function formattedSize(r: LidarrRelease): string {
  const size = r.size;
  if (size <= 0) return '—';
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(0)} KB`;
  if (size < 1024 * 1024 * 1024) return `${(size / (1024 * 1024)).toFixed(0)} MB`;
  return `${(size / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

/** Selected Lidarr instance (lidarrClientProvider is non-null exactly when one is selected). */
export async function selectedLidarrInstance(): Promise<LidarrInstance | null> {
  try {
    const s = await api.lidarrInstances();
    return s.instances.find((i) => i.id === s.selectedId) ?? null;
  } catch {
    return null;
  }
}

export const errMsg = (e: unknown): string => toAppError(e).message;

export const missingDefaultsMessage = 'Set a root folder + quality profile in Settings → Lidarr first.';
