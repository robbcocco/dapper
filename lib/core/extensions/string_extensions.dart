// Windows blocks these as filenames even with an extension (CON.flac is
// equally rejected). Match is case-insensitive; we prefix with `_` to keep
// the original name readable.
final _kWindowsReserved = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false);

extension StringExtensions on String {
  String toSafeFilename() {
    var result = replaceAll('…', '...')                // ellipsis → three dots (normalise)
        .replaceAll('–', '-')                       // en dash → hyphen
        .replaceAll('—', '-')                       // em dash → hyphen
        .replaceAll(RegExp(r'[/\\]'), '-')               // path separators → hyphen
        .replaceAll(RegExp(r'[:*?"<>|]'), '')            // FAT32 illegal chars → drop
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')     // control chars → drop
        .replaceAll(RegExp(r' {2,}'), ' ')               // collapse multiple spaces
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');      // strip leading/trailing dots & spaces
    if (_kWindowsReserved.hasMatch(result)) {
      result = '_$result';
    }
    return result.isEmpty ? '_' : result;               // guard against empty result
  }
}
