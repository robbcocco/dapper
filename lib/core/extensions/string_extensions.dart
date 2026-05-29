extension StringExtensions on String {
  String toSafeFilename() {
    final result = replaceAll('…', '...')                // ellipsis → three dots (normalise)
        .replaceAll('–', '-')                       // en dash → hyphen
        .replaceAll('—', '-')                       // em dash → hyphen
        .replaceAll(RegExp(r'[/\\]'), '-')               // path separators → hyphen
        .replaceAll(RegExp(r'[:*?"<>|]'), '')            // FAT32 illegal chars → drop
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')     // control chars → drop
        .replaceAll(RegExp(r' {2,}'), ' ')               // collapse multiple spaces
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');      // strip leading/trailing dots & spaces
    return result.isEmpty ? '_' : result;               // guard against empty result
  }
}
