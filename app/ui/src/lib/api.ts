// Typed wrappers for every backend command and event (see IPC contract).
import type { UnlistenFn } from '@tauri-apps/api/event';
import { channel, invoke, onEvent } from './ipc';
import type * as T from './types';

const isWindows = typeof navigator !== 'undefined' && /windows/i.test(navigator.userAgent);

export function coverUrl(serverId: string, coverArtId: string, size: number): string {
  const path = `${encodeURIComponent(serverId)}/${encodeURIComponent(coverArtId)}?size=${size}`;
  return isWindows ? `http://cover.localhost/${path}` : `cover://localhost/${path}`;
}

// ---- servers ----
export const serversList = () => invoke<T.ServersState>('servers_list');
export const serverTest = (url: string, username: string, password: string) =>
  invoke<void>('server_test', { url, username, password });
export const serverAdd = (name: string, url: string, username: string, password: string) =>
  invoke<T.NavidromeServer>('server_add', { name, url, username, password });
/** `password: null` keeps the stored secret; the backend re-tests connectivity with it. */
export const serverUpdate = (id: string, name: string, url: string, username: string, password: string | null) =>
  invoke<T.NavidromeServer>('server_update', { id, name, url, username, password });
export const serverRemove = (id: string) => invoke<void>('server_remove', { id });
export const serverSelect = (id: string) => invoke<void>('server_select', { id });

// ---- library ----
export const librarySync = (force: boolean) => invoke<void>('library_sync', { force });
export const librarySyncStatus = () => invoke<T.SyncProgress>('library_sync_status');
export const artistsList = () => invoke<T.Artist[]>('artists_list');
export const artistAlbums = (artistId: string) => invoke<T.Album[]>('artist_albums', { artistId });
export const albumGet = (albumId: string) => invoke<T.Album>('album_get', { albumId });
export const albumsRecent = (limit: number) => invoke<T.Album[]>('albums_recent', { limit });
export const albumsWindow = (offset: number, limit: number, sort: T.AlbumSort) =>
  invoke<T.Page<T.Album>>('albums_window', { offset, limit, sort });
export const songsWindow = (offset: number, limit: number, sort: T.SongSort, desc: boolean) =>
  invoke<T.Page<T.Song>>('songs_window', { offset, limit, sort, desc });
export const songsIds = (sort: T.SongSort, desc: boolean) => invoke<string[]>('songs_ids', { sort, desc });
export const genresList = () => invoke<T.Genre[]>('genres_list');
export const genreAlbums = (genre: string) => invoke<T.Album[]>('genre_albums', { genre });
export const search = (query: string) => invoke<T.SearchResults>('search', { query });
export const starredIds = () => invoke<string[]>('starred_ids');
export const starSet = (id: string, starred: boolean) => invoke<void>('star_set', { id, starred });
export const ratingSet = (id: string, rating: number) => invoke<void>('rating_set', { id, rating });
export const lyricsGet = (songId: string) => invoke<T.Lyrics | null>('lyrics_get', { songId });
export const playlistsList = () => invoke<T.Playlist[]>('playlists_list');
export const playlistGet = (id: string) => invoke<T.Playlist>('playlist_get', { id });
export const playlistCreate = (name: string, songIds: string[]) =>
  invoke<T.Playlist>('playlist_create', { name, songIds });
export const playlistRename = (id: string, name: string) => invoke<void>('playlist_rename', { id, name });
export const playlistAddSongs = (id: string, songIds: string[]) =>
  invoke<void>('playlist_add_songs', { id, songIds });
export const playlistRemoveSong = (id: string, index: number) =>
  invoke<void>('playlist_remove_song', { id, index });
export const playlistDelete = (id: string) => invoke<void>('playlist_delete', { id });
export const songUpdate = (songId: string, fields: T.SongUpdateFields) =>
  invoke<void>('song_update', { songId, fields });
export const mbSearchReleaseGroups = (album: string, artist: string) =>
  invoke<T.MbReleaseGroup[]>('mb_search_release_groups', { album, artist });
export const albumCoverFromReleaseGroup = (albumId: string, mbid: string) =>
  invoke<void>('album_cover_from_release_group', { albumId, mbid });

// ---- playback ----
export const playerPlaySongs = (songs: T.Song[], startIndex: number) =>
  invoke<void>('player_play_songs', { songs, startIndex });
export const playerPlayAlbum = (albumId: string, startIndex: number) =>
  invoke<void>('player_play_album', { albumId, startIndex });
export const playerPlayArtist = (artistId: string) => invoke<void>('player_play_artist', { artistId });
export const playerPlayPlaylist = (playlistId: string, startIndex: number) =>
  invoke<void>('player_play_playlist', { playlistId, startIndex });
/** Plays the whole cached song list in the given table order, starting at `startIndex` (songs page). */
export const playerPlayLibrary = (sort: T.SongSort, desc: boolean, startIndex: number) =>
  invoke<void>('player_play_library', { sort, desc, startIndex });
