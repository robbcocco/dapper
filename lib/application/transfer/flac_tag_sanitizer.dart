import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';

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
