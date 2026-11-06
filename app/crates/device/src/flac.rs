//! FLAC metadata cleanup for DAPs: Vorbis-comment sanitising (in place,
//! absorbing freed bytes into PADDING) and embedded cover shrinking (which
//! rewrites metadata and moves the audio frames so the file really shrinks).
//!
//! Path-based functions skip anything not named `*.flac` and leave files
//! that don't parse cleanly untouched. Audio frames are always streamed,
//! never held in memory.

use std::fs::{File, OpenOptions};
use std::io::{self, Cursor, Read, Seek, SeekFrom, Write};
use std::path::Path;

use fast_image_resize::images::Image;
use fast_image_resize::{FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};

/// Shanling M-series DAPs have a 320x240 LCD; larger covers waste space.
pub const DEFAULT_PICTURE_MAX_EDGE: u32 = 320;
pub const DEFAULT_PICTURE_JPEG_QUALITY: u8 = 85;

// LYRICS*: large multi-line values misalign the Shanling M-series tag parser,
// which then shows e.g. GENRE in the title column. MAJOR_BRAND etc.: m4a
// container atoms ffmpeg copies verbatim when transcoding; they trip the same
// parsers.
const DROP_KEYS: [&str; 6] =
    ["LYRICS", "UNSYNCEDLYRICS", "SYNCEDLYRICS", "MAJOR_BRAND", "MINOR_VERSION", "COMPATIBLE_BRANDS"];
// Collapsed to their first value; multi-value GENRE triggers the same bug.
const SINGLE_VALUE_KEYS: [&str; 1] = ["GENRE"];

const BLOCK_PADDING: u8 = 1;
const BLOCK_VORBIS_COMMENT: u8 = 4;
const BLOCK_PICTURE: u8 = 6;
const MAX_BLOCK_SIZE: usize = 0xFF_FFFF;
const MAX_BLOCKS: usize = 128;
const FLAC_MAGIC: &[u8; 4] = b"fLaC";
const COPY_BUFFER: usize = 8 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlacCleanOptions {
    pub sanitize_tags: bool,
    pub shrink_picture: bool,
    pub max_edge: u32,
    pub quality: u8,
}

impl FlacCleanOptions {
    /// Both steps toggled like `DeviceSettings.autoCleanMetadata` /
    /// `autoShrinkCoverArt`, with the default cover target.
    pub fn new(sanitize_tags: bool, shrink_picture: bool) -> Self {
        Self { sanitize_tags, shrink_picture, max_edge: DEFAULT_PICTURE_MAX_EDGE, quality: DEFAULT_PICTURE_JPEG_QUALITY }
    }

