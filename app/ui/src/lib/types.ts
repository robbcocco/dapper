// TS mirrors of the serde JSON of dapper-domain / dapper-import types plus the
// auxiliary IPC payloads in the IPC contract. Keep in sync with app/crates.

export type AppErrorKind =
  | 'network'
  | 'subsonic'
  | 'auth'
  | 'notFound'
  | 'storage'
  | 'io'
  | 'cancelled'
  | 'other';

export interface AppError {
  kind: AppErrorKind;
  message: string;
  code?: number;
}

// ---- domain ----

export interface Song {
  id: string;
  title: string;
  albumId: string | null;
  artistId: string | null;
  album: string | null;
  artist: string | null;
  duration: number | null;
  bitRate: number | null;
  contentType: string | null;
  suffix: string | null;
  size: number | null;
  coverArtId: string | null;
  track: number | null;
  discNumber: number | null;
  year: number | null;
  genre: string | null;
  albumArtist: string | null;
  userRating: number | null;
  starred: string | null;
}

export interface Album {
  id: string;
  name: string;
  artistId: string | null;
  artist: string | null;
  coverArtId: string | null;
  year: number | null;
  genre: string | null;
  songCount: number;
  duration: number;
  songs: Song[];
  userRating: number | null;
  starred: string | null;
  created: string | null;
}

export interface Artist {
  id: string;
  name: string;
  coverArtId: string | null;
  albumCount: number;
  musicBrainzId: string | null;
}

export interface AppSettings {
  transferConcurrency: number;
}

export interface ConnectedDevice {
  path: string;
  label: string;
  totalBytes: number;
  availableBytes: number;
}

export interface EjectResult {
  success: boolean;
  error: string | null;
}

export type FolderStructure = 'artistAlbum' | 'artistAlbumYear' | 'artistOnly' | 'flat' | 'custom';
export type FilenameFormat = 'none' | 'track' | 'discTrack' | 'custom';
export type TranscodeFormat = 'original' | 'mp3' | 'opus' | 'aac';

export interface DeviceSettings {
  devicePath: string;
  musicRootFolder: string;
  playlistFolder: string;
  folderStructure: FolderStructure;
  filenameFormat: FilenameFormat;
  includeYear: boolean;
  overwriteExisting: boolean;
  transcodeFormat: TranscodeFormat;
  transcodeMaxBitRate: number | null;
  useZipDownload: boolean;
  customFilenameTemplate: string;
  customFolderTemplate: string;
  autoCleanMetadata: boolean;
  autoShrinkCoverArt: boolean;
}

export interface Genre {
  name: string;
  songCount: number;
  albumCount: number;
}

export interface LidarrInstance {
  id: string;
  name: string;
  url: string;
  defaultRootFolderId?: number;
  defaultRootFolderPath?: string;
  defaultQualityProfileId?: number;
  defaultQualityProfileName?: string;
}

export interface LidarrArtist {
  id: number;
  mbid: string;
  name: string;
  monitored: boolean;
  status: string | null;
  rootFolderPath: string | null;
  posterUrl: string | null;
  overview: string | null;
  albumCount: number;
  trackFileCount: number;
  totalTrackCount: number;
  qualityProfileId: number;
  tagIds: number[];
  genres: string[];
}

export type LidarrAlbumType = 'album' | 'ep' | 'single' | 'other';

export interface LidarrAlbum {
  id: number;
  title: string;
  monitored: boolean;
  hasFile: boolean;
  albumType: LidarrAlbumType;
  releaseDate: string | null;
  coverUrl: string | null;
}

export interface LidarrAlbumLookup {
  lidarrAlbumId: number;
  foreignAlbumId: string;
  title: string;
  artistName: string;
  artistMbid: string;
  releaseDate: string | null;
  coverUrl: string | null;
  albumType: LidarrAlbumType | null;
  raw: Record<string, unknown>;
}

export interface LidarrRelease {
  guid: string;
  title: string;
  indexer: string;
  size: number;
  protocol: string;
  quality: string;
  ageInDays: number;
  rejected: boolean;
  rejections: string[];
  seeders: number | null;
  leechers: number | null;
  raw: Record<string, unknown>;
}

export interface LidarrRootFolder {
  id: number;
  path: string;
}

export interface LidarrQualityProfile {
  id: number;
  name: string;
}

export interface LidarrFilterCondition {
  key: string;
  values: string[];
  operator: string;
}

export interface LidarrCustomFilter {
  id: number;
  label: string;
  conditions: LidarrFilterCondition[];
}

export interface LyricsLine {
  text: string;
  startMs: number | null;
}

export interface Lyrics {
  lines: LyricsLine[];
  synced: boolean;
  lang: string | null;
}

export interface MbReleaseGroup {
  id: string;
  title: string;
  artistName: string | null;
  firstReleaseDate: string | null;
}

export interface NavidromeServer {
  id: string;
  name: string;
  url: string;
  username: string;
}

export interface Playlist {
  id: string;
  name: string;
  comment: string | null;
  coverArtId: string | null;
  songCount: number;
  duration: number;
  songs: Song[];
}

export interface SearchResults {
  artists: Artist[];
  albums: Album[];
  songs: Song[];
}

export interface SpotifyTrack {
  title: string;
  artist: string;
  album: string | null;
  durationMs: number | null;
}

export type PlaylistProvider = 'spotify' | 'tidal';

