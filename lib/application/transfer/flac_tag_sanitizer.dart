import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// Vorbis-comment keys dropped from FLAC files before they land on the device.
//
// LYRICS / UNSYNCEDLYRICS / SYNCEDLYRICS: large multi-line values misalign the
// Shanling M-series tag parser, which then falls through to the next field and
// renders e.g. GENRE in the title column.
//
// MAJOR_BRAND / MINOR_VERSION / COMPATIBLE_BRANDS: junk container atoms that
// ffmpeg copies verbatim when transcoding from m4a/AAC; they don't belong in a
// Vorbis-comment block and trip the same parsers.
const _kDropKeys = <String>{
  'LYRICS',
  'UNSYNCEDLYRICS',
  'SYNCEDLYRICS',
  'MAJOR_BRAND',
  'MINOR_VERSION',
  'COMPATIBLE_BRANDS',
};

// Tags collapsed to a single value (first occurrence kept). Multi-value GENRE
// in particular triggers the misalignment bug on Shanling firmware.
const _kSingleValueKeys = <String>{'GENRE'};

const _kBlockTypeVorbisComment = 4;
const _kBlockTypePadding = 1;
const _kBlockTypePicture = 6;

// Shanling M-series DAPs ship a 320x240 LCD; shrinking embedded covers to a
// 320 px long edge keeps the display sharp at no extra bandwidth. Saves
// several MB per album when sources carry 1500+ px lossless covers.
const _kDefaultPictureMaxEdge = 320;
const _kDefaultPictureJpegQuality = 85;

/// Rewrites the Vorbis-comment block of a FLAC file in place, dropping tags
/// known to break embedded DAP tag parsers (notably the Shanling M-series) and
/// collapsing multi-value tags down to a single value.
///
/// Works without rewriting audio frames by absorbing the freed bytes into an
/// existing PADDING block. If the file has no padding block, no .flac
/// extension, or doesn't parse cleanly, the call is a no-op.
///
/// Returns `true` if the file was rewritten, `false` if nothing needed
/// changing or the file was skipped.
Future<bool> sanitizeFlacTags(String path) async {
  if (!path.toLowerCase().endsWith('.flac')) return false;
  final file = File(path);
  if (!await file.exists()) return false;

  RandomAccessFile? raf;
  try {
    raf = await file.open(mode: FileMode.append);
    await raf.setPosition(0);

    final magic = await raf.read(4);
    if (magic.length < 4 ||
        magic[0] != 0x66 ||
        magic[1] != 0x4c ||
        magic[2] != 0x61 ||
        magic[3] != 0x43) {
      return false;
    }

    final blocks = <_MetaBlock>[];
    while (true) {
      final header = await raf.read(4);
      if (header.length < 4) return false;
      final headerByte = header[0];
      final isLast = (headerByte & 0x80) != 0;
      final type = headerByte & 0x7f;
      final size = (header[1] << 16) | (header[2] << 8) | header[3];
      final body = size == 0 ? Uint8List(0) : await raf.read(size);
      if (body.length < size) return false;
      blocks.add(_MetaBlock(
        type: type,
        isLast: isLast,
        body: body,
      ));
      if (isLast) break;
      if (blocks.length > 128) return false; // sanity bail
    }

    final vcIdx = blocks.indexWhere((b) => b.type == _kBlockTypeVorbisComment);
    if (vcIdx < 0) return false;
    final newVcBody = _rewriteVorbisComment(blocks[vcIdx].body);
    if (newVcBody == null) return false;
    final delta = blocks[vcIdx].body.length - newVcBody.length;
    if (delta <= 0) return false;

    final padIdx = blocks.indexWhere((b) => b.type == _kBlockTypePadding);
    if (padIdx < 0) return false;
    final newPadLen = blocks[padIdx].body.length + delta;
    if (newPadLen > 0xFFFFFF) return false;

    blocks[vcIdx] = blocks[vcIdx].copyWith(body: newVcBody);
    blocks[padIdx] = blocks[padIdx].copyWith(body: Uint8List(newPadLen));

    final out = BytesBuilder(copy: false)
      ..add(const [0x66, 0x4c, 0x61, 0x43]);
    for (final b in blocks) {
      final size = b.body.length;
      if (size > 0xFFFFFF) return false;
      out.addByte((b.isLast ? 0x80 : 0) | (b.type & 0x7f));
      out.addByte((size >> 16) & 0xff);
      out.addByte((size >> 8) & 0xff);
      out.addByte(size & 0xff);
      out.add(b.body);
    }
    final bytes = out.takeBytes();

    await raf.setPosition(0);
    await raf.writeFrom(bytes);
    await raf.flush();
    return true;
  } catch (e) {
    dev.log('sanitizeFlacTags: failed on $path — $e');
    return false;
  } finally {
    await raf?.close();
  }
}

