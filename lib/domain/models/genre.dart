/// One genre as returned by Subsonic's `getGenres`. The counts come from the
/// server's library scan — useful for sorting / hiding zero-count entries.
class Genre {
  const Genre({
    required this.name,
    required this.songCount,
    required this.albumCount,
  });

  final String name;
  final int songCount;
  final int albumCount;
}