    fn is_noop(&self) -> bool {
        !self.sanitize_tags && !self.shrink_picture
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct FlacCleanOutcome {
    pub tags_changed: bool,
    pub picture_shrunk: bool,
}

impl FlacCleanOutcome {
    pub fn modified(&self) -> bool {
        self.tags_changed || self.picture_shrunk
    }
}

pub fn is_flac_path(path: &Path) -> bool {
    path.to_string_lossy().to_lowercase().ends_with(".flac")
}

struct MetaBlock {
    block_type: u8,
    is_last: bool,
    body: Vec<u8>,
}

struct FlacMetadata {
    blocks: Vec<MetaBlock>,
    /// Byte offset of the first audio frame in the source.
    audio_start: u64,
}

fn read_exact_or_eof(r: &mut impl Read, buf: &mut [u8]) -> io::Result<bool> {
    match r.read_exact(buf) {
        Ok(()) => Ok(true),
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => Ok(false),
        Err(e) => Err(e),
    }
}

/// `Ok(None)` when the stream is not a cleanly parseable FLAC.
fn read_metadata(r: &mut impl Read) -> io::Result<Option<FlacMetadata>> {
    let mut magic = [0u8; 4];
    if !read_exact_or_eof(r, &mut magic)? || &magic != FLAC_MAGIC {
        return Ok(None);
    }
    let mut blocks = Vec::new();
    let mut audio_start = 4u64;
    loop {
        let mut header = [0u8; 4];
        if !read_exact_or_eof(r, &mut header)? {
            return Ok(None);
        }
        let is_last = header[0] & 0x80 != 0;
        let block_type = header[0] & 0x7f;
        let size = (usize::from(header[1]) << 16) | (usize::from(header[2]) << 8) | usize::from(header[3]);
        // Grows with the bytes actually present, so a corrupt 16 MiB size
        // field on a short file can't force a large allocation.
        let mut body = Vec::with_capacity(size.min(64 * 1024));
        if r.by_ref().take(size as u64).read_to_end(&mut body)? < size {
            return Ok(None);
        }
        blocks.push(MetaBlock { block_type, is_last, body });
        audio_start += 4 + size as u64;
        if is_last {
            break;
        }
        if blocks.len() > MAX_BLOCKS {
            return Ok(None);
        }
    }
    Ok(Some(FlacMetadata { blocks, audio_start }))
}

fn serialize_metadata(blocks: &[MetaBlock]) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(4 + blocks.iter().map(|b| 4 + b.body.len()).sum::<usize>());
    out.extend_from_slice(FLAC_MAGIC);
    for b in blocks {
        let size = b.body.len();
        if size > MAX_BLOCK_SIZE {
            return None;
        }
        out.push(if b.is_last { 0x80 } else { 0 } | (b.block_type & 0x7f));
        out.extend_from_slice(&[(size >> 16) as u8, (size >> 8) as u8, size as u8]);
        out.extend_from_slice(&b.body);
    }
    Some(out)
}

struct Reader<'a> {
    body: &'a [u8],
    off: usize,
}

impl<'a> Reader<'a> {
    fn u32_le(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.bytes(4)?.try_into().ok()?))
    }

    fn u32_be(&mut self) -> Option<u32> {
        Some(u32::from_be_bytes(self.bytes(4)?.try_into().ok()?))
    }

    fn bytes(&mut self, len: usize) -> Option<&'a [u8]> {
        let end = self.off.checked_add(len).filter(|&e| e <= self.body.len())?;
        let s = &self.body[self.off..end];
        self.off = end;
        Some(s)
    }
}

/// Rewritten Vorbis-comment body, or `None` when it doesn't parse. Drops
/// [`DROP_KEYS`], values containing CR/LF (firmware parsers misalign after
/// multi-line values) and repeated [`SINGLE_VALUE_KEYS`]; keeps entries
/// without `=` and the vendor string verbatim.
fn rewrite_vorbis_comment(body: &[u8]) -> Option<Vec<u8>> {
    let mut r = Reader { body, off: 0 };
    let vendor_len = r.u32_le()? as usize;
    let vendor = r.bytes(vendor_len)?;
    let count = r.u32_le()?;
    let mut kept: Vec<&[u8]> = Vec::new();
    let mut seen_single: Vec<&str> = Vec::new();
    for _ in 0..count {
        let len = r.u32_le()? as usize;
        let entry = r.bytes(len)?;
        let Some(eq) = entry.iter().position(|&b| b == b'=') else {
            kept.push(entry);
            continue;
        };
        // Keys are compared byte-wise as Latin-1 upper-cased; only ASCII
        // bytes can ever match the ASCII key lists.
        let key = &entry[..eq];
        if DROP_KEYS.iter().any(|k| key.eq_ignore_ascii_case(k.as_bytes())) {
            continue;
        }
        if entry[eq + 1..].iter().any(|&b| b == b'\n' || b == b'\r') {
            continue;
        }
        if let Some(k) = SINGLE_VALUE_KEYS.iter().find(|k| key.eq_ignore_ascii_case(k.as_bytes())) {
            if seen_single.contains(k) {
                continue;
            }
            seen_single.push(k);
        }
        kept.push(entry);
    }
    let mut out = Vec::with_capacity(body.len());
    out.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
    out.extend_from_slice(vendor);
    out.extend_from_slice(&(kept.len() as u32).to_le_bytes());
    for c in kept {
        out.extend_from_slice(&(c.len() as u32).to_le_bytes());
        out.extend_from_slice(c);
    }
    Some(out)
}