class _MetaBlock {
  _MetaBlock({required this.type, required this.isLast, required this.body});
  final int type;
  final bool isLast;
  final Uint8List body;

  _MetaBlock copyWith({int? type, bool? isLast, Uint8List? body}) => _MetaBlock(
        type: type ?? this.type,
        isLast: isLast ?? this.isLast,
        body: body ?? this.body,
      );
}

/// Shrinks the embedded album-art PICTURE block of a FLAC file in place.
/// Target: longest edge ≤ [maxEdge] (default 320 — Shanling M1s screen
/// height). Re-encodes as JPEG at [quality], rewrites metadata, and moves
/// audio frames forward so the **file actually shrinks on disk** — vs the
/// padding-absorb trick used by [sanitizeFlacTags] for sub-KB tag savings.
///
/// No-op when: file isn't .flac, file has no PICTURE block, or the embedded
/// image is already small enough.
///
/// Image decode + resize + JPEG encode runs inside a fresh isolate via
/// [Isolate.run] so the caller's isolate isn't blocked. The audio-shift loop
/// runs sequentially in the caller's isolate.
///
/// Returns `true` when the file was rewritten with a smaller cover.
Future<bool> shrinkFlacEmbeddedPicture(
  String path, {
  int maxEdge = _kDefaultPictureMaxEdge,
  int quality = _kDefaultPictureJpegQuality,
}) async {
  if (!path.toLowerCase().endsWith('.flac')) return false;
  final file = File(path);
  if (!await file.exists()) return false;

  RandomAccessFile? raf;
  try {
    raf = await file.open(mode: FileMode.append);
    await raf.setPosition(0);

    final magic = await raf.read(4);
    if (magic.length < 4 ||
        magic[0] != 0x66 ||
        magic[1] != 0x4c ||
        magic[2] != 0x61 ||
        magic[3] != 0x43) {
      return false;
    }

    final blocks = <_MetaBlock>[];
    // Track absolute end-of-metadata = start-of-audio while we parse.
    var oldAudioStart = 4;
    while (true) {
      final header = await raf.read(4);
      if (header.length < 4) return false;
      final headerByte = header[0];
      final isLast = (headerByte & 0x80) != 0;
      final type = headerByte & 0x7f;
      final size = (header[1] << 16) | (header[2] << 8) | header[3];
      final body = size == 0 ? Uint8List(0) : await raf.read(size);
      if (body.length < size) return false;
      blocks.add(_MetaBlock(type: type, isLast: isLast, body: body));
      oldAudioStart += 4 + size;
      if (isLast) break;
      if (blocks.length > 128) return false;
    }

    final picIdx = blocks.indexWhere((b) => b.type == _kBlockTypePicture);
    if (picIdx < 0) return false;
    final parsed = _parsePictureBlock(blocks[picIdx].body);
    if (parsed == null) return false;

    // FLAC's stored dims can lie (some encoders write zeros) — let the decoder
    // be authoritative. Skip the expensive decode only when the stored dims
    // clearly say "already small".
    if (parsed.width > 0 &&
        parsed.height > 0 &&
        parsed.width <= maxEdge &&
        parsed.height <= maxEdge) {
      return false;
    }

    final srcData = parsed.data;
    final shrunk = await Isolate.run(() => _decodeResizeEncode(
          srcData,
          maxEdge,
          quality,
        ));
    if (shrunk == null) return false;

    final newPicBody = _buildPictureBlock(
      pictureType: parsed.pictureType,
      mime: 'image/jpeg',
      description: parsed.desc,
      width: shrunk.width,
      height: shrunk.height,
      depth: 24,
      colors: 0,
      data: shrunk.bytes,
    );

    final delta = blocks[picIdx].body.length - newPicBody.length;
    if (delta <= 0) return false;

    blocks[picIdx] = blocks[picIdx].copyWith(body: newPicBody);

    final out = BytesBuilder(copy: false)
      ..add(const [0x66, 0x4c, 0x61, 0x43]);
    for (final b in blocks) {
      final size = b.body.length;
      if (size > 0xFFFFFF) return false;
      out.addByte((b.isLast ? 0x80 : 0) | (b.type & 0x7f));
      out.addByte((size >> 16) & 0xff);
      out.addByte((size >> 8) & 0xff);
      out.addByte(size & 0xff);
      out.add(b.body);
    }
    final newMetadataBytes = out.takeBytes();
    final newAudioStart = newMetadataBytes.length;
    if (newAudioStart > oldAudioStart) return false; // sanity

    final fileLen = await raf.length();
    await raf.setPosition(0);
    await raf.writeFrom(newMetadataBytes);

    // Shift audio frames forward in 1 MB chunks. Source > destination, so
    // reading-then-writing each chunk before the next read is safe (no
    // overwrite-before-read overlap).
    const chunkSize = 1024 * 1024;
    var src = oldAudioStart;
    var dst = newAudioStart;
    while (src < fileLen) {
      final remaining = fileLen - src;
      final n = remaining > chunkSize ? chunkSize : remaining;
      await raf.setPosition(src);
      final chunk = await raf.read(n);
      if (chunk.length < n) return false;
      await raf.setPosition(dst);
      await raf.writeFrom(chunk);
      src += n;
      dst += n;
    }
    await raf.truncate(dst);
    await raf.flush();
    return true;
  } catch (e) {
    dev.log('shrinkFlacEmbeddedPicture: failed on $path — $e');
    return false;
  } finally {
    await raf?.close();
  }
}

