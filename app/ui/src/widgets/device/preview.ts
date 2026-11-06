// Preview-only ports of the Dart path helpers used by the device settings dialog:
// lib/core/extensions/string_extensions.dart (toSafeFilename),
// lib/application/transfer/transfer_path_resolver.dart (renderFilenameTemplate,
// validateFilenameTemplate, validateFolderTemplate) and
// lib/domain/models/device_settings.dart (validateMusicRootPath, resolvedMusicRoot).
// Real paths are always computed by the backend (dapper-paths); keep these in lockstep.
import type { Song, TranscodeFormat } from '../../lib/types';

// Windows blocks these as filenames even with an extension.
const windowsReserved = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i;

export function toSafeFilename(s: string): string {
  let result = s
    .replaceAll('…', '...')
    .replaceAll('–', '-')
    .replaceAll('—', '-')
    .replace(/[/\\]/g, '-')
    .replace(/[:*?"<>|]/g, '')
    .replace(/[\x00-\x1F\x7F]/g, '')
    .replace(/ {2,}/g, ' ')
    .replace(/^[. ]+|[. ]+$/g, '');
  if (windowsReserved.test(result)) result = `_${result}`;
  return result === '' ? '_' : result;
}

/** Subset of Song fields the templates read. */
export type TemplateSong = Pick<Song, 'title' | 'album' | 'artist' | 'albumArtist' | 'track' | 'discNumber' | 'year'>;

/** Sample song shown in the settings dialog previews. */
export const sampleSong: TemplateSong & Pick<Song, 'suffix'> = {
  title: 'Astronomy Domine',
  album: 'The Piper at the Gates of Dawn',
  artist: 'Pink Floyd',
  albumArtist: 'Pink Floyd',
  track: 1,
  discNumber: 1,
  year: 1967,
  suffix: 'flac',
};

const templateToken = /\{(\w+)(?::(\d+))?\}/g;

const int64Min = -(2n ** 63n);
const int64Max = 2n ** 63n - 1n;

// Dart `int.tryParse` without radix: surrounding whitespace ignored, optional sign,
// decimal or 0x-prefixed hex; decimal must fit int64, hex up to 64 bits wraps.
function dartTryParseInt(raw: string): bigint | null {
  const m = /^([+-]?)(?:0[xX]([0-9a-fA-F]+)|([0-9]+))$/.exec(raw.trim());
  if (!m) return null;
  const negative = m[1] === '-';
  if (m[2] !== undefined) {
    const v = BigInt(`0x${m[2]}`);
    if (v > 2n ** 64n - 1n) return null;
    const signed = BigInt.asIntN(64, v);
    return negative ? BigInt.asIntN(64, -signed) : signed;
  }
  const v = negative ? -BigInt(m[3] ?? '0') : BigInt(m[3] ?? '0');
  return v < int64Min || v > int64Max ? null : v;
}

function tokenValue(key: string, song: TemplateSong): string | null {
  switch (key) {
    case 'track':
      return song.track?.toString() ?? null;
    case 'disc':
      return (song.discNumber ?? 1).toString();
    case 'year':
      return song.year?.toString() ?? null;
    case 'title':
      return song.title;
    case 'artist':
      return song.artist ?? song.albumArtist;
    case 'albumArtist':
      return song.albumArtist ?? song.artist;
    case 'album':
      return song.album;
    default:
      return null;
  }
}

// Bounds the zero-padding so a typo like `{track:99999999}` can't freeze the dialog.
const maxPreviewPad = 1024;

/** Unknown tokens are kept verbatim; the result is NOT sanitized. */
export function renderFilenameTemplate(template: string, song: TemplateSong): string {
  if (template === '') return song.title;
  return template.replace(templateToken, (whole: string, key: string, width: string | undefined) => {
    const raw = tokenValue(key, song);
    if (raw === null) return whole;
    if (width !== undefined) {
      const n = dartTryParseInt(raw);
      if (n !== null) return n.toString().padStart(Math.min(Number(width), maxPreviewPad), '0');
    }
    return raw;
  });
}

export function validateFilenameTemplate(template: string): string | null {
  const trimmed = template.trim();
  if (trimmed === '') return 'Template cannot be empty';
  if (!trimmed.includes('{title}') && !trimmed.includes('{track')) {
    return 'Template must include {title} or {track} to avoid collisions';
  }
  if (trimmed.includes('/') || trimmed.includes('\\')) return 'Template cannot contain path separators';
  return null;
}

export function validateFolderTemplate(template: string): string | null {
  const trimmed = template.trim();
  if (trimmed === '') return 'Template cannot be empty';
  if (!trimmed.includes('{album}') && !trimmed.includes('{artist}')) {
    return 'Template must include {album} or {artist}';
  }
  if (trimmed.includes('{title}')) return 'Folder template cannot include {title}';
  return null;
}

export function validateMusicRootPath(input: string): string | null {
  const trimmed = input.trim();
  if (trimmed === '') return null;
  if (trimmed.startsWith('/') || trimmed.startsWith('\\')) return 'Use a relative path (no leading slash)';
  if (trimmed.length >= 2 && trimmed[1] === ':') return 'Use a relative path (no drive letter)';
  for (const seg of trimmed.replaceAll('\\', '/').split('/')) {
    if (seg === '..') return "Path cannot contain '..'";
  }
  return null;
}

/** Custom filename preview line (`_CustomTemplateField`). */
export function filenamePreview(template: string): string {
  return `${toSafeFilename(renderFilenameTemplate(template, sampleSong))}.flac`;
}

/** Custom folder preview line (`_CustomFolderField`); segments joined with ` / `. */
export function folderPreview(template: string): string {
  return template
    .replaceAll('\\', '/')
    .split('/')
    .map((seg) => toSafeFilename(renderFilenameTemplate(seg, sampleSong)))
    .filter((s) => s !== '')
    .join(' / ');
}

const isWindows = typeof navigator !== 'undefined' && /windows/i.test(navigator.userAgent);
const sep = isWindows ? '\\' : '/';

/** Relative music-root components, as `DeviceSettings.resolvedMusicRoot` splits them. */
export function musicRootParts(musicRootFolder: string): string[] {
  const trimmed = musicRootFolder.trim();
  if (trimmed === '') return [];
  return trimmed
    .replaceAll('\\', '/')
    .split('/')
    .filter((s) => s !== '' && s !== '.');
}

/** `p.joinAll` with the platform separator. */
export function joinPath(base: string, ...parts: string[]): string {
  let out = base;
  for (const part of parts) {
    if (out === '' || out.endsWith('/') || out.endsWith('\\')) out += part;
    else out += sep + part;
  }
  return out;
}

/** Absolute music root on the device (`DeviceSettings.resolvedMusicRoot`). */
export function resolvedMusicRoot(devicePath: string, musicRootFolder: string): string {
  return joinPath(devicePath, ...musicRootParts(musicRootFolder));
}

/** Last path component, like `p.basename` (empty for a bare root such as `/`). */
export function basename(path: string): string {
  const trimmed = path.replace(/[/\\]+$/, '');
  const i = Math.max(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'));
  return trimmed.slice(i + 1);
}

export const transcodeLabels: Record<TranscodeFormat, string> = {
  original: 'Original',
  mp3: 'MP3',
  opus: 'Opus',
  aac: 'AAC',
};
