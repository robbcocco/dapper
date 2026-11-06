//! Device path layout, filename templates, filename sanitising, zip entry matching.

mod byte_format;
pub mod dart_path;
mod resolver;
mod safe_filename;

pub use byte_format::format_bytes;
pub use dart_path::{basename, basename_without_extension, join, join_all};
pub use resolver::{
    artist_folder, build_album_folder, build_playlist_path, build_song_path, estimate_total_bytes, match_zip_entry,
    render_filename_template, validate_filename_template, validate_folder_template,
};
pub use safe_filename::{MAX_PATH_COMPONENT, ToSafeFilename, to_safe_filename, trunc_utf16, utf16_len};

#[cfg(test)]
mod tests;
#[cfg(test)]
mod fixture_tests;