class _ShrunkImage {
  const _ShrunkImage(
      {required this.bytes, required this.width, required this.height});
  final Uint8List bytes;
  final int width;
  final int height;
}

// Runs inside an isolate spawned by [shrinkFlacEmbeddedPicture]. Pure CPU,
// no I/O, no file handles — safe to ship across the boundary.
_ShrunkImage? _decodeResizeEncode(Uint8List src, int maxEdge, int quality) {
  final decoded = img.decodeImage(src);
  if (decoded == null) return null;
  final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longest <= maxEdge) return null;
  final scale = maxEdge / longest;
  final newW = (decoded.width * scale).round().clamp(1, maxEdge);
  final newH = (decoded.height * scale).round().clamp(1, maxEdge);
  final resized = img.copyResize(
    decoded,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.average,
  );
  final jpg = img.encodeJpg(resized, quality: quality);
  return _ShrunkImage(
    bytes: Uint8List.fromList(jpg),
    width: newW,
    height: newH,
  );
}

class _ParsedPicture {
  const _ParsedPicture({
    required this.pictureType,
    required this.mime,
    required this.desc,
    required this.width,
    required this.height,
    required this.depth,
    required this.colors,
    required this.data,
  });
  final int pictureType;
  final String mime;
  final String desc;
  final int width;
  final int height;
  final int depth;
  final int colors;
  final Uint8List data;
}

