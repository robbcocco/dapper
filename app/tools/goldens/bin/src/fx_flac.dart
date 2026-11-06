import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../../../../../lib/application/transfer/flac_tag_sanitizer.dart';
import 'common.dart';
import 'corpus.dart';

const _vorbis = 4, _padding = 1, _picture = 6, _streamInfo = 0, _app = 2, _seek = 3;

typedef _Block = ({int type, Uint8List body, bool? last});

_Block _b(int type, List<int> body, {bool? last}) =>
    (type: type, body: Uint8List.fromList(body), last: last);

Uint8List _flac(List<_Block> blocks, List<int> audio, {List<int> magic = const [0x66, 0x4c, 0x61, 0x43]}) {
  final out = BytesBuilder()..add(magic);
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final last = b.last ?? i == blocks.length - 1;
    final n = b.body.length;
    out
      ..addByte((last ? 0x80 : 0) | b.type)
      ..add([(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff])
      ..add(b.body);
  }
  out.add(audio);
  return out.takeBytes();
}

List<int> _le32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
List<int> _be32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

List<int> _streamInfoBody() => [
      0x10, 0x00, 0x10, 0x00, // min/max block size 4096
      0x00, 0x00, 0x0e, 0x00, 0x30, 0x00, // min/max frame size
      0x0a, 0xc4, 0x42, 0xf0, // 44100 Hz, 2 ch, 16 bit
      0x00, 0x00, 0x00, 0x10, // total samples (low bits)
      ...List.filled(16, 0xab), // md5
    ];

List<int> _vc(String vendor, List<Object> comments, {List<int> trailing = const [], int? countOverride}) {
  final v = utf8.encode(vendor);
  final out = <int>[..._le32(v.length), ...v, ..._le32(countOverride ?? comments.length)];
  for (final c in comments) {
    final bytes = c is String ? utf8.encode(c) : c as List<int>;
    out
      ..addAll(_le32(bytes.length))
      ..addAll(bytes);
  }
  return out..addAll(trailing);
}

List<int> _pic({
  int type = 3,
  String mime = 'image/jpeg',
  String desc = '',
  required int width,
  required int height,
  int depth = 24,
  int colors = 0,
  required List<int> data,
  int? dataLenOverride,
}) {
  final m = utf8.encode(mime), d = utf8.encode(desc);
  return [
    ..._be32(type),
    ..._be32(m.length), ...m,
    ..._be32(d.length), ...d,
    ..._be32(width), ..._be32(height), ..._be32(depth), ..._be32(colors),
    ..._be32(dataLenOverride ?? data.length), ...data,
  ];
}

List<int> _audio(int n, int salt) {
  final rnd = seeded(100 + salt);
  return [0xff, 0xf8, for (var i = 2; i < n; i++) rnd.nextInt(256)];
}

String _sha(List<int> b) => sha256.convert(b).toString();