/// Sanitises the Vorbis comment, growing the first PADDING block by the
/// bytes saved so the metadata length (and audio offset) stay unchanged.
/// No-op without a comment or padding block, or when nothing shrinks.
fn apply_sanitize(blocks: &mut [MetaBlock]) -> bool {
    let Some(vc) = blocks.iter().position(|b| b.block_type == BLOCK_VORBIS_COMMENT) else { return false };
    let Some(new_vc) = rewrite_vorbis_comment(&blocks[vc].body) else { return false };
    let old_len = blocks[vc].body.len();
    if new_vc.len() >= old_len {
        return false;
    }
    let delta = old_len - new_vc.len();
    let Some(pad) = blocks.iter().position(|b| b.block_type == BLOCK_PADDING) else { return false };
    let new_pad_len = blocks[pad].body.len() + delta;
    if new_pad_len > MAX_BLOCK_SIZE {
        return false;
    }
    blocks[vc].body = new_vc;
    blocks[pad].body = vec![0u8; new_pad_len];
    true
}

struct ParsedPicture<'a> {
    picture_type: u32,
    description: String,
    width: u32,
    height: u32,
    data: &'a [u8],
}

fn parse_picture_block(body: &[u8]) -> Option<ParsedPicture<'_>> {
    let mut r = Reader { body, off: 0 };
    let picture_type = r.u32_be()?;
    let mime_len = r.u32_be()? as usize;
    r.bytes(mime_len)?;
    let desc_len = r.u32_be()? as usize;
    let description = String::from_utf8_lossy(r.bytes(desc_len)?).into_owned();
    let width = r.u32_be()?;
    let height = r.u32_be()?;
    let _depth = r.u32_be()?;
    let _colors = r.u32_be()?;
    let data_len = r.u32_be()? as usize;
    let data = r.bytes(data_len)?;
    Some(ParsedPicture { picture_type, description, width, height, data })
}

fn build_picture_block(picture_type: u32, description: &str, width: u32, height: u32, data: &[u8]) -> Vec<u8> {
    const MIME: &[u8] = b"image/jpeg";
    let mut out = Vec::with_capacity(32 + MIME.len() + description.len() + data.len());
    let u32_be = |out: &mut Vec<u8>, v: u32| out.extend_from_slice(&v.to_be_bytes());
    u32_be(&mut out, picture_type);
    u32_be(&mut out, MIME.len() as u32);
    out.extend_from_slice(MIME);
    u32_be(&mut out, description.len() as u32);
    out.extend_from_slice(description.as_bytes());
    u32_be(&mut out, width);
    u32_be(&mut out, height);
    u32_be(&mut out, 24); // colour depth
    u32_be(&mut out, 0); // indexed colours
    u32_be(&mut out, data.len() as u32);
    out.extend_from_slice(data);
    out
}

/// A 24-bit BMP declaring `BI_BITFIELDS` with the standard BGR masks (as
/// Dart's `image` encoder writes) is plain `BI_RGB`, which the `image` crate
/// rejects; this returns the equivalent `BI_RGB` copy.
fn bmp_bitfields24_as_rgb(src: &[u8]) -> Option<Vec<u8>> {
    let u32_at = |off: usize| Some(u32::from_le_bytes(src.get(off..off + 4)?.try_into().ok()?));
    let u16_at = |off: usize| Some(u16::from_le_bytes(src.get(off..off + 2)?.try_into().ok()?));
    let standard = src.starts_with(b"BM")
        && u16_at(28)? == 24
        && u32_at(30)? == 3
        && (u32_at(54)?, u32_at(58)?, u32_at(62)?) == (0x00FF_0000, 0x0000_FF00, 0x0000_00FF);
    standard.then(|| {
        let mut patched = src.to_vec();
        patched[30..34].copy_from_slice(&0u32.to_le_bytes());
        patched
    })
}