_ParsedPicture? _parsePictureBlock(Uint8List body) {
  var off = 0;
  int readU32BE() {
    if (off + 4 > body.length) throw const FormatException('truncated');
    final v = (body[off] << 24) |
        (body[off + 1] << 16) |
        (body[off + 2] << 8) |
        body[off + 3];
    off += 4;
    return v;
  }

  try {
    final picType = readU32BE();
    final mimeLen = readU32BE();
    if (off + mimeLen > body.length) return null;
    final mime = utf8.decode(body.sublist(off, off + mimeLen), allowMalformed: true);
    off += mimeLen;
    final descLen = readU32BE();
    if (off + descLen > body.length) return null;
    final desc = utf8.decode(body.sublist(off, off + descLen), allowMalformed: true);
    off += descLen;
    final width = readU32BE();
    final height = readU32BE();
    final depth = readU32BE();
    final colors = readU32BE();
    final dataLen = readU32BE();
    if (off + dataLen > body.length) return null;
    final data = body.sublist(off, off + dataLen);
    return _ParsedPicture(
      pictureType: picType,
      mime: mime,
      desc: desc,
      width: width,
      height: height,
      depth: depth,
      colors: colors,
      data: data,
    );
  } catch (_) {
    return null;
  }
}

Uint8List _buildPictureBlock({
  required int pictureType,
  required String mime,
  required String description,
  required int width,
  required int height,
  required int depth,
  required int colors,
  required Uint8List data,
}) {
  final mimeBytes = utf8.encode(mime);
  final descBytes = utf8.encode(description);
  final out = BytesBuilder(copy: false);
  void writeU32BE(int v) {
    out.addByte((v >> 24) & 0xff);
    out.addByte((v >> 16) & 0xff);
    out.addByte((v >> 8) & 0xff);
    out.addByte(v & 0xff);
  }

  writeU32BE(pictureType);
  writeU32BE(mimeBytes.length);
  out.add(mimeBytes);
  writeU32BE(descBytes.length);
  out.add(descBytes);
  writeU32BE(width);
  writeU32BE(height);
  writeU32BE(depth);
  writeU32BE(colors);
  writeU32BE(data.length);
  out.add(data);
  return out.takeBytes();
}

Uint8List? _rewriteVorbisComment(Uint8List body) {
  var off = 0;
  int readU32() {
    if (off + 4 > body.length) throw const FormatException('truncated');
    final v = body[off] |
        (body[off + 1] << 8) |
        (body[off + 2] << 16) |
        (body[off + 3] << 24);
    off += 4;
    return v;
  }

  try {
    final vendorLen = readU32();
    if (off + vendorLen > body.length) return null;
    final vendor = body.sublist(off, off + vendorLen);
    off += vendorLen;
    final count = readU32();
    final kept = <Uint8List>[];
    final seenSingle = <String>{};
    for (var i = 0; i < count; i++) {
      final len = readU32();
      if (off + len > body.length) return null;
      final bytes = body.sublist(off, off + len);
      off += len;
      final eq = bytes.indexOf(0x3d);
      if (eq < 0) {
        kept.add(bytes);
        continue;
      }
      final keyUpper =
          String.fromCharCodes(bytes.sublist(0, eq)).toUpperCase();
      if (_kDropKeys.contains(keyUpper)) continue;
      // Drop entries whose value contains a newline; embedded firmware tag
      // parsers misalign subsequent fields after multi-line Vorbis values.
      var hasNewline = false;
      for (var j = eq + 1; j < bytes.length; j++) {
        if (bytes[j] == 0x0a || bytes[j] == 0x0d) {
          hasNewline = true;
          break;
        }
      }
      if (hasNewline) continue;
      if (_kSingleValueKeys.contains(keyUpper)) {
        if (seenSingle.contains(keyUpper)) continue;
        seenSingle.add(keyUpper);
      }
      kept.add(bytes);
    }

    final out = BytesBuilder(copy: false);
    void writeU32(int v) {
      out.addByte(v & 0xff);
      out.addByte((v >> 8) & 0xff);
      out.addByte((v >> 16) & 0xff);
      out.addByte((v >> 24) & 0xff);
    }

    writeU32(vendor.length);
    out.add(vendor);
    writeU32(kept.length);
    for (final c in kept) {
      writeU32(c.length);
      out.add(c);
    }
    return out.takeBytes();
  } catch (_) {
    return null;
  }
}