Future<void> flacSanitize(Directory tmp) async {
  final dir = Directory('${fixturesDir.path}flac_sanitize')..createSync(recursive: true);
  for (final f in dir.listSync()) {
    f.deleteSync();
  }
  final si = _b(_streamInfo, _streamInfoBody());
  final audio = _audio(4096, 1);
  final lyrics = 'LYRICS=Line one\nLine two\r\nLine three';
  final standard = [
    'TITLE=Song',
    'ARTIST=Artist',
    'GENRE=Rock',
    'GENRE=Pop',
    lyrics,
    'UNSYNCEDLYRICS=single line is still dropped',
    'SYNCEDLYRICS=[00:01.00]x',
    'MAJOR_BRAND=M4A ',
    'MINOR_VERSION=512',
    'COMPATIBLE_BRANDS=isomiso2',
    'COMMENT=multi\nline comment',
    'DESCRIPTION=cr only\rvalue',
    'ALBUM=Album',
  ];
  final png = img.encodePng(img.Image(width: 8, height: 8));

  final cases = <(String, String, Uint8List)>[
    ('basic', 'basic.flac', _flac([si, _b(_vorbis, _vc('reference libFLAC 1.4.3', standard)), _b(_padding, List.filled(1024, 0))], audio)),
    ('no_padding', 'no_padding.flac', _flac([si, _b(_vorbis, _vc('v', standard))], audio)),
    ('nothing_to_drop', 'clean.flac', _flac([si, _b(_vorbis, _vc('v', ['TITLE=Clean', 'GENRE=Jazz'])), _b(_padding, List.filled(64, 0))], audio)),
    ('lowercase_keys', 'lower.flac', _flac([si, _b(_vorbis, _vc('v', ['lyrics=x', 'Genre=A', 'genre=B', 'GeNrE=C', 'major_brand=y', 'title=t'])), _b(_padding, List.filled(16, 0))], audio)),
    ('no_equals', 'noeq.flac', _flac([si, _b(_vorbis, _vc('v', ['NOEQUALS', 'LYRICS', 'GENRE', 'GENRE', 'LYRICS=x'])), _b(_padding, List.filled(8, 0))], audio)),
    ('empty_values', 'empty.flac', _flac([si, _b(_vorbis, _vc('v', ['GENRE=', 'GENRE=', 'LYRICS=', '=value', '=', 'TITLE='])), _b(_padding, [])], audio)),
    ('vendor_only', 'vendor.flac', _flac([si, _b(_vorbis, _vc('only vendor', [])), _b(_padding, List.filled(4, 0))], audio)),
    ('truncated_vc', 'trunc.flac', _flac([si, _b(_vorbis, _vc('v', ['LYRICS=x', 'TITLE=t'], countOverride: 5)), _b(_padding, List.filled(32, 0))], audio)),
    ('vendor_len_overflow', 'vlen.flac', _flac([si, _b(_vorbis, [..._le32(9999), 1, 2, 3]), _b(_padding, List.filled(32, 0))], audio)),
    ('framing_trailer', 'framing.flac', _flac([si, _b(_vorbis, _vc('v', ['TITLE=t'], trailing: [0x01])), _b(_padding, List.filled(32, 0))], audio)),
    ('trailing_garbage_only', 'garbage.flac', _flac([si, _b(_vorbis, _vc('v', ['TITLE=t', 'GENRE=x'], trailing: [1, 2, 3, 4, 5, 6, 7])), _b(_padding, List.filled(32, 0))], audio)),
    ('padding_before_vc', 'padfirst.flac', _flac([si, _b(_padding, List.filled(100, 0)), _b(_app, utf8.encode('riffAPPDATA')), _b(_vorbis, _vc('v', standard))], audio)),
    ('two_paddings', 'twopad.flac', _flac([si, _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(10, 0)), _b(_padding, List.filled(20, 0xee))], audio)),
    ('two_vc_blocks', 'twovc.flac', _flac([si, _b(_vorbis, _vc('first', ['TITLE=a', 'GENRE=1', 'GENRE=2'])), _b(_vorbis, _vc('second', ['LYRICS=keep me'])), _b(_padding, List.filled(10, 0))], audio)),
    ('vc_last_block', 'vclast.flac', _flac([si, _b(_padding, List.filled(10, 0)), _b(_vorbis, _vc('v', ['LYRICS=a\nb', 'TITLE=t']))], audio)),
    ('nonzero_padding_bytes', 'padbytes.flac', _flac([si, _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(40, 0x5a))], audio)),
    ('with_picture_and_seektable', 'pic.flac', _flac([si, _b(_seek, List.filled(18, 0x11)), _b(_vorbis, _vc('v', standard)), _b(_picture, _pic(width: 8, height: 8, mime: 'image/png', data: png)), _b(_padding, List.filled(200, 0))], audio)),
    ('non_ascii_keys', 'nonascii.flac', _flac([si, _b(_vorbis, _vc('vëndor', ['GENRÉ=a', 'GENRÉ=b', 'ÿLYRICS=x', 'lyrıcs=dotless', 'TITLE=Ünïcödé 🎵', 'ARTIST=x\u2028y', 'GENRE=a\u0085b'])), _b(_padding, List.filled(8, 0))], audio)),
    ('raw_bytes', 'raw.flac', _flac([si, _b(_vorbis, _vc('v', [[0x47, 0x45, 0x4e, 0x52, 0x45, 0x3d, 0xff, 0xfe], [0x47, 0x45, 0x4e, 0x52, 0x45, 0x3d, 0x0a], [0xff, 0x3d, 0x0d], [0x4c, 0x59, 0x52, 0x49, 0x43, 0x53]])), _b(_padding, List.filled(8, 0))], audio)),
    ('uppercase_ext', 'UPPER.FLAC', _flac([si, _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(8, 0))], audio)),
    ('mp3_ext', 'not.mp3', _flac([si, _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(8, 0))], audio)),
    ('flac_in_name_only', 'x.flac.bak', _flac([si, _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(8, 0))], audio)),
    ('bad_magic', 'id3.flac', _flac([si, _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(8, 0))], audio, magic: utf8.encode('ID3\u0004'))),
    ('empty_file', 'empty_file.flac', Uint8List(0)),
    ('magic_only', 'magic.flac', Uint8List.fromList(utf8.encode('fLaC'))),
    ('truncated_header', 'trunchdr.flac', Uint8List.fromList([...utf8.encode('fLaC'), 0x00, 0x00])),
    ('truncated_block', 'truncblk.flac', Uint8List.fromList([...utf8.encode('fLaC'), 0x84, 0x00, 0x01, 0x00, 1, 2, 3])),
    ('no_last_flag', 'nolast.flac', _flac([si.copy(last: false), _b(_vorbis, _vc('v', standard), last: false), _b(_padding, List.filled(8, 0), last: false)], [])),
    ('too_many_blocks', 'many.flac', _flac([si, for (var i = 0; i < 130; i++) _b(_app, [i & 0xff], last: false), _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(8, 0))], audio)),
    ('no_vc', 'novc.flac', _flac([si, _b(_padding, List.filled(8, 0))], audio)),
    ('large_lyrics', 'biglyrics.flac', _flac([si, _b(_vorbis, _vc('v', ['TITLE=t', 'LYRICS=${'la la la\n' * 3000}'])), _b(_padding, List.filled(8192, 0))], _audio(20000, 2))),
    ('no_audio', 'noaudio.flac', _flac([si, _b(_vorbis, _vc('v', standard)), _b(_padding, List.filled(8, 0))], [])),
  ];

  final out = <Case>[];
  for (final (name, fileName, bytes) in cases) {
    final inRel = 'flac_sanitize/$name.in.flac';
    final outRel = 'flac_sanitize/$name.out.flac';
    File('${fixturesDir.path}$inRel').writeAsBytesSync(bytes);
    final work = Directory('${tmp.path}/sanitize/$name')..createSync(recursive: true);
    final target = File('${work.path}/$fileName')..writeAsBytesSync(bytes);
    final input = {'name': name, 'inFile': inRel, 'fileName': fileName};
    // sanitizeFlacTags swallows its own errors; a throw here is a generator
    // sanity failure and aborts the run.
    final changed = await sanitizeFlacTags(target.path);
    final after = target.readAsBytesSync();
    if (!changed && _sha(after) != _sha(bytes)) {
      throw StateError('$name: returned false but modified the file');
    }
    File('${fixturesDir.path}$outRel').writeAsBytesSync(after);
    out.add(Case(input, {
      'changed': changed,
      'outFile': outRel,
      'outSha256': _sha(after),
      'outLength': after.length,
    }));
  }

  writeFixture(
    'flac_sanitize',
    'sanitizeFlacTags(path) (lib/application/transfer/flac_tag_sanitizer.dart), byte-exact. Paths are '
        'relative to app/fixtures/. input {name, inFile, fileName: name the file must have when the function '
        'runs (extension check)} → output {changed: return value, outFile: exact file bytes afterwards, '
        'outSha256, outLength}. Unchanged cases have outFile identical to inFile. Not covered (would need a '
        '16 MiB fixture): padding growth past 0xFFFFFF returns false.',
    out,
  );
}

