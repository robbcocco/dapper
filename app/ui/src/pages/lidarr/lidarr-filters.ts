// Port of LidarrCustomFilter.matches / LidarrFilterCondition.matches and
// filteredLidarrArtistsProvider (lib/domain/models/lidarr_models.dart,
// lib/application/lidarr/lidarr_notifier.dart).
import type { LidarrArtist, LidarrCustomFilter, LidarrFilterCondition } from '../../lib/types';
import type { LidarrLibraryFilter } from '../../lib/stores/lidarr-nav.svelte';

export const isInLidarr = (a: LidarrArtist): boolean => a.id > 0;

/** Tracked but no track files downloaded yet. */
export const isMissing = (a: LidarrArtist): boolean =>
  isInLidarr(a) && a.totalTrackCount > 0 && a.trackFileCount === 0;

function scalarField(key: string, a: LidarrArtist): string | null {
  switch (key) {
    case 'monitored':
      return String(a.monitored);
    case 'status':
      return a.status;
    case 'qualityProfileId':
      return String(a.qualityProfileId);
    case 'rootFolderPath':
      return a.rootFolderPath;
    case 'albumCount':
      return String(a.albumCount);
    case 'trackFileCount':
      return String(a.trackFileCount);
    case 'totalTrackCount':
      return String(a.totalTrackCount);
    case 'percentOfTracks':
      return (a.totalTrackCount > 0 ? (a.trackFileCount / a.totalTrackCount) * 100 : 0).toFixed(1);
    default:
      return null;
  }
}

function num(s: string): number | null {
  if (s.trim() === '') return null;
  const n = Number(s);
  return Number.isNaN(n) ? null : n;
}

const eq = (a: string, b: string): boolean => a.toLowerCase() === b.toLowerCase();

function conditionMatches(c: LidarrFilterCondition, artist: LidarrArtist): boolean {
  const { key, values, operator } = c;
  if (key === 'tags') {
    const ids = new Set(artist.tagIds.map(String));
    if (operator === 'contains') return values.some((v) => ids.has(v));
    if (operator === 'notContain') return values.every((v) => !ids.has(v));
    return true;
  }
  if (key === 'genres') {
    const gs = new Set(artist.genres.map((g) => g.toLowerCase()));
    if (operator === 'contains') return values.some((v) => gs.has(v.toLowerCase()));
    if (operator === 'notContain') return values.every((v) => !gs.has(v.toLowerCase()));
    return true;
  }

  const field = scalarField(key, artist);
  if (field === null) return true; // unknown field — pass through
  switch (operator) {
    case 'equal':
      return values.some((v) => eq(field, v));
    case 'notEqual':
      return values.every((v) => !eq(field, v));
    case 'contains':
      return values.some((v) => field.toLowerCase().includes(v.toLowerCase()));
    case 'notContain':
      return values.every((v) => !field.toLowerCase().includes(v.toLowerCase()));
    case 'lessThan': {
      const n = num(field);
      return n !== null && values.length > 0 && n < (num(values[0]!) ?? 0);
    }
    case 'greaterThan': {
      const n = num(field);
      return n !== null && values.length > 0 && n > (num(values[0]!) ?? 0);
    }
    default:
      return true;
  }
}

export const customFilterMatches = (f: LidarrCustomFilter, a: LidarrArtist): boolean =>
  f.conditions.every((c) => conditionMatches(c, a));

/** All artists after applying whichever filter is active (custom filter wins). */
export function filterArtists(
  all: LidarrArtist[],
  libraryFilter: LidarrLibraryFilter,
  customFilterId: number | null,
  customFilters: LidarrCustomFilter[],
): LidarrArtist[] {
  if (customFilterId !== null) {
    const cf = customFilters.find((f) => f.id === customFilterId);
    return cf ? all.filter((a) => customFilterMatches(cf, a)) : all;
  }
  switch (libraryFilter) {
    case 'all':
      return all;
    case 'monitored':
      return all.filter((a) => a.monitored);
    case 'unmonitored':
      return all.filter((a) => !a.monitored);
    case 'missing':
      return all.filter(isMissing);
  }
}

export const albumTypeOrder = ['album', 'ep', 'single', 'other'] as const;

export const albumTypeLabel: Record<(typeof albumTypeOrder)[number], string> = {
  album: 'Albums',
  ep: 'EPs',
  single: 'Singles',
  other: 'Other',
};

/** LidarrAlbum.year: leading `YYYY` of releaseDate. */
export function releaseYear(releaseDate: string | null): number | null {
  if (!releaseDate) return null;
  const head = releaseDate.split('-')[0] ?? '';
  if (!/^[+-]?\d+$/.test(head)) return null;
  return parseInt(head, 10);
}

/** LidarrRelease.formattedSize. */
export function formatReleaseSize(size: number): string {
  if (size <= 0) return '—';
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(0)} KB`;
  if (size < 1024 * 1024 * 1024) return `${(size / (1024 * 1024)).toFixed(0)} MB`;
  return `${(size / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}
