class MbReleaseGroup {
  const MbReleaseGroup({
    required this.id,
    required this.title,
    this.artistName,
    this.firstReleaseDate,
  });

  final String id;
  final String title;
  final String? artistName;
  final String? firstReleaseDate;

  String? get year {
    final d = firstReleaseDate;
    if (d == null || d.isEmpty) return null;
    return d.split('-').first;
  }

  String get coverArtThumbUrl =>
      'https://coverartarchive.org/release-group/$id/front-250';

  factory MbReleaseGroup.fromJson(Map<String, dynamic> json) {
    final credits = json['artist-credit'] as List<dynamic>? ?? [];
    String? artistName;
    if (credits.isNotEmpty) {
      final first = credits.first as Map<String, dynamic>;
      artistName = first['name'] as String?;
    }
    return MbReleaseGroup(
      id: json['id'] as String,
      title: json['title'] as String,
      artistName: artistName,
      firstReleaseDate: json['first-release-date'] as String?,
    );
  }
}