extension on _Block {
  _Block copy({bool? last}) => (type: type, body: body, last: last);
}

// ── shrink ──────────────────────────────────────────────────────────────────

Map<String, Object?>? _readPicture(Uint8List file) {
  if (file.length < 4) return null;
  var off = 4;
  while (off + 4 <= file.length) {
    final hdr = file[off];
    final size = (file[off + 1] << 16) | (file[off + 2] << 8) | file[off + 3];
    final body = file.sublist(off + 4, off + 4 + size);
    if ((hdr & 0x7f) == _picture) {
      final bd = ByteData.sublistView(body);
      var p = 0;
      int u32() => bd.getUint32((p += 4) - 4);
      final type = u32();
      final mimeLen = u32();
      final mime = utf8.decode(body.sublist(p, p += mimeLen));
      final descLen = u32();
      final desc = utf8.decode(body.sublist(p, p += descLen));
      final w = u32(), h = u32(), depth = u32(), colors = u32(), len = u32();
      final data = body.sublist(p, p + len);
      final decoded = img.decodeImage(data);
      return {
        'pictureType': type,
        'mime': mime,
        'description': desc,
        'width': w,
        'height': h,
        'depth': depth,
        'colors': colors,
        'decodedWidth': decoded?.width,
        'decodedHeight': decoded?.height,
        'decodedFormat': decoded == null ? null : img.findFormatForData(data).name,
        'dataLength': len,
      };
    }
    off += 4 + size;
    if ((hdr & 0x80) != 0) break;
  }
  return null;
}

