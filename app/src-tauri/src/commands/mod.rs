//! IPC commands, one module per area. Fallible commands reject with
//! `dapper_domain::AppError` (`{kind, message, code?}`).

pub mod devices;
pub mod import;
pub mod library;
pub mod lidarr;
pub mod player;
pub mod servers;
pub mod settings;
pub mod transfer;

/// Registers every command with Tauri and lists its name, from one list so
/// the two can't drift.
macro_rules! commands {
    ($($module:ident :: $name:ident),* $(,)?) => {
        #[cfg(test)]
        pub const COMMANDS: &[&str] = &[$(stringify!($name)),*];

        pub fn handler() -> impl Fn(tauri::ipc::Invoke) -> bool + Send + Sync + 'static {
            tauri::generate_handler![$($module::$name),*]
        }
    };
}

commands![
    servers::servers_list,
    servers::server_test,
    servers::server_add,
    servers::server_update,
    servers::server_remove,
    servers::server_select,
    library::library_sync,
    library::library_sync_status,
    library::artists_list,
    library::artist_albums,
    library::album_get,
    library::albums_recent,
    library::albums_window,
    library::songs_window,
    library::songs_ids,
    library::genres_list,
    library::genre_albums,
    library::search,
    library::starred_ids,
    library::star_set,
    library::rating_set,
    library::lyrics_get,
    library::playlists_list,
    library::playlist_get,
    library::playlist_create,
    library::playlist_rename,
    library::playlist_add_songs,
    library::playlist_remove_song,
    library::playlist_delete,
    library::song_update,
    library::mb_search_release_groups,
    library::album_cover_from_release_group,
    player::player_state,
    player::player_play_songs,
    player::player_play_album,
    player::player_play_artist,
    player::player_play_playlist,
    player::player_play_library,
    player::player_toggle,
    player::player_next,
    player::player_previous,
    player::player_seek,
    player::player_set_volume,
    player::player_toggle_shuffle,
    player::player_cycle_repeat,
    devices::devices_list,
    devices::device_eject,
    devices::device_settings_get,
    devices::device_settings_save,
    devices::device_settings_all,
    devices::device_scan,
    devices::device_album_sync,
    devices::device_artist_sync,
    devices::device_song_presence,
    devices::device_sync_plan,
    devices::device_browse,
    devices::device_list_dirs,
    devices::device_delete_files,
    devices::open_full_disk_access_settings,
    transfer::transfer_enqueue_songs,
    transfer::transfer_enqueue_album,
    transfer::transfer_enqueue_artist,
    transfer::transfer_enqueue_playlist,
    transfer::transfer_enqueue_albums,
    transfer::transfer_cancel,
    transfer::transfer_cancel_all,
    transfer::transfer_retry,
    transfer::transfer_retry_failed,
    transfer::transfer_pause,
    transfer::transfer_resume,
    transfer::transfer_clear_completed,
    transfer::transfer_tasks,
    transfer::transfer_paused,
    transfer::queue_album_status,
    transfer::queue_song_status,
    settings::app_settings_get,
    settings::app_settings_set_transfer_concurrency,
    settings::cache_clean,
    settings::cover_cache_size,
    settings::app_reset,
    lidarr::lidarr_instances,
    lidarr::lidarr_test,
    lidarr::lidarr_add,
    lidarr::lidarr_update,
    lidarr::lidarr_remove,
    lidarr::lidarr_select,
    lidarr::lidarr_root_folders,
    lidarr::lidarr_quality_profiles,
    lidarr::lidarr_custom_filters,
    lidarr::lidarr_artists,
    lidarr::lidarr_only_artists,
    lidarr::lidarr_artist_lookup,
    lidarr::lidarr_add_artist,
    lidarr::lidarr_artist_albums,
    lidarr::lidarr_album_lookup,
    lidarr::lidarr_add_album,
    lidarr::lidarr_search_artist,
    lidarr::lidarr_search_album,
    lidarr::lidarr_releases,
    lidarr::lidarr_grab,
    import::import_start,
    import::import_set_selection,
    import::import_manual_search,
    import::import_commit,
    import::import_reset,
    import::import_state,
];

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    /// Every `invoke('<name>'` in the UI's typed API is a registered command
    /// and vice versa.
    #[test]
    fn api_ts_commands_are_registered() {
        let api = include_str!("../../../ui/src/lib/api.ts");
        let invoked: BTreeSet<&str> = api
            .split("invoke<")
            .skip(1)
            .filter_map(|rest| {
                let start = rest.find("('")? + 2;
                let len = rest[start..].find('\'')?;
                Some(&rest[start..start + len])
            })
            .collect();
        assert!(!invoked.is_empty(), "no invoke calls found in api.ts");
        let registered: BTreeSet<&str> = super::COMMANDS.iter().copied().collect();
        let missing: Vec<_> = invoked.difference(&registered).collect();
        let unused: Vec<_> = registered.difference(&invoked).collect();
        assert!(missing.is_empty(), "invoked by api.ts but not registered: {missing:?}");
        assert!(unused.is_empty(), "registered but not in api.ts: {unused:?}");
        assert_eq!(super::COMMANDS.len(), registered.len(), "duplicate command registration");
    }
}
