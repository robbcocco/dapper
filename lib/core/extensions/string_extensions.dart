extension StringExtensions on String {
  String toSafeFilename() {
    return replaceAll(RegExp(r'[/\\]'), '-')         // path separators → hyphen
        .replaceAll(RegExp(r'[:*?"<>|]'), '')        // other illegal chars → drop
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '') // control chars → drop
        .replaceAll(RegExp(r' {2,}'), ' ')           // collapse multiple spaces
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');  // strip leading/trailing dots & spaces
  }
}