List<Map<String, Object?>> _blockList(Uint8List file) {
  final out = <Map<String, Object?>>[];
  var off = 4;
  while (off + 4 <= file.length) {
    final hdr = file[off];
    final size = (file[off + 1] << 16) | (file[off + 2] << 8) | file[off + 3];
    final type = hdr & 0x7f;
    out.add({
      'type': type,
      'isLast': (hdr & 0x80) != 0,
      // PICTURE bodies depend on the JPEG encoder; others must match exactly.
      'sha256': type == _picture ? null : _sha(file.sublist(off + 4, off + 4 + size)),
    });
    off += 4 + size;
    if ((hdr & 0x80) != 0) break;
  }
  return out;
}

int _audioStart(Uint8List file) {
  var off = 4;
  while (off + 4 <= file.length) {
    final hdr = file[off];
    final size = (file[off + 1] << 16) | (file[off + 2] << 8) | file[off + 3];
    off += 4 + size;
    if ((hdr & 0x80) != 0) break;
  }
  return off;
}

// Smooth gradients + rings: photo-like detail without the bulk of noise,
// keeping the committed fixtures small. [noise] adds that many random low
// bits per channel where a source must be much larger than its 320 px JPEG
// (near-320 or very thin images).
img.Image _pattern(int w, int h, int salt, {int noise = 0}) {
  final rnd = seeded(200 + salt);
  final im = img.Image(width: w, height: h);
  final cx = rnd.nextInt(w), cy = rnd.nextInt(h);
  int n() => noise == 0 ? 0 : rnd.nextInt(1 << noise);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      im.setPixelRgb(x, y, ((x * 255) ~/ w) ^ n(), ((y * 255) ~/ h) ^ n(),
          (127 + 127 * sin(d / 9)).round() ^ n());
    }
  }
  return im;
}

