class LidarrArtist {
  const LidarrArtist({
    required this.id,
    required this.mbid,
    required this.name,
    required this.monitored,
    required this.albumCount,
    required this.trackFileCount,
    required this.totalTrackCount,
    required this.qualityProfileId,
    required this.tagIds,
    required this.genres,
    this.status,
    this.rootFolderPath,
    this.posterUrl,
    this.overview,
  });

  /// Lidarr's internal ID. 0 means the artist is a lookup result not yet added.
  final int id;

  /// MusicBrainz artist ID (foreignArtistId in Lidarr).
  final String mbid;

  final String name;
  final bool monitored;
  final String? status;
  final String? rootFolderPath;
  final String? posterUrl;
  final String? overview;

  final int albumCount;
  final int trackFileCount;
  final int totalTrackCount;
  final int qualityProfileId;
  final List<int> tagIds;
  final List<String> genres;

  bool get isInLidarr => id > 0;

  /// True when the artist is tracked but no track files have been downloaded.
  bool get isMissing =>
      isInLidarr && totalTrackCount > 0 && trackFileCount == 0;

  double get percentOfTracks =>
      totalTrackCount > 0 ? trackFileCount / totalTrackCount * 100 : 0;

  factory LidarrArtist.fromJson(Map<String, dynamic> json) {
    final images = (json['images'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final poster = images
        .where((img) => img['coverType'] == 'poster')
        .map((img) => img['remoteUrl'] as String? ?? img['url'] as String?)
        .whereType<String>()
        .firstOrNull;

    final stats = json['statistics'] as Map<String, dynamic>?;
    final rawTags = (json['tags'] as List<dynamic>?) ?? [];
    final rawGenres = (json['genres'] as List<dynamic>?) ?? [];

    return LidarrArtist(
      id: json['id'] as int? ?? 0,
      mbid: json['foreignArtistId'] as String? ?? '',
      name: json['artistName'] as String? ?? '',
      monitored: json['monitored'] as bool? ?? false,
      status: json['status'] as String?,
      rootFolderPath: json['rootFolderPath'] as String?,
      posterUrl: poster,
      overview: json['overview'] as String?,
      qualityProfileId: json['qualityProfileId'] as int? ?? 0,
      tagIds: rawTags.whereType<int>().toList(),
      genres: rawGenres.whereType<String>().toList(),
      albumCount: stats?['albumCount'] as int? ?? 0,
      trackFileCount: stats?['trackFileCount'] as int? ?? 0,
      totalTrackCount: stats?['totalTrackCount'] as int? ?? 0,
    );
  }
}

enum LidarrAlbumType {
  album,
  ep,
  single,
  other;

  static LidarrAlbumType fromString(String? s) => switch (s?.toLowerCase()) {
        'album' => album,
        'ep' => ep,
        'single' => single,
        _ => other,
      };

  String get label => switch (this) {
        LidarrAlbumType.album => 'Albums',
        LidarrAlbumType.ep => 'EPs',
        LidarrAlbumType.single => 'Singles',
        LidarrAlbumType.other => 'Other',
      };
}

class LidarrAlbum {
  const LidarrAlbum({
    required this.id,
    required this.title,
    required this.monitored,
    required this.hasFile,
    required this.albumType,
    this.releaseDate,
    this.coverUrl,
  });

  final int id;
  final String title;
  final bool monitored;

  /// True when at least one track file has been imported.
  final bool hasFile;
  final LidarrAlbumType albumType;
  final String? releaseDate;
  final String? coverUrl;

  int? get year {
    if (releaseDate == null || releaseDate!.isEmpty) return null;
    return int.tryParse(releaseDate!.split('-').first);
  }

  factory LidarrAlbum.fromJson(Map<String, dynamic> json) {
    final images = (json['images'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final cover = images
        .where((img) => img['coverType'] == 'cover')
        .map((img) => img['remoteUrl'] as String? ?? img['url'] as String?)
        .whereType<String>()
        .firstOrNull;

    final stats = json['statistics'] as Map<String, dynamic>?;
    final trackFileCount = stats?['trackFileCount'] as int? ?? 0;

    return LidarrAlbum(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      monitored: json['monitored'] as bool? ?? false,
      hasFile: trackFileCount > 0,
      albumType: LidarrAlbumType.fromString(json['albumType'] as String?),
      releaseDate: json['releaseDate'] as String?,
      coverUrl: cover,
    );
  }
}

class LidarrRelease {
  const LidarrRelease({
    required this.guid,
    required this.title,
    required this.indexer,
    required this.size,
    required this.protocol,
    required this.quality,
    required this.ageInDays,
    required this.rejected,
    required this.rejections,
    required this.raw,
    this.seeders,
    this.leechers,
  });

  final String guid;
  final String title;
  final String indexer;
  final int size;
  final String protocol; // 'torrent' | 'usenet'
  final String quality;
  final int ageInDays;
  final bool rejected;
  final List<String> rejections;
  final int? seeders;
  final int? leechers;

  /// Original JSON — sent back verbatim to POST /api/v1/release.
  final Map<String, dynamic> raw;

  String get formattedSize {
    if (size <= 0) return '—';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  factory LidarrRelease.fromJson(Map<String, dynamic> json) {
    final qualityNode =
        (json['quality'] as Map<String, dynamic>?)?['quality']
            as Map<String, dynamic>?;
    final rejectionList = (json['rejections'] as List<dynamic>?) ?? [];
    final rejections = rejectionList.map((r) {
      if (r is String) return r;
      if (r is Map<String, dynamic>) {
        return r['reason'] as String? ?? r.toString();
      }
      return r.toString();
    }).toList();

    return LidarrRelease(
      guid: json['guid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      indexer: json['indexer'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      protocol: json['protocol'] as String? ?? '',
      quality: qualityNode?['name'] as String? ?? '',
      ageInDays: json['age'] as int? ?? 0,
      rejected: rejections.isNotEmpty,
      rejections: rejections,
      seeders: json['seeders'] as int?,
      leechers: json['leechers'] as int?,
      raw: json,
    );
  }
}

class LidarrRootFolder {
  const LidarrRootFolder({required this.id, required this.path});

  final int id;
  final String path;

  factory LidarrRootFolder.fromJson(Map<String, dynamic> json) =>
      LidarrRootFolder(
        id: json['id'] as int,
        path: json['path'] as String,
      );

  @override
  String toString() => path;
}

class LidarrQualityProfile {
  const LidarrQualityProfile({required this.id, required this.name});

  final int id;
  final String name;

  factory LidarrQualityProfile.fromJson(Map<String, dynamic> json) =>
      LidarrQualityProfile(
        id: json['id'] as int,
        name: json['name'] as String,
      );

  @override
  String toString() => name;
}

// ── Custom filters ────────────────────────────────────────────────────────────

class LidarrCustomFilter {
  const LidarrCustomFilter({
    required this.id,
    required this.label,
    required this.conditions,
  });

  final int id;
  final String label;
  final List<LidarrFilterCondition> conditions;

  bool matches(LidarrArtist artist) =>
      conditions.every((c) => c.matches(artist));

  factory LidarrCustomFilter.fromJson(Map<String, dynamic> json) {
    final raw = (json['filters'] as List<dynamic>?) ?? [];
    return LidarrCustomFilter(
      id: json['id'] as int,
      label: json['label'] as String? ?? '',
      conditions: raw
          .cast<Map<String, dynamic>>()
          .map(LidarrFilterCondition.fromJson)
          .toList(),
    );
  }
}

class LidarrFilterCondition {
  const LidarrFilterCondition({
    required this.key,
    required this.values,
    required this.operator,
  });

  final String key;
  final List<String> values;
  final String operator;

  factory LidarrFilterCondition.fromJson(Map<String, dynamic> json) {
    final raw = json['value'];
    final values = switch (raw) {
      final List list => list.map((e) => e.toString()).toList(),
      null => <String>[],
      _ => [raw.toString()],
    };
    return LidarrFilterCondition(
      key: json['key'] as String? ?? '',
      values: values,
      operator: json['type'] as String? ?? '',
    );
  }

  bool matches(LidarrArtist artist) {
    // ── List fields (tags, genres) ────────────────────────────────────────────
    if (key == 'tags') {
      final ids = artist.tagIds.map((t) => t.toString()).toSet();
      return switch (operator) {
        'contains' => values.any(ids.contains),
        'notContain' => values.every((v) => !ids.contains(v)),
        _ => true,
      };
    }
    if (key == 'genres') {
      final gs = artist.genres.map((g) => g.toLowerCase()).toSet();
      return switch (operator) {
        'contains' =>
          values.any((v) => gs.contains(v.toLowerCase())),
        'notContain' =>
          values.every((v) => !gs.contains(v.toLowerCase())),
        _ => true,
      };
    }

    // ── Scalar fields ─────────────────────────────────────────────────────────
    final fieldValue = _scalarField(artist);
    if (fieldValue == null) return true; // unknown field — pass through
    return switch (operator) {
      'equal' => values.any((v) => _eq(fieldValue, v)),
      'notEqual' => values.every((v) => !_eq(fieldValue, v)),
      'contains' =>
        values.any((v) => fieldValue.toLowerCase().contains(v.toLowerCase())),
      'notContain' =>
        values.every((v) => !fieldValue.toLowerCase().contains(v.toLowerCase())),
      'lessThan' => _num(fieldValue) != null &&
          values.isNotEmpty &&
          _num(fieldValue)! < (_num(values.first) ?? 0),
      'greaterThan' => _num(fieldValue) != null &&
          values.isNotEmpty &&
          _num(fieldValue)! > (_num(values.first) ?? 0),
      _ => true,
    };
  }

  String? _scalarField(LidarrArtist a) => switch (key) {
        'monitored' => a.monitored.toString(),
        'status' => a.status,
        'qualityProfileId' => a.qualityProfileId.toString(),
        'rootFolderPath' => a.rootFolderPath,
        'albumCount' => a.albumCount.toString(),
        'trackFileCount' => a.trackFileCount.toString(),
        'totalTrackCount' => a.totalTrackCount.toString(),
        'percentOfTracks' => a.percentOfTracks.toStringAsFixed(1),
        _ => null,
      };

  bool _eq(String a, String b) => a.toLowerCase() == b.toLowerCase();
  double? _num(String s) => double.tryParse(s);
}