export const playerToggle = () => invoke<void>('player_toggle');
export const playerNext = () => invoke<void>('player_next');
export const playerPrevious = () => invoke<void>('player_previous');
export const playerSeek = (positionMs: number) => invoke<void>('player_seek', { positionMs });
export const playerSetVolume = (volume: number) => invoke<void>('player_set_volume', { volume });
export const playerToggleShuffle = () => invoke<void>('player_toggle_shuffle');
export const playerCycleRepeat = () => invoke<void>('player_cycle_repeat');
/** Current player state + position, for initial render before the first `player-state` event. */
export const playerState = () =>
  invoke<{ state: T.PlayerState; position: T.PlayerPosition }>('player_state');

// ---- devices ----
export const devicesList = () => invoke<T.ConnectedDevice[]>('devices_list');
export const deviceEject = (path: string) => invoke<T.EjectResult>('device_eject', { path });
export const deviceSettingsGet = (devicePath: string) =>
  invoke<T.DeviceSettings>('device_settings_get', { devicePath });
export const deviceSettingsSave = (settings: T.DeviceSettings) =>
  invoke<void>('device_settings_save', { settings });
export const deviceSettingsAll = () => invoke<T.DeviceSettings[]>('device_settings_all');
export const deviceScan = (
  devicePath: string,
  prune: boolean,
  cleanTags: boolean,
  onProgress: (p: T.ScanProgress) => void,
) =>
  invoke<T.ScanReport>('device_scan', { devicePath, prune, cleanTags, onProgress: channel(onProgress) });
export const deviceAlbumSync = (devicePath: string) =>
  invoke<Record<string, T.AlbumSyncStatus>>('device_album_sync', { devicePath });
export const deviceArtistSync = (devicePath: string) =>
  invoke<Record<string, T.ArtistSyncStatus>>('device_artist_sync', { devicePath });
export const deviceSongPresence = (devicePath: string, songIds: string[]) =>
  invoke<Record<string, boolean>>('device_song_presence', { devicePath, songIds });
export const deviceSyncPlan = (devicePath: string, onProgress: (p: T.SyncPlanProgress) => void) =>
  invoke<T.LibrarySyncPlan>('device_sync_plan', { devicePath, onProgress: channel(onProgress) });
export const deviceBrowse = (devicePath: string, relPath: string) =>
  invoke<T.DeviceEntry[]>('device_browse', { devicePath, relPath });
export const deviceListDirs = (devicePath: string, relPath: string) =>
  invoke<T.DeviceEntry[]>('device_list_dirs', { devicePath, relPath });
/** Deletes files on the device (scan dialog duplicate resolution). Paths are absolute; the backend rejects any outside `devicePath`. */
export const deviceDeleteFiles = (devicePath: string, paths: string[]) =>
  invoke<void>('device_delete_files', { devicePath, paths });
export const openFullDiskAccessSettings = () => invoke<void>('open_full_disk_access_settings');

// ---- transfer ----
export const transferEnqueueSongs = (devicePath: string, songs: T.Song[]) =>
  invoke<void>('transfer_enqueue_songs', { devicePath, songs });
export const transferEnqueueAlbum = (devicePath: string, albumId: string) =>
  invoke<void>('transfer_enqueue_album', { devicePath, albumId });
export const transferEnqueueArtist = (devicePath: string, artistId: string) =>
  invoke<void>('transfer_enqueue_artist', { devicePath, artistId });
export const transferEnqueuePlaylist = (devicePath: string, playlistId: string) =>
  invoke<void>('transfer_enqueue_playlist', { devicePath, playlistId });
export const transferEnqueueAlbums = (devicePath: string, albumIds: string[], useZip: boolean) =>
  invoke<void>('transfer_enqueue_albums', { devicePath, albumIds, useZip });
export const transferCancel = (taskId: string) => invoke<void>('transfer_cancel', { taskId });
export const transferCancelAll = (devicePath: string | null) => invoke<void>('transfer_cancel_all', { devicePath });
export const transferRetry = (taskId: string) => invoke<void>('transfer_retry', { taskId });
export const transferRetryFailed = (devicePath: string | null) =>
  invoke<void>('transfer_retry_failed', { devicePath });
export const transferPause = (devicePath: string | null) => invoke<void>('transfer_pause', { devicePath });
export const transferResume = (devicePath: string | null) => invoke<void>('transfer_resume', { devicePath });
export const transferClearCompleted = () => invoke<void>('transfer_clear_completed');
export const transferTasks = () => invoke<T.TransferTask[]>('transfer_tasks');
export const transferPaused = () => invoke<T.TransferPausedState>('transfer_paused');
export const queueAlbumStatus = () => invoke<Record<string, T.QueueItemStatus>>('queue_album_status');
export const queueSongStatus = () => invoke<Record<string, T.QueueItemStatus>>('queue_song_status');

// ---- settings / app ----
export const appSettingsGet = () => invoke<T.AppSettings>('app_settings_get');
export const appSettingsSetTransferConcurrency = (n: number) =>
  invoke<T.AppSettings>('app_settings_set_transfer_concurrency', { n });