/// Decodes, box-filter downsizes to `max_edge` on the longest side and
/// re-encodes as JPEG. `None` if undecodable or already small enough.
fn shrink_image(src: &[u8], max_edge: u32, quality: u8) -> Option<(Vec<u8>, u32, u32)> {
    let decoded = image::load_from_memory(src)
        .ok()
        .or_else(|| image::load_from_memory(&bmp_bitfields24_as_rgb(src)?).ok())?;
    let (w, h) = (decoded.width(), decoded.height());
    let longest = w.max(h);
    if longest <= max_edge {
        return None;
    }
    let scale = f64::from(max_edge) / f64::from(longest);
    let new_w = ((f64::from(w) * scale).round() as u32).clamp(1, max_edge);
    let new_h = ((f64::from(h) * scale).round() as u32).clamp(1, max_edge);
    let src_img = Image::from_vec_u8(w, h, decoded.into_rgb8().into_raw(), PixelType::U8x3).ok()?;
    let mut dst = Image::new(new_w, new_h, PixelType::U8x3);
    let opts = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Box));
    Resizer::new().resize(&src_img, &mut dst, &opts).ok()?;
    let mut jpg = Vec::new();
    jpeg_encoder::Encoder::new(&mut jpg, quality)
        .encode(dst.buffer(), u16::try_from(new_w).ok()?, u16::try_from(new_h).ok()?, jpeg_encoder::ColorType::Rgb)
        .ok()?;
    Some((jpg, new_w, new_h))
}

/// Replaces the first PICTURE block with a shrunk JPEG. No-op when the
/// stored dimensions already fit (stored zeros defer to the decoder), the
/// image can't be decoded, or the new block isn't smaller.
fn apply_shrink(blocks: &mut [MetaBlock], max_edge: u32, quality: u8) -> bool {
    let Some(pic) = blocks.iter().position(|b| b.block_type == BLOCK_PICTURE) else { return false };
    let new_body = {
        let Some(parsed) = parse_picture_block(&blocks[pic].body) else { return false };
        if parsed.width > 0 && parsed.height > 0 && parsed.width <= max_edge && parsed.height <= max_edge {
            return false;
        }
        let Some((jpg, w, h)) = shrink_image(parsed.data, max_edge, quality) else { return false };
        build_picture_block(parsed.picture_type, &parsed.description, w, h, &jpg)
    };
    if new_body.len() >= blocks[pic].body.len() {
        return false;
    }
    blocks[pic].body = new_body;
    true
}

/// Applies the enabled steps to parsed metadata; returns the outcome and the
/// new metadata bytes when anything changed.
fn apply(meta: &mut FlacMetadata, opts: &FlacCleanOptions) -> Option<(FlacCleanOutcome, Vec<u8>)> {
    let mut outcome = FlacCleanOutcome::default();
    if opts.sanitize_tags {
        outcome.tags_changed = apply_sanitize(&mut meta.blocks);
    }
    if opts.shrink_picture {
        outcome.picture_shrunk = apply_shrink(&mut meta.blocks, opts.max_edge, opts.quality);
    }
    if !outcome.modified() {
        return None;
    }
    let bytes = serialize_metadata(&meta.blocks)?;
    (bytes.len() as u64 <= meta.audio_start).then_some((outcome, bytes))
}

/// Writes `metadata` at the start of `file`, moves the audio that began at
/// `audio_start` up behind it and truncates the tail. Source is always at or
/// after the destination, so chunked forward copying never overwrites
/// unread bytes.
fn rewrite_in_place(file: &mut File, metadata: &[u8], audio_start: u64) -> io::Result<()> {
    let file_len = file.metadata()?.len();
    file.seek(SeekFrom::Start(0))?;
    file.write_all(metadata)?;
    let mut src = audio_start;
    let mut dst = metadata.len() as u64;
    if src != dst {
        let mut buf = vec![0u8; COPY_BUFFER.min((file_len - src) as usize)];
        while src < file_len {
            let n = buf.len().min((file_len - src) as usize);
            file.seek(SeekFrom::Start(src))?;
            file.read_exact(&mut buf[..n])?;
            file.seek(SeekFrom::Start(dst))?;
            file.write_all(&buf[..n])?;
            src += n as u64;
            dst += n as u64;
        }
        file.set_len(dst)?;
    }
    file.sync_all()
}