Future<void> flacShrink(Directory tmp) async {
  final dir = Directory('${fixturesDir.path}flac_shrink')..createSync(recursive: true);
  for (final f in dir.listSync()) {
    f.deleteSync();
  }
  final si = _b(_streamInfo, _streamInfoBody());
  final vc = _b(_vorbis, _vc('v', ['TITLE=t', 'ARTIST=a']));
  final pad = _b(_padding, List.filled(512, 0));
  final audio = _audio(8192, 3);

  List<int> jpg(int w, int h, int salt) => img.encodeJpg(_pattern(w, h, salt), quality: 80);
  List<int> png(int w, int h, int salt, {int noise = 0}) =>
      img.encodePng(_pattern(w, h, salt, noise: noise));

  final big = jpg(1000, 800, 1);
  final cases = <(String, String, Uint8List, bool)>[
    ('jpeg_1000x800', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 800, data: big)), pad], audio), true),
    ('jpeg_square_1200', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 1200, height: 1200, data: jpg(1200, 1200, 2), desc: 'Front cover — Ünïcödé 🎵')), pad], audio), true),
    ('png_640x481_half_rounding', 'a.flac', _flac([si, vc, _b(_picture, _pic(mime: 'image/png', width: 640, height: 481, depth: 32, data: png(640, 481, 3))), pad], audio), true),
    ('png_481x640', 'a.flac', _flac([si, vc, _b(_picture, _pic(mime: 'image/png', width: 481, height: 640, data: png(481, 640, 4))), pad], audio), true),
    ('stored_zero_dims_big', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 0, height: 0, data: jpg(960, 720, 5))), pad], audio), true),
    ('stored_zero_dims_small', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 0, height: 0, data: jpg(200, 100, 6))), pad], audio), false),
    ('stored_small_dims_lie', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 100, height: 100, data: big)), pad], audio), false),
    ('stored_big_actual_small', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 1000, data: jpg(320, 200, 7))), pad], audio), false),
    ('exactly_320', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 320, height: 320, data: jpg(320, 320, 8))), pad], audio), false),
    ('stored_321_actual_321x320', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 321, height: 320, data: png(321, 320, 9, noise: 6), mime: 'image/png')), pad], audio), true),
    ('wide_4000x3', 'a.flac', _flac([si, vc, _b(_picture, _pic(mime: 'image/png', width: 4000, height: 3, data: png(4000, 3, 10, noise: 6))), pad], audio), true),
    ('tall_3x4000', 'a.flac', _flac([si, vc, _b(_picture, _pic(mime: 'image/png', width: 3, height: 4000, data: png(3, 4000, 11, noise: 6))), pad], audio), true),
    ('odd_641x427', 'a.flac', _flac([si, vc, _b(_picture, _pic(mime: 'image/png', width: 641, height: 427, data: png(641, 427, 12, noise: 4))), pad], audio), true),
    ('gif_source', 'a.flac', _flac([si, vc, _b(_picture, _pic(mime: 'image/gif', width: 700, height: 500, depth: 8, colors: 256, data: img.encodeGif(_pattern(700, 500, 13)))), pad], audio), true),
    ('bmp_source', 'a.flac', _flac([si, vc, _b(_picture, _pic(mime: 'image/bmp', width: 220, height: 340, data: img.encodeBmp(_pattern(220, 340, 14)))), pad], audio), true),
    ('garbage_image', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 1000, data: List.generate(5000, (i) => (i * 31) & 0xff))), pad], audio), false),
    ('no_picture', 'a.flac', _flac([si, vc, pad], audio), false),
    ('picture_last_block', 'a.flac', _flac([si, vc, pad, _b(_picture, _pic(width: 900, height: 900, data: jpg(900, 900, 15), type: 4))], audio), true),
    ('two_pictures', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 800, height: 600, data: jpg(800, 600, 16))), _b(_picture, _pic(width: 800, height: 800, data: jpg(800, 800, 17), type: 4)), pad], audio), true),
    ('picture_data_len_overflow', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 800, data: big, dataLenOverride: big.length + 10)), pad], audio), false),
    ('picture_mime_len_overflow', 'a.flac', _flac([si, vc, _b(_picture, [..._be32(3), ..._be32(1 << 30), 1, 2, 3]), pad], audio), false),
    ('mp3_extension', 'a.mp3', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 800, data: big)), pad], audio), false),
    ('uppercase_extension', 'A.FLAC', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 800, data: big)), pad], audio), true),
    ('bad_magic', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 800, data: big)), pad], audio, magic: [0, 0, 0, 0]), false),
    ('large_audio_chunked_move', 'a.flac', _flac([si, vc, _b(_picture, _pic(width: 1000, height: 800, data: big))], _audio(1100000, 4)), true),
    ('no_audio', 'a.flac', _flac([si, _b(_picture, _pic(width: 1000, height: 800, data: big)), vc], []), true),
  ];

  final out = <Case>[];
  for (final (name, fileName, bytes, expectChange) in cases) {
    final inRel = 'flac_shrink/$name.in.flac';
    File('${fixturesDir.path}$inRel').writeAsBytesSync(bytes);
    final work = Directory('${tmp.path}/shrink/$name')..createSync(recursive: true);
    final target = File('${work.path}/$fileName')..writeAsBytesSync(bytes);
    final input = {'name': name, 'inFile': inRel, 'fileName': fileName};
    final before = Uint8List.fromList(bytes);
    // shrinkFlacEmbeddedPicture swallows its own errors; anything thrown below
    // is a generator sanity failure and aborts the run.
    final changed = await shrinkFlacEmbeddedPicture(target.path);
    final after = target.readAsBytesSync();
    if (changed != expectChange) {
      throw StateError('$name: expected changed=$expectChange, got $changed');
    }
    if (!changed) {
      if (_sha(after) != _sha(before)) {
        throw StateError('$name: returned false but modified the file');
      }
      out.add(lossyCase(input, {
        'changed': false,
        'unchangedSha256': _sha(after),
        'picture': null,
        'blocks': null,
        'audioSha256': null,
        'audioLength': null,
        'dartTotalLength': after.length,
        'dartPictureDataLength': null,
      }));
      continue;
    }
    final beforePic = _readPicture(before)!;
    final afterPic = _readPicture(after)!;
    // Keep the case encoder-independent: the original picture must be far
    // larger than any plausible 320 px JPEG.
    final ratio = (beforePic['dataLength'] as int) / (afterPic['dataLength'] as int);
    if (ratio < 3) throw StateError('$name: shrink margin too small ($ratio)');
    final audioBefore = before.sublist(_audioStart(before));
    final audioAfter = after.sublist(_audioStart(after));
    if (_sha(audioBefore) != _sha(audioAfter)) throw StateError('$name: audio changed');
    out.add(lossyCase(input, {
      'changed': true,
      'unchangedSha256': null,
      'picture': afterPic,
      'blocks': _blockList(after),
      'audioSha256': _sha(audioAfter),
      'audioLength': audioAfter.length,
      'dartTotalLength': after.length,
      'dartPictureDataLength': afterPic['dataLength'],
    }));
  }

  writeFixture(
    'flac_shrink',
    'shrinkFlacEmbeddedPicture(path) with defaults maxEdge=320, quality=85 '
        '(flac_tag_sanitizer.dart). JPEG bytes differ between encoders, so outputs are structural. '
        'input {name, inFile (relative to app/fixtures/), fileName: name the file must have when run} → output '
        '{changed, unchangedSha256: whole-file hash when changed=false (file must be untouched), '
        'picture: first PICTURE block after the call when changed {pictureType, mime, description, width, height, '
        'depth, colors, decodedWidth, decodedHeight, decodedFormat, dataLength(Dart-encoder specific)}, '
        'blocks: [{type, isLast, sha256 (null for PICTURE)}] metadata block order after the call, '
        'audioSha256/audioLength: bytes after the last metadata block (must be unchanged), '
        'dartTotalLength/dartPictureDataLength: informational, encoder-specific}. Every changed case shrinks '
        'the picture by >=3x so encoder size differences cannot flip the result.',
    out,
  );
}