export interface SpotifyPlaylistData {
  name: string;
  tracks: SpotifyTrack[];
  truncated: boolean;
  provider: PlaylistProvider;
}

export type AlbumSyncStatus = 'absent' | 'partial' | 'full';
export type ArtistSyncStatus = 'full' | 'partial';
export type RepeatMode = 'none' | 'one' | 'all';

export type TransferStatus = 'queued' | 'inProgress' | 'completed' | 'failed' | 'cancelled';

export interface TransferTask {
  id: string;
  song: Song;
  devicePath: string;
  status: TransferStatus;
  bytesReceived: number;
  totalBytes: number;
  errorMessage: string | null;
  zipGroupId: string | null;
  zipSourceId: string | null;
}

// ---- import ----

export interface RankedSong {
  song: Song;
  score: number;
}

export interface TrackMatch {
  source: SpotifyTrack;
  candidates: RankedSong[];
  bestScore: number;
  selectedId: string | null;
}

export type ImportState =
  | { kind: 'idle' }
  | { kind: 'scraping' }
  | { kind: 'matching'; playlistName: string; done: number; total: number }
  | {
      kind: 'review';
      playlistName: string;
      truncated: boolean;
      matches: TrackMatch[];
      autoMatchedCount: number;
      unmatchedCount: number;
    }
  | { kind: 'creating' }
  | { kind: 'done'; playlistName: string; importedCount: number; skippedCount: number }
  | { kind: 'error'; message: string; tracks: SpotifyTrack[] | null };

// ---- auxiliary IPC payloads ----

export interface Page<T> {
  total: number;
  items: T[];
}

export type AlbumSort = 'name' | 'artist' | 'year' | 'recent';
export type SongSort = 'title' | 'artist' | 'album' | 'year' | 'duration' | 'track';

export type SyncPhase =
  | 'idle'
  | 'checking'
  | 'artists'
  | 'albums'
  | 'songs'
  | 'starred'
  | 'genres'
  | 'playlists'
  | 'done';

export interface SyncProgress {
  running: boolean;
  phase: SyncPhase;
  done: number;
  total: number | null;
  lastSyncedAt: string | null;
  error: string | null;
}

export interface PlayerPosition {
  positionMs: number;
  durationMs: number;
}

export interface PlayerState {
  currentSong: Song | null;
  queue: Song[];
  currentIndex: number;
  isPlaying: boolean;
  isBuffering: boolean;
  durationMs: number;
  volume: number;
  isShuffled: boolean;
  repeatMode: RepeatMode;
  errorMessage: string | null;
}

export interface QueueItemStatus {
  active: boolean;
  queued: boolean;
}

export interface QueueStatus {
  albums: Record<string, QueueItemStatus>;
  songs: Record<string, QueueItemStatus>;
}

/** Port of device_scan.dart `DeviceDuplicate`. */
export interface DeviceDuplicate {
  songId: string;
  title: string;
  folderPaths: string[];
}

/** Port of device_scan.dart `FileDuplicate`. */
export interface FileDuplicate {
  folderPath: string;
  filenames: string[];
  correctFilename: string | null;
}

/** Port of device_prune.dart `PruneResult`. */
export interface PruneResult {
  songsRemoved: number;
  bytesFreed: number;
  errors: string[];
}

/** Port of device_tag_sanitize.dart `TagSanitizeResult`. */
export interface TagSanitizeResult {
  filesScanned: number;
  filesSkipped: number;
  filesModified: number;
  coversShrunk: number;
  bytesFreed: number;
  errors: string[];
}

/** Port of device_scan.dart `DeviceScanResult` plus optional prune / tag-clean results. */
export interface ScanReport {
  albumsScanned: number;
  albumsMatched: number;
  songsMatched: number;
  songsTotal: number;
  manifestDuplicates: DeviceDuplicate[];
  fileDuplicates: FileDuplicate[];
  prune: PruneResult | null;
  clean: TagSanitizeResult | null;
}

export interface ScanProgress {
  phase: string;
  done: number;
  total: number | null;
}

export interface LibrarySyncPlan {
  unsynced: Album[];
  missingSongs: number;
  missingAlbums: number;
}

export interface SyncPlanProgress {
  scanned: number;
}

export type DeviceEntryKind = 'dir' | 'audio' | 'playlist' | 'other';

export interface DeviceEntry {
  name: string;
  path: string;
  isDir: boolean;
  size: number | null;
  kind: DeviceEntryKind;
}

/** Port of scrobble_importer.dart `ScrobbleImportResult`. */
export interface ScrobbleImportResult {
  devicePath: string;
  parsed: number;
  matched: number;
  submitted: number;
  unmatched: number;
  errors: number;
}

export interface ServersState {
  servers: NavidromeServer[];
  selectedId: string | null;
}

export interface ServerChanged {
  selectedId: string | null;
}

export interface LidarrInstancesState {
  instances: LidarrInstance[];
  selectedId: string | null;
}

export interface TransferPausedState {
  anyPaused: boolean;
  devices: string[];
}

/** taskId → [received, total] */
export type TransferProgress = Record<string, [number, number]>;

export interface SongUpdateFields {
  title?: string;
  artist?: string;
  album?: string;
  albumArtist?: string;
  track?: number;
  disc?: number;
  year?: number;
  genre?: string;
}

export interface CacheCleanResult {
  filesRemoved: number;
  bytesFreed: number;
  skippedStaging: boolean;
}

export interface ActionError {
  message: string;
}
