// Stand-in for `import 'package:path/path.dart' as p;` in the bin/copies/windows
// copies: the same top-level API, bound to package:path's Windows context.
import 'package:path/path.dart' as path;

final _c = path.windows;

String get separator => _c.separator;

String join(String part1,
        [String? part2,
        String? part3,
        String? part4,
        String? part5,
        String? part6,
        String? part7,
        String? part8,
        String? part9,
        String? part10,
        String? part11,
        String? part12,
        String? part13,
        String? part14,
        String? part15,
        String? part16]) =>
    _c.join(part1, part2, part3, part4, part5, part6, part7, part8, part9,
        part10, part11, part12, part13, part14, part15, part16);

String joinAll(Iterable<String> parts) => _c.joinAll(parts);
List<String> split(String path) => _c.split(path);
String basename(String path) => _c.basename(path);
String basenameWithoutExtension(String path) =>
    _c.basenameWithoutExtension(path);
String dirname(String path) => _c.dirname(path);
String extension(String path, [int level = 1]) => _c.extension(path, level);
String relative(String path, {String? from}) => _c.relative(path, from: from);