/** Cleans the cover cache and tmp/staging files (staging is skipped while transfers are active). */
export const cacheClean = () => invoke<T.CacheCleanResult>('cache_clean');
/** Wipes app data and credentials; the backend then emits `server-changed {selectedId: null}`. */
export const appReset = () => invoke<void>('app_reset');
export const coverCacheSize = () => invoke<number>('cover_cache_size');

// ---- lidarr ----
export const lidarrInstances = () => invoke<T.LidarrInstancesState>('lidarr_instances');
export const lidarrTest = (url: string, apiKey: string) => invoke<void>('lidarr_test', { url, apiKey });
export const lidarrAdd = (name: string, url: string, apiKey: string) =>
  invoke<T.LidarrInstance>('lidarr_add', { name, url, apiKey });
/** `apiKey: null` keeps the stored key; the backend re-tests connectivity with it. */
export const lidarrUpdate = (instance: T.LidarrInstance, apiKey: string | null) =>
  invoke<void>('lidarr_update', { instance, apiKey });
export const lidarrRemove = (id: string) => invoke<void>('lidarr_remove', { id });
export const lidarrSelect = (id: string) => invoke<void>('lidarr_select', { id });
export const lidarrRootFolders = () => invoke<T.LidarrRootFolder[]>('lidarr_root_folders');
export const lidarrQualityProfiles = () => invoke<T.LidarrQualityProfile[]>('lidarr_quality_profiles');
export const lidarrCustomFilters = () => invoke<T.LidarrCustomFilter[]>('lidarr_custom_filters');
export const lidarrArtists = () => invoke<T.LidarrArtist[]>('lidarr_artists');
export const lidarrOnlyArtists = () => invoke<T.LidarrArtist[]>('lidarr_only_artists');
export const lidarrArtistLookup = (term: string) => invoke<T.LidarrArtist[]>('lidarr_artist_lookup', { term });
export const lidarrAddArtist = (artist: T.LidarrArtist, rootFolderPath: string, qualityProfileId: number) =>
  invoke<T.LidarrArtist>('lidarr_add_artist', { artist, rootFolderPath, qualityProfileId });
export const lidarrArtistAlbums = (artistId: number) =>
  invoke<T.LidarrAlbum[]>('lidarr_artist_albums', { artistId });
export const lidarrAlbumLookup = (term: string) => invoke<T.LidarrAlbumLookup[]>('lidarr_album_lookup', { term });
/** Returns the new Lidarr album id. */
export const lidarrAddAlbum = (
  lookup: T.LidarrAlbumLookup,
  rootFolderPath: string,
  qualityProfileId: number,
  searchOnAdd: boolean,
) => invoke<number>('lidarr_add_album', { lookup, rootFolderPath, qualityProfileId, searchOnAdd });
export const lidarrSearchArtist = (artistId: number) => invoke<void>('lidarr_search_artist', { artistId });
export const lidarrSearchAlbum = (albumId: number) => invoke<void>('lidarr_search_album', { albumId });
export const lidarrReleases = (albumId: number) => invoke<T.LidarrRelease[]>('lidarr_releases', { albumId });
export const lidarrGrab = (release: T.LidarrRelease) => invoke<void>('lidarr_grab', { release });

// ---- playlist import ----
export const importStart = (url: string) => invoke<void>('import_start', { url });
export const importSetSelection = (index: number, songId: string | null, song: T.Song | null) =>
  invoke<void>('import_set_selection', { index, songId, song });
export const importManualSearch = (query: string) => invoke<T.Song[]>('import_manual_search', { query });
export const importCommit = (name: string | null) => invoke<void>('import_commit', { name });
export const importReset = () => invoke<void>('import_reset');
export const importState = () => invoke<T.ImportState>('import_state');

// ---- events ----
type Sub<P> = (cb: (payload: P) => void) => Promise<UnlistenFn>;
const sub =
  <P>(event: string): Sub<P> =>
  (cb) =>
    onEvent<P>(event, cb);

export const onServerChanged = sub<T.ServerChanged>('server-changed');
export const onLibrarySync = sub<T.SyncProgress>('library-sync');
export const onLibraryChanged = sub<Record<string, never>>('library-changed');
export const onPlayerState = sub<T.PlayerState>('player-state');
export const onPlayerPosition = sub<T.PlayerPosition>('player-position');
export const onDevices = sub<T.ConnectedDevice[]>('devices');
export const onScrobbleImport = sub<T.ScrobbleImportResult>('scrobble-import');
export const onManifestRevision = sub<number>('manifest-revision');
export const onTransferTasks = sub<T.TransferTask[]>('transfer-tasks');
export const onTransferProgress = sub<T.TransferProgress>('transfer-progress');
export const onTransferPaused = sub<T.TransferPausedState>('transfer-paused');
export const onQueueStatus = sub<T.QueueStatus>('queue-status');
export const onActionError = sub<T.ActionError>('action-error');
export const onLidarrChanged = sub<unknown>('lidarr-changed');
export const onImportState = sub<T.ImportState>('import-state');