/// Cleans a FLAC file in place with one metadata parse; the result is
/// byte-identical to [`sanitize_flac_tags`] followed by
/// [`shrink_flac_embedded_picture`]. Blocking (image work is CPU-bound).
pub fn clean_flac_file(path: &Path, opts: &FlacCleanOptions) -> io::Result<FlacCleanOutcome> {
    if opts.is_noop() || !is_flac_path(path) || !path.is_file() {
        return Ok(FlacCleanOutcome::default());
    }
    let mut file = OpenOptions::new().read(true).write(true).open(path)?;
    let Some(mut meta) = read_metadata(&mut io::BufReader::new(&mut file))? else {
        return Ok(FlacCleanOutcome::default());
    };
    let Some((outcome, bytes)) = apply(&mut meta, opts) else { return Ok(FlacCleanOutcome::default()) };
    rewrite_in_place(&mut file, &bytes, meta.audio_start)?;
    Ok(outcome)
}

/// Streams `src` into `dst` with cleaned metadata, for writing a staged file
/// to the device in a single pass. Anything that isn't a parseable FLAC is
/// copied verbatim. Returns the outcome and the bytes written.
pub fn clean_flac_copy(
    src: &Path,
    dst: &mut impl Write,
    opts: &FlacCleanOptions,
) -> io::Result<(FlacCleanOutcome, u64)> {
    let mut file = File::open(src)?;
    let parsed = if opts.is_noop() || !is_flac_path(src) {
        None
    } else {
        let mut reader = io::BufReader::new(&mut file);
        read_metadata(&mut reader)?
    };
    if let Some(mut meta) = parsed
        && let Some((outcome, bytes)) = apply(&mut meta, opts)
    {
        dst.write_all(&bytes)?;
        let audio = copy_from(&mut file, meta.audio_start, dst)?;
        return Ok((outcome, bytes.len() as u64 + audio));
    }
    let n = copy_from(&mut file, 0, dst)?;
    Ok((FlacCleanOutcome::default(), n))
}

fn copy_from(file: &mut File, offset: u64, dst: &mut impl Write) -> io::Result<u64> {
    file.seek(SeekFrom::Start(offset))?;
    io::copy(&mut io::BufReader::with_capacity(COPY_BUFFER, file), dst)
}

/// In-memory variant for files already buffered (e.g. small zip entries).
pub fn clean_flac_bytes(data: &mut Vec<u8>, opts: &FlacCleanOptions) -> FlacCleanOutcome {
    if opts.is_noop() {
        return FlacCleanOutcome::default();
    }
    let Ok(Some(mut meta)) = read_metadata(&mut Cursor::new(data.as_slice())) else {
        return FlacCleanOutcome::default();
    };
    let Some((outcome, bytes)) = apply(&mut meta, opts) else { return FlacCleanOutcome::default() };
    data.splice(..meta.audio_start as usize, bytes);
    outcome
}

/// Drops DAP-breaking Vorbis comments in place (see [`FlacCleanOptions`]).
/// `true` if the file was rewritten; failures are logged and report `false`.
pub fn sanitize_flac_tags(path: &Path) -> bool {
    match clean_flac_file(path, &FlacCleanOptions::new(true, false)) {
        Ok(o) => o.tags_changed,
        Err(e) => {
            tracing::warn!("sanitize_flac_tags: failed on {}: {e}", path.display());
            false
        }
    }
}

/// Shrinks the embedded cover in place so the file gets smaller on disk.
/// `true` if rewritten; failures are logged and report `false`.
pub fn shrink_flac_embedded_picture(path: &Path, max_edge: u32, quality: u8) -> bool {
    let opts = FlacCleanOptions { sanitize_tags: false, shrink_picture: true, max_edge, quality };
    match clean_flac_file(path, &opts) {
        Ok(o) => o.picture_shrunk,
        Err(e) => {
            tracing::warn!("shrink_flac_embedded_picture: failed on {}: {e}", path.display());
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn block(block_type: u8, is_last: bool, body: Vec<u8>) -> MetaBlock {
        MetaBlock { block_type, is_last, body }
    }

    fn vorbis(vendor: &str, comments: &[&[u8]]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
        out.extend_from_slice(vendor.as_bytes());
        out.extend_from_slice(&(comments.len() as u32).to_le_bytes());
        for c in comments {
            out.extend_from_slice(&(c.len() as u32).to_le_bytes());
            out.extend_from_slice(c);
        }
        out
    }

    fn picture(width: u32, height: u32, data: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&3u32.to_be_bytes());
        out.extend_from_slice(&9u32.to_be_bytes());
        out.extend_from_slice(b"image/png");
        out.extend_from_slice(&5u32.to_be_bytes());
        out.extend_from_slice("Cövr".as_bytes());
        for v in [width, height, 32, 0, data.len() as u32] {
            out.extend_from_slice(&v.to_be_bytes());
        }
        out.extend_from_slice(data);
        out
    }

    fn png(w: u32, h: u32) -> Vec<u8> {
        let img = image::RgbImage::from_fn(w, h, |x, y| image::Rgb([(x * 7) as u8, (y * 13) as u8, ((x ^ y) * 3) as u8]));
        let mut out = Cursor::new(Vec::new());
        img.write_to(&mut out, image::ImageFormat::Png).unwrap();
        out.into_inner()
    }

    fn audio() -> Vec<u8> {
        (0..3_000_000u32).map(|i| (i.wrapping_mul(2_654_435_761) >> 24) as u8).collect()
    }

    fn flac(blocks: &[MetaBlock], audio: &[u8]) -> Vec<u8> {
        let mut out = serialize_metadata(blocks).unwrap();
        out.extend_from_slice(audio);
        out
    }

    fn dirty_comments() -> Vec<u8> {
        vorbis(
            "reference libFLAC 1.4.3",
            &[
                b"TITLE=Song",
                b"GENRE=Rock",
                b"lyrics=la la",
                b"genre=Pop",
                b"COMMENT=multi\nline",
                b"NOEQUALS",
                b"Major_Brand=M4A ",
                b"ARTIST=caf\xc3\xa9\r",
                b"ALBUM=Alb",
            ],
        )
    }

    fn streaminfo() -> MetaBlock {
        block(0, false, vec![0x11; 34])
    }

    fn write_tmp(dir: &Path, name: &str, bytes: &[u8]) -> std::path::PathBuf {
        let p = dir.join(name);
        fs::write(&p, bytes).unwrap();
        p
    }

    #[test]
    fn vorbis_rewrite_rules() {
        let out = rewrite_vorbis_comment(&dirty_comments()).unwrap();
        assert_eq!(
            out,
            vorbis("reference libFLAC 1.4.3", &[b"TITLE=Song", b"GENRE=Rock", b"NOEQUALS", b"ALBUM=Alb"])
        );
        assert_eq!(rewrite_vorbis_comment(&[1, 0, 0]), None);
        let mut truncated = vorbis("v", &[b"A=b"]);
        truncated.pop();
        assert_eq!(rewrite_vorbis_comment(&truncated), None);
    }

    #[test]
    fn sanitize_absorbs_into_padding() {
        let dir = tempfile::tempdir().unwrap();
        let audio = audio();
        let comments = dirty_comments();
        let clean = vorbis("reference libFLAC 1.4.3", &[b"TITLE=Song", b"GENRE=Rock", b"NOEQUALS", b"ALBUM=Alb"]);
        let delta = comments.len() - clean.len();
        let original = flac(
            &[streaminfo(), block(4, false, comments), block(1, false, vec![0xAB; 10]), block(2, true, vec![7; 5])],
            &audio,
        );
        let path = write_tmp(dir.path(), "a.FLAC", &original);
        assert!(sanitize_flac_tags(&path));
        let expected = flac(
            &[streaminfo(), block(4, false, clean), block(1, false, vec![0; 10 + delta]), block(2, true, vec![7; 5])],
            &audio,
        );
        assert_eq!(fs::read(&path).unwrap(), expected);
        // Already clean: no-op.
        assert!(!sanitize_flac_tags(&path));
        assert_eq!(fs::read(&path).unwrap(), expected);
    }

    #[test]
    fn oversized_block_length_on_short_file_is_rejected() {
        let mut bytes = b"fLaC".to_vec();
        bytes.extend_from_slice(&[0x84, 0xFF, 0xFF, 0xFF]);
        bytes.extend_from_slice(b"short");
        assert!(read_metadata(&mut Cursor::new(&bytes)).unwrap().is_none());
        let mut data = bytes.clone();
        assert_eq!(clean_flac_bytes(&mut data, &FlacCleanOptions::new(true, true)), FlacCleanOutcome::default());
        assert_eq!(data, bytes);
    }

    #[test]
    fn sanitize_noop_cases() {
        let dir = tempfile::tempdir().unwrap();
        let no_padding = flac(&[streaminfo(), block(4, true, dirty_comments())], b"audio");
        let mut truncated = flac(&[streaminfo(), block(4, false, dirty_comments()), block(1, true, vec![0; 4])], b"");
        truncated.truncate(truncated.len() - 2);
        let cases: [(&str, Vec<u8>); 5] = [
            ("nopad.flac", no_padding.clone()),
            ("notflac.mp3", flac(&[block(4, false, dirty_comments()), block(1, true, vec![])], b"")),
            ("magic.flac", b"ID3\x04rest".to_vec()),
            ("trunc.flac", truncated),
            ("empty.flac", Vec::new()),
        ];
        for (name, bytes) in cases {
            let p = write_tmp(dir.path(), name, &bytes);
            assert!(!sanitize_flac_tags(&p), "{name}");
            assert_eq!(fs::read(&p).unwrap(), bytes, "{name}");
        }
        assert!(!sanitize_flac_tags(&dir.path().join("missing.flac")));
    }

    fn picture_flac(w: u32, h: u32, stored: (u32, u32)) -> (Vec<u8>, Vec<u8>) {
        let audio = audio();
        let bytes = flac(
            &[
                streaminfo(),
                block(4, false, dirty_comments()),
                block(6, false, picture(stored.0, stored.1, &png(w, h))),
                block(1, true, vec![0; 100]),
            ],
            &audio,
        );
        (bytes, audio)
    }

    #[test]
    fn shrink_rewrites_picture_and_moves_audio() {
        let dir = tempfile::tempdir().unwrap();
        let (original, audio) = picture_flac(1000, 800, (0, 0));
        let path = write_tmp(dir.path(), "a.flac", &original);
        assert!(shrink_flac_embedded_picture(&path, DEFAULT_PICTURE_MAX_EDGE, DEFAULT_PICTURE_JPEG_QUALITY));
        let out = fs::read(&path).unwrap();
        assert!(out.len() < original.len());
        let meta = read_metadata(&mut Cursor::new(&out)).unwrap().unwrap();
        assert_eq!(&out[meta.audio_start as usize..], &audio[..]);
        assert_eq!(meta.blocks.len(), 4);
        assert_eq!(meta.blocks[1].body, dirty_comments(), "tags untouched by shrink");
        let pic = &meta.blocks[2].body;
        let mut r = Reader { body: pic, off: 0 };
        assert_eq!(r.u32_be(), Some(3));
        let mime_len = r.u32_be().unwrap() as usize;
        assert_eq!(r.bytes(mime_len), Some(&b"image/jpeg"[..]));
        let desc_len = r.u32_be().unwrap() as usize;
        assert_eq!(r.bytes(desc_len), Some("Cövr".as_bytes()));
        assert_eq!([r.u32_be(), r.u32_be(), r.u32_be(), r.u32_be()], [Some(320), Some(256), Some(24), Some(0)]);
        let data_len = r.u32_be().unwrap() as usize;
        let jpg = r.bytes(data_len).unwrap();
        assert_eq!(r.off, pic.len());
        let decoded = image::load_from_memory_with_format(jpg, image::ImageFormat::Jpeg).unwrap();
        assert_eq!((decoded.width(), decoded.height()), (320, 256));
        // Already small now.
        assert!(!shrink_flac_embedded_picture(&path, DEFAULT_PICTURE_MAX_EDGE, DEFAULT_PICTURE_JPEG_QUALITY));
        assert_eq!(fs::read(&path).unwrap(), out);
    }

    #[test]
    fn shrink_noop_cases() {
        let dir = tempfile::tempdir().unwrap();
        // Stored dimensions within bounds skip decoding even if they lie.
        let (lying, _) = picture_flac(1000, 800, (300, 200));
        // Decoded image already small.
        let (small, _) = picture_flac(200, 100, (0, 0));
        let undecodable = flac(&[streaminfo(), block(6, true, picture(0, 0, b"garbage"))], b"aud");
        let no_picture = flac(&[streaminfo(), block(1, true, vec![0; 3])], b"aud");
        for (name, bytes) in [("l.flac", lying), ("s.flac", small), ("u.flac", undecodable), ("n.flac", no_picture)] {
            let p = write_tmp(dir.path(), name, &bytes);
            assert!(!shrink_flac_embedded_picture(&p, DEFAULT_PICTURE_MAX_EDGE, DEFAULT_PICTURE_JPEG_QUALITY), "{name}");
            assert_eq!(fs::read(&p).unwrap(), bytes, "{name}");
        }
    }

    #[test]
    fn combined_variants_match_sequential_steps() {
        let dir = tempfile::tempdir().unwrap();
        let (original, _) = picture_flac(900, 1200, (900, 1200));
        let seq = write_tmp(dir.path(), "seq.flac", &original);
        assert!(sanitize_flac_tags(&seq));
        assert!(shrink_flac_embedded_picture(&seq, DEFAULT_PICTURE_MAX_EDGE, DEFAULT_PICTURE_JPEG_QUALITY));
        let expected = fs::read(&seq).unwrap();

        let opts = FlacCleanOptions::new(true, true);
        let both = FlacCleanOutcome { tags_changed: true, picture_shrunk: true };
        let in_place = write_tmp(dir.path(), "in_place.flac", &original);
        assert_eq!(clean_flac_file(&in_place, &opts).unwrap(), both);
        assert_eq!(fs::read(&in_place).unwrap(), expected);

        let src = write_tmp(dir.path(), "src.flac", &original);
        let mut copied = Vec::new();
        assert_eq!(clean_flac_copy(&src, &mut copied, &opts).unwrap(), (both, expected.len() as u64));
        assert_eq!(copied, expected);
        assert_eq!(fs::read(&src).unwrap(), original, "copy leaves the source alone");

        let mut bytes = original.clone();
        assert_eq!(clean_flac_bytes(&mut bytes, &opts), both);
        assert_eq!(bytes, expected);
    }

    #[test]
    fn copy_passes_through_untouched_files() {
        let dir = tempfile::tempdir().unwrap();
        let opts = FlacCleanOptions::new(true, true);
        for (name, bytes) in [("x.mp3", b"ID3 not flac".to_vec()), ("y.flac", b"fLaC\x80\x00".to_vec())] {
            let src = write_tmp(dir.path(), name, &bytes);
            let mut out = Vec::new();
            assert_eq!(clean_flac_copy(&src, &mut out, &opts).unwrap(), (FlacCleanOutcome::default(), bytes.len() as u64));
            assert_eq!(out, bytes);
        }
        let (original, _) = picture_flac(500, 500, (0, 0));
        let src = write_tmp(dir.path(), "z.flac", &original);
        let mut out = Vec::new();
        clean_flac_copy(&src, &mut out, &FlacCleanOptions::new(false, false)).unwrap();
        assert_eq!(out, original);
    }
}
