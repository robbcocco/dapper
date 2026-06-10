// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ArtistsTableTable extends ArtistsTable
    with TableInfo<$ArtistsTableTable, ArtistsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtistsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverArtIdMeta = const VerificationMeta(
    'coverArtId',
  );
  @override
  late final GeneratedColumn<String> coverArtId = GeneratedColumn<String>(
    'cover_art_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumCountMeta = const VerificationMeta(
    'albumCount',
  );
  @override
  late final GeneratedColumn<int> albumCount = GeneratedColumn<int>(
    'album_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, coverArtId, albumCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artists_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArtistsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('cover_art_id')) {
      context.handle(
        _coverArtIdMeta,
        coverArtId.isAcceptableOrUnknown(
          data['cover_art_id']!,
          _coverArtIdMeta,
        ),
      );
    }
    if (data.containsKey('album_count')) {
      context.handle(
        _albumCountMeta,
        albumCount.isAcceptableOrUnknown(data['album_count']!, _albumCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArtistsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArtistsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      coverArtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_art_id'],
      ),
      albumCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}album_count'],
      )!,
    );
  }

  @override
  $ArtistsTableTable createAlias(String alias) {
    return $ArtistsTableTable(attachedDatabase, alias);
  }
}

class ArtistsTableData extends DataClass
    implements Insertable<ArtistsTableData> {
  final String id;
  final String name;
  final String? coverArtId;
  final int albumCount;
  const ArtistsTableData({
    required this.id,
    required this.name,
    this.coverArtId,
    required this.albumCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || coverArtId != null) {
      map['cover_art_id'] = Variable<String>(coverArtId);
    }
    map['album_count'] = Variable<int>(albumCount);
    return map;
  }

  ArtistsTableCompanion toCompanion(bool nullToAbsent) {
    return ArtistsTableCompanion(
      id: Value(id),
      name: Value(name),
      coverArtId: coverArtId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverArtId),
      albumCount: Value(albumCount),
    );
  }

  factory ArtistsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArtistsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      coverArtId: serializer.fromJson<String?>(json['coverArtId']),
      albumCount: serializer.fromJson<int>(json['albumCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'coverArtId': serializer.toJson<String?>(coverArtId),
      'albumCount': serializer.toJson<int>(albumCount),
    };
  }

  ArtistsTableData copyWith({
    String? id,
    String? name,
    Value<String?> coverArtId = const Value.absent(),
    int? albumCount,
  }) => ArtistsTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    coverArtId: coverArtId.present ? coverArtId.value : this.coverArtId,
    albumCount: albumCount ?? this.albumCount,
  );
  ArtistsTableData copyWithCompanion(ArtistsTableCompanion data) {
    return ArtistsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      coverArtId: data.coverArtId.present
          ? data.coverArtId.value
          : this.coverArtId,
      albumCount: data.albumCount.present
          ? data.albumCount.value
          : this.albumCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArtistsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('coverArtId: $coverArtId, ')
          ..write('albumCount: $albumCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, coverArtId, albumCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArtistsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.coverArtId == this.coverArtId &&
          other.albumCount == this.albumCount);
}

class ArtistsTableCompanion extends UpdateCompanion<ArtistsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> coverArtId;
  final Value<int> albumCount;
  final Value<int> rowid;
  const ArtistsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.coverArtId = const Value.absent(),
    this.albumCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArtistsTableCompanion.insert({
    required String id,
    required String name,
    this.coverArtId = const Value.absent(),
    this.albumCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ArtistsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? coverArtId,
    Expression<int>? albumCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (coverArtId != null) 'cover_art_id': coverArtId,
      if (albumCount != null) 'album_count': albumCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArtistsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? coverArtId,
    Value<int>? albumCount,
    Value<int>? rowid,
  }) {
    return ArtistsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      coverArtId: coverArtId ?? this.coverArtId,
      albumCount: albumCount ?? this.albumCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (coverArtId.present) {
      map['cover_art_id'] = Variable<String>(coverArtId.value);
    }
    if (albumCount.present) {
      map['album_count'] = Variable<int>(albumCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtistsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('coverArtId: $coverArtId, ')
          ..write('albumCount: $albumCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumsTableTable extends AlbumsTable
    with TableInfo<$AlbumsTableTable, AlbumsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistIdMeta = const VerificationMeta(
    'artistId',
  );
  @override
  late final GeneratedColumn<String> artistId = GeneratedColumn<String>(
    'artist_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverArtIdMeta = const VerificationMeta(
    'coverArtId',
  );
  @override
  late final GeneratedColumn<String> coverArtId = GeneratedColumn<String>(
    'cover_art_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _songCountMeta = const VerificationMeta(
    'songCount',
  );
  @override
  late final GeneratedColumn<int> songCount = GeneratedColumn<int>(
    'song_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<int> duration = GeneratedColumn<int>(
    'duration',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    artistId,
    artist,
    coverArtId,
    year,
    genre,
    songCount,
    duration,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlbumsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artist_id')) {
      context.handle(
        _artistIdMeta,
        artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('cover_art_id')) {
      context.handle(
        _coverArtIdMeta,
        coverArtId.isAcceptableOrUnknown(
          data['cover_art_id']!,
          _coverArtIdMeta,
        ),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('song_count')) {
      context.handle(
        _songCountMeta,
        songCount.isAcceptableOrUnknown(data['song_count']!, _songCountMeta),
      );
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlbumsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      artistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_id'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      coverArtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_art_id'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      songCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}song_count'],
      )!,
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration'],
      )!,
    );
  }

  @override
  $AlbumsTableTable createAlias(String alias) {
    return $AlbumsTableTable(attachedDatabase, alias);
  }
}

class AlbumsTableData extends DataClass implements Insertable<AlbumsTableData> {
  final String id;
  final String name;
  final String? artistId;
  final String? artist;
  final String? coverArtId;
  final int? year;
  final String? genre;
  final int songCount;
  final int duration;
  const AlbumsTableData({
    required this.id,
    required this.name,
    this.artistId,
    this.artist,
    this.coverArtId,
    this.year,
    this.genre,
    required this.songCount,
    required this.duration,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<String>(artistId);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || coverArtId != null) {
      map['cover_art_id'] = Variable<String>(coverArtId);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    map['song_count'] = Variable<int>(songCount);
    map['duration'] = Variable<int>(duration);
    return map;
  }

  AlbumsTableCompanion toCompanion(bool nullToAbsent) {
    return AlbumsTableCompanion(
      id: Value(id),
      name: Value(name),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      coverArtId: coverArtId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverArtId),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      songCount: Value(songCount),
      duration: Value(duration),
    );
  }

  factory AlbumsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      artistId: serializer.fromJson<String?>(json['artistId']),
      artist: serializer.fromJson<String?>(json['artist']),
      coverArtId: serializer.fromJson<String?>(json['coverArtId']),
      year: serializer.fromJson<int?>(json['year']),
      genre: serializer.fromJson<String?>(json['genre']),
      songCount: serializer.fromJson<int>(json['songCount']),
      duration: serializer.fromJson<int>(json['duration']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'artistId': serializer.toJson<String?>(artistId),
      'artist': serializer.toJson<String?>(artist),
      'coverArtId': serializer.toJson<String?>(coverArtId),
      'year': serializer.toJson<int?>(year),
      'genre': serializer.toJson<String?>(genre),
      'songCount': serializer.toJson<int>(songCount),
      'duration': serializer.toJson<int>(duration),
    };
  }

  AlbumsTableData copyWith({
    String? id,
    String? name,
    Value<String?> artistId = const Value.absent(),
    Value<String?> artist = const Value.absent(),
    Value<String?> coverArtId = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    int? songCount,
    int? duration,
  }) => AlbumsTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    artistId: artistId.present ? artistId.value : this.artistId,
    artist: artist.present ? artist.value : this.artist,
    coverArtId: coverArtId.present ? coverArtId.value : this.coverArtId,
    year: year.present ? year.value : this.year,
    genre: genre.present ? genre.value : this.genre,
    songCount: songCount ?? this.songCount,
    duration: duration ?? this.duration,
  );
  AlbumsTableData copyWithCompanion(AlbumsTableCompanion data) {
    return AlbumsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      artist: data.artist.present ? data.artist.value : this.artist,
      coverArtId: data.coverArtId.present
          ? data.coverArtId.value
          : this.coverArtId,
      year: data.year.present ? data.year.value : this.year,
      genre: data.genre.present ? data.genre.value : this.genre,
      songCount: data.songCount.present ? data.songCount.value : this.songCount,
      duration: data.duration.present ? data.duration.value : this.duration,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('artistId: $artistId, ')
          ..write('artist: $artist, ')
          ..write('coverArtId: $coverArtId, ')
          ..write('year: $year, ')
          ..write('genre: $genre, ')
          ..write('songCount: $songCount, ')
          ..write('duration: $duration')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    artistId,
    artist,
    coverArtId,
    year,
    genre,
    songCount,
    duration,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.artistId == this.artistId &&
          other.artist == this.artist &&
          other.coverArtId == this.coverArtId &&
          other.year == this.year &&
          other.genre == this.genre &&
          other.songCount == this.songCount &&
          other.duration == this.duration);
}

class AlbumsTableCompanion extends UpdateCompanion<AlbumsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> artistId;
  final Value<String?> artist;
  final Value<String?> coverArtId;
  final Value<int?> year;
  final Value<String?> genre;
  final Value<int> songCount;
  final Value<int> duration;
  final Value<int> rowid;
  const AlbumsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.artistId = const Value.absent(),
    this.artist = const Value.absent(),
    this.coverArtId = const Value.absent(),
    this.year = const Value.absent(),
    this.genre = const Value.absent(),
    this.songCount = const Value.absent(),
    this.duration = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumsTableCompanion.insert({
    required String id,
    required String name,
    this.artistId = const Value.absent(),
    this.artist = const Value.absent(),
    this.coverArtId = const Value.absent(),
    this.year = const Value.absent(),
    this.genre = const Value.absent(),
    this.songCount = const Value.absent(),
    this.duration = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<AlbumsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? artistId,
    Expression<String>? artist,
    Expression<String>? coverArtId,
    Expression<int>? year,
    Expression<String>? genre,
    Expression<int>? songCount,
    Expression<int>? duration,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (artistId != null) 'artist_id': artistId,
      if (artist != null) 'artist': artist,
      if (coverArtId != null) 'cover_art_id': coverArtId,
      if (year != null) 'year': year,
      if (genre != null) 'genre': genre,
      if (songCount != null) 'song_count': songCount,
      if (duration != null) 'duration': duration,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? artistId,
    Value<String?>? artist,
    Value<String?>? coverArtId,
    Value<int?>? year,
    Value<String?>? genre,
    Value<int>? songCount,
    Value<int>? duration,
    Value<int>? rowid,
  }) {
    return AlbumsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      artistId: artistId ?? this.artistId,
      artist: artist ?? this.artist,
      coverArtId: coverArtId ?? this.coverArtId,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      songCount: songCount ?? this.songCount,
      duration: duration ?? this.duration,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<String>(artistId.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (coverArtId.present) {
      map['cover_art_id'] = Variable<String>(coverArtId.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (songCount.present) {
      map['song_count'] = Variable<int>(songCount.value);
    }
    if (duration.present) {
      map['duration'] = Variable<int>(duration.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('artistId: $artistId, ')
          ..write('artist: $artist, ')
          ..write('coverArtId: $coverArtId, ')
          ..write('year: $year, ')
          ..write('genre: $genre, ')
          ..write('songCount: $songCount, ')
          ..write('duration: $duration, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SongsTableTable extends SongsTable
    with TableInfo<$SongsTableTable, SongsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistIdMeta = const VerificationMeta(
    'artistId',
  );
  @override
  late final GeneratedColumn<String> artistId = GeneratedColumn<String>(
    'artist_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<int> duration = GeneratedColumn<int>(
    'duration',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bitRateMeta = const VerificationMeta(
    'bitRate',
  );
  @override
  late final GeneratedColumn<int> bitRate = GeneratedColumn<int>(
    'bit_rate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _suffixMeta = const VerificationMeta('suffix');
  @override
  late final GeneratedColumn<String> suffix = GeneratedColumn<String>(
    'suffix',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverArtIdMeta = const VerificationMeta(
    'coverArtId',
  );
  @override
  late final GeneratedColumn<String> coverArtId = GeneratedColumn<String>(
    'cover_art_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackMeta = const VerificationMeta('track');
  @override
  late final GeneratedColumn<int> track = GeneratedColumn<int>(
    'track',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discNumberMeta = const VerificationMeta(
    'discNumber',
  );
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
    'disc_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    albumId,
    artistId,
    album,
    artist,
    duration,
    bitRate,
    contentType,
    suffix,
    size,
    coverArtId,
    track,
    discNumber,
    year,
    genre,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    }
    if (data.containsKey('artist_id')) {
      context.handle(
        _artistIdMeta,
        artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    }
    if (data.containsKey('bit_rate')) {
      context.handle(
        _bitRateMeta,
        bitRate.isAcceptableOrUnknown(data['bit_rate']!, _bitRateMeta),
      );
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    }
    if (data.containsKey('suffix')) {
      context.handle(
        _suffixMeta,
        suffix.isAcceptableOrUnknown(data['suffix']!, _suffixMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('cover_art_id')) {
      context.handle(
        _coverArtIdMeta,
        coverArtId.isAcceptableOrUnknown(
          data['cover_art_id']!,
          _coverArtIdMeta,
        ),
      );
    }
    if (data.containsKey('track')) {
      context.handle(
        _trackMeta,
        track.isAcceptableOrUnknown(data['track']!, _trackMeta),
      );
    }
    if (data.containsKey('disc_number')) {
      context.handle(
        _discNumberMeta,
        discNumber.isAcceptableOrUnknown(data['disc_number']!, _discNumberMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SongsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      ),
      artistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_id'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration'],
      ),
      bitRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bit_rate'],
      ),
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      ),
      suffix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suffix'],
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      ),
      coverArtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_art_id'],
      ),
      track: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track'],
      ),
      discNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc_number'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
    );
  }

  @override
  $SongsTableTable createAlias(String alias) {
    return $SongsTableTable(attachedDatabase, alias);
  }
}

class SongsTableData extends DataClass implements Insertable<SongsTableData> {
  final String id;
  final String title;
  final String? albumId;
  final String? artistId;
  final String? album;
  final String? artist;
  final int? duration;
  final int? bitRate;
  final String? contentType;
  final String? suffix;
  final int? size;
  final String? coverArtId;
  final int? track;
  final int? discNumber;
  final int? year;
  final String? genre;
  const SongsTableData({
    required this.id,
    required this.title,
    this.albumId,
    this.artistId,
    this.album,
    this.artist,
    this.duration,
    this.bitRate,
    this.contentType,
    this.suffix,
    this.size,
    this.coverArtId,
    this.track,
    this.discNumber,
    this.year,
    this.genre,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<String>(albumId);
    }
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<String>(artistId);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || duration != null) {
      map['duration'] = Variable<int>(duration);
    }
    if (!nullToAbsent || bitRate != null) {
      map['bit_rate'] = Variable<int>(bitRate);
    }
    if (!nullToAbsent || contentType != null) {
      map['content_type'] = Variable<String>(contentType);
    }
    if (!nullToAbsent || suffix != null) {
      map['suffix'] = Variable<String>(suffix);
    }
    if (!nullToAbsent || size != null) {
      map['size'] = Variable<int>(size);
    }
    if (!nullToAbsent || coverArtId != null) {
      map['cover_art_id'] = Variable<String>(coverArtId);
    }
    if (!nullToAbsent || track != null) {
      map['track'] = Variable<int>(track);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    return map;
  }

  SongsTableCompanion toCompanion(bool nullToAbsent) {
    return SongsTableCompanion(
      id: Value(id),
      title: Value(title),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      duration: duration == null && nullToAbsent
          ? const Value.absent()
          : Value(duration),
      bitRate: bitRate == null && nullToAbsent
          ? const Value.absent()
          : Value(bitRate),
      contentType: contentType == null && nullToAbsent
          ? const Value.absent()
          : Value(contentType),
      suffix: suffix == null && nullToAbsent
          ? const Value.absent()
          : Value(suffix),
      size: size == null && nullToAbsent ? const Value.absent() : Value(size),
      coverArtId: coverArtId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverArtId),
      track: track == null && nullToAbsent
          ? const Value.absent()
          : Value(track),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
    );
  }

  factory SongsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongsTableData(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      albumId: serializer.fromJson<String?>(json['albumId']),
      artistId: serializer.fromJson<String?>(json['artistId']),
      album: serializer.fromJson<String?>(json['album']),
      artist: serializer.fromJson<String?>(json['artist']),
      duration: serializer.fromJson<int?>(json['duration']),
      bitRate: serializer.fromJson<int?>(json['bitRate']),
      contentType: serializer.fromJson<String?>(json['contentType']),
      suffix: serializer.fromJson<String?>(json['suffix']),
      size: serializer.fromJson<int?>(json['size']),
      coverArtId: serializer.fromJson<String?>(json['coverArtId']),
      track: serializer.fromJson<int?>(json['track']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      year: serializer.fromJson<int?>(json['year']),
      genre: serializer.fromJson<String?>(json['genre']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'albumId': serializer.toJson<String?>(albumId),
      'artistId': serializer.toJson<String?>(artistId),
      'album': serializer.toJson<String?>(album),
      'artist': serializer.toJson<String?>(artist),
      'duration': serializer.toJson<int?>(duration),
      'bitRate': serializer.toJson<int?>(bitRate),
      'contentType': serializer.toJson<String?>(contentType),
      'suffix': serializer.toJson<String?>(suffix),
      'size': serializer.toJson<int?>(size),
      'coverArtId': serializer.toJson<String?>(coverArtId),
      'track': serializer.toJson<int?>(track),
      'discNumber': serializer.toJson<int?>(discNumber),
      'year': serializer.toJson<int?>(year),
      'genre': serializer.toJson<String?>(genre),
    };
  }

  SongsTableData copyWith({
    String? id,
    String? title,
    Value<String?> albumId = const Value.absent(),
    Value<String?> artistId = const Value.absent(),
    Value<String?> album = const Value.absent(),
    Value<String?> artist = const Value.absent(),
    Value<int?> duration = const Value.absent(),
    Value<int?> bitRate = const Value.absent(),
    Value<String?> contentType = const Value.absent(),
    Value<String?> suffix = const Value.absent(),
    Value<int?> size = const Value.absent(),
    Value<String?> coverArtId = const Value.absent(),
    Value<int?> track = const Value.absent(),
    Value<int?> discNumber = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> genre = const Value.absent(),
  }) => SongsTableData(
    id: id ?? this.id,
    title: title ?? this.title,
    albumId: albumId.present ? albumId.value : this.albumId,
    artistId: artistId.present ? artistId.value : this.artistId,
    album: album.present ? album.value : this.album,
    artist: artist.present ? artist.value : this.artist,
    duration: duration.present ? duration.value : this.duration,
    bitRate: bitRate.present ? bitRate.value : this.bitRate,
    contentType: contentType.present ? contentType.value : this.contentType,
    suffix: suffix.present ? suffix.value : this.suffix,
    size: size.present ? size.value : this.size,
    coverArtId: coverArtId.present ? coverArtId.value : this.coverArtId,
    track: track.present ? track.value : this.track,
    discNumber: discNumber.present ? discNumber.value : this.discNumber,
    year: year.present ? year.value : this.year,
    genre: genre.present ? genre.value : this.genre,
  );
  SongsTableData copyWithCompanion(SongsTableCompanion data) {
    return SongsTableData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      album: data.album.present ? data.album.value : this.album,
      artist: data.artist.present ? data.artist.value : this.artist,
      duration: data.duration.present ? data.duration.value : this.duration,
      bitRate: data.bitRate.present ? data.bitRate.value : this.bitRate,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      suffix: data.suffix.present ? data.suffix.value : this.suffix,
      size: data.size.present ? data.size.value : this.size,
      coverArtId: data.coverArtId.present
          ? data.coverArtId.value
          : this.coverArtId,
      track: data.track.present ? data.track.value : this.track,
      discNumber: data.discNumber.present
          ? data.discNumber.value
          : this.discNumber,
      year: data.year.present ? data.year.value : this.year,
      genre: data.genre.present ? data.genre.value : this.genre,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongsTableData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('albumId: $albumId, ')
          ..write('artistId: $artistId, ')
          ..write('album: $album, ')
          ..write('artist: $artist, ')
          ..write('duration: $duration, ')
          ..write('bitRate: $bitRate, ')
          ..write('contentType: $contentType, ')
          ..write('suffix: $suffix, ')
          ..write('size: $size, ')
          ..write('coverArtId: $coverArtId, ')
          ..write('track: $track, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('genre: $genre')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    albumId,
    artistId,
    album,
    artist,
    duration,
    bitRate,
    contentType,
    suffix,
    size,
    coverArtId,
    track,
    discNumber,
    year,
    genre,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongsTableData &&
          other.id == this.id &&
          other.title == this.title &&
          other.albumId == this.albumId &&
          other.artistId == this.artistId &&
          other.album == this.album &&
          other.artist == this.artist &&
          other.duration == this.duration &&
          other.bitRate == this.bitRate &&
          other.contentType == this.contentType &&
          other.suffix == this.suffix &&
          other.size == this.size &&
          other.coverArtId == this.coverArtId &&
          other.track == this.track &&
          other.discNumber == this.discNumber &&
          other.year == this.year &&
          other.genre == this.genre);
}

class SongsTableCompanion extends UpdateCompanion<SongsTableData> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> albumId;
  final Value<String?> artistId;
  final Value<String?> album;
  final Value<String?> artist;
  final Value<int?> duration;
  final Value<int?> bitRate;
  final Value<String?> contentType;
  final Value<String?> suffix;
  final Value<int?> size;
  final Value<String?> coverArtId;
  final Value<int?> track;
  final Value<int?> discNumber;
  final Value<int?> year;
  final Value<String?> genre;
  final Value<int> rowid;
  const SongsTableCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.albumId = const Value.absent(),
    this.artistId = const Value.absent(),
    this.album = const Value.absent(),
    this.artist = const Value.absent(),
    this.duration = const Value.absent(),
    this.bitRate = const Value.absent(),
    this.contentType = const Value.absent(),
    this.suffix = const Value.absent(),
    this.size = const Value.absent(),
    this.coverArtId = const Value.absent(),
    this.track = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.genre = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SongsTableCompanion.insert({
    required String id,
    required String title,
    this.albumId = const Value.absent(),
    this.artistId = const Value.absent(),
    this.album = const Value.absent(),
    this.artist = const Value.absent(),
    this.duration = const Value.absent(),
    this.bitRate = const Value.absent(),
    this.contentType = const Value.absent(),
    this.suffix = const Value.absent(),
    this.size = const Value.absent(),
    this.coverArtId = const Value.absent(),
    this.track = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.year = const Value.absent(),
    this.genre = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title);
  static Insertable<SongsTableData> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? albumId,
    Expression<String>? artistId,
    Expression<String>? album,
    Expression<String>? artist,
    Expression<int>? duration,
    Expression<int>? bitRate,
    Expression<String>? contentType,
    Expression<String>? suffix,
    Expression<int>? size,
    Expression<String>? coverArtId,
    Expression<int>? track,
    Expression<int>? discNumber,
    Expression<int>? year,
    Expression<String>? genre,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (albumId != null) 'album_id': albumId,
      if (artistId != null) 'artist_id': artistId,
      if (album != null) 'album': album,
      if (artist != null) 'artist': artist,
      if (duration != null) 'duration': duration,
      if (bitRate != null) 'bit_rate': bitRate,
      if (contentType != null) 'content_type': contentType,
      if (suffix != null) 'suffix': suffix,
      if (size != null) 'size': size,
      if (coverArtId != null) 'cover_art_id': coverArtId,
      if (track != null) 'track': track,
      if (discNumber != null) 'disc_number': discNumber,
      if (year != null) 'year': year,
      if (genre != null) 'genre': genre,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SongsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? albumId,
    Value<String?>? artistId,
    Value<String?>? album,
    Value<String?>? artist,
    Value<int?>? duration,
    Value<int?>? bitRate,
    Value<String?>? contentType,
    Value<String?>? suffix,
    Value<int?>? size,
    Value<String?>? coverArtId,
    Value<int?>? track,
    Value<int?>? discNumber,
    Value<int?>? year,
    Value<String?>? genre,
    Value<int>? rowid,
  }) {
    return SongsTableCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      albumId: albumId ?? this.albumId,
      artistId: artistId ?? this.artistId,
      album: album ?? this.album,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      bitRate: bitRate ?? this.bitRate,
      contentType: contentType ?? this.contentType,
      suffix: suffix ?? this.suffix,
      size: size ?? this.size,
      coverArtId: coverArtId ?? this.coverArtId,
      track: track ?? this.track,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<String>(artistId.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (duration.present) {
      map['duration'] = Variable<int>(duration.value);
    }
    if (bitRate.present) {
      map['bit_rate'] = Variable<int>(bitRate.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (suffix.present) {
      map['suffix'] = Variable<String>(suffix.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (coverArtId.present) {
      map['cover_art_id'] = Variable<String>(coverArtId.value);
    }
    if (track.present) {
      map['track'] = Variable<int>(track.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsTableCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('albumId: $albumId, ')
          ..write('artistId: $artistId, ')
          ..write('album: $album, ')
          ..write('artist: $artist, ')
          ..write('duration: $duration, ')
          ..write('bitRate: $bitRate, ')
          ..write('contentType: $contentType, ')
          ..write('suffix: $suffix, ')
          ..write('size: $size, ')
          ..write('coverArtId: $coverArtId, ')
          ..write('track: $track, ')
          ..write('discNumber: $discNumber, ')
          ..write('year: $year, ')
          ..write('genre: $genre, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceSettingsTableTable extends DeviceSettingsTable
    with TableInfo<$DeviceSettingsTableTable, DeviceSettingsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _devicePathMeta = const VerificationMeta(
    'devicePath',
  );
  @override
  late final GeneratedColumn<String> devicePath = GeneratedColumn<String>(
    'device_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _musicRootFolderMeta = const VerificationMeta(
    'musicRootFolder',
  );
  @override
  late final GeneratedColumn<String> musicRootFolder = GeneratedColumn<String>(
    'music_root_folder',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _playlistFolderMeta = const VerificationMeta(
    'playlistFolder',
  );
  @override
  late final GeneratedColumn<String> playlistFolder = GeneratedColumn<String>(
    'playlist_folder',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Playlists'),
  );
  static const VerificationMeta _folderStructureMeta = const VerificationMeta(
    'folderStructure',
  );
  @override
  late final GeneratedColumn<String> folderStructure = GeneratedColumn<String>(
    'folder_structure',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('artistAlbum'),
  );
  static const VerificationMeta _filenameFormatMeta = const VerificationMeta(
    'filenameFormat',
  );
  @override
  late final GeneratedColumn<String> filenameFormat = GeneratedColumn<String>(
    'filename_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('discTrack'),
  );
  static const VerificationMeta _includeYearMeta = const VerificationMeta(
    'includeYear',
  );
  @override
  late final GeneratedColumn<bool> includeYear = GeneratedColumn<bool>(
    'include_year',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("include_year" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _overwriteExistingMeta = const VerificationMeta(
    'overwriteExisting',
  );
  @override
  late final GeneratedColumn<bool> overwriteExisting = GeneratedColumn<bool>(
    'overwrite_existing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("overwrite_existing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _transcodeFormatMeta = const VerificationMeta(
    'transcodeFormat',
  );
  @override
  late final GeneratedColumn<String> transcodeFormat = GeneratedColumn<String>(
    'transcode_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('original'),
  );
  static const VerificationMeta _transcodeMaxBitRateMeta =
      const VerificationMeta('transcodeMaxBitRate');
  @override
  late final GeneratedColumn<int> transcodeMaxBitRate = GeneratedColumn<int>(
    'transcode_max_bit_rate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _useZipDownloadMeta = const VerificationMeta(
    'useZipDownload',
  );
  @override
  late final GeneratedColumn<bool> useZipDownload = GeneratedColumn<bool>(
    'use_zip_download',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_zip_download" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _customFilenameTemplateMeta =
      const VerificationMeta('customFilenameTemplate');
  @override
  late final GeneratedColumn<String> customFilenameTemplate =
      GeneratedColumn<String>(
        'custom_filename_template',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _customFolderTemplateMeta =
      const VerificationMeta('customFolderTemplate');
  @override
  late final GeneratedColumn<String> customFolderTemplate =
      GeneratedColumn<String>(
        'custom_folder_template',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  @override
  List<GeneratedColumn> get $columns => [
    devicePath,
    musicRootFolder,
    playlistFolder,
    folderStructure,
    filenameFormat,
    includeYear,
    overwriteExisting,
    transcodeFormat,
    transcodeMaxBitRate,
    useZipDownload,
    customFilenameTemplate,
    customFolderTemplate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_settings_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceSettingsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_path')) {
      context.handle(
        _devicePathMeta,
        devicePath.isAcceptableOrUnknown(data['device_path']!, _devicePathMeta),
      );
    } else if (isInserting) {
      context.missing(_devicePathMeta);
    }
    if (data.containsKey('music_root_folder')) {
      context.handle(
        _musicRootFolderMeta,
        musicRootFolder.isAcceptableOrUnknown(
          data['music_root_folder']!,
          _musicRootFolderMeta,
        ),
      );
    }
    if (data.containsKey('playlist_folder')) {
      context.handle(
        _playlistFolderMeta,
        playlistFolder.isAcceptableOrUnknown(
          data['playlist_folder']!,
          _playlistFolderMeta,
        ),
      );
    }
    if (data.containsKey('folder_structure')) {
      context.handle(
        _folderStructureMeta,
        folderStructure.isAcceptableOrUnknown(
          data['folder_structure']!,
          _folderStructureMeta,
        ),
      );
    }
    if (data.containsKey('filename_format')) {
      context.handle(
        _filenameFormatMeta,
        filenameFormat.isAcceptableOrUnknown(
          data['filename_format']!,
          _filenameFormatMeta,
        ),
      );
    }
    if (data.containsKey('include_year')) {
      context.handle(
        _includeYearMeta,
        includeYear.isAcceptableOrUnknown(
          data['include_year']!,
          _includeYearMeta,
        ),
      );
    }
    if (data.containsKey('overwrite_existing')) {
      context.handle(
        _overwriteExistingMeta,
        overwriteExisting.isAcceptableOrUnknown(
          data['overwrite_existing']!,
          _overwriteExistingMeta,
        ),
      );
    }
    if (data.containsKey('transcode_format')) {
      context.handle(
        _transcodeFormatMeta,
        transcodeFormat.isAcceptableOrUnknown(
          data['transcode_format']!,
          _transcodeFormatMeta,
        ),
      );
    }
    if (data.containsKey('transcode_max_bit_rate')) {
      context.handle(
        _transcodeMaxBitRateMeta,
        transcodeMaxBitRate.isAcceptableOrUnknown(
          data['transcode_max_bit_rate']!,
          _transcodeMaxBitRateMeta,
        ),
      );
    }
    if (data.containsKey('use_zip_download')) {
      context.handle(
        _useZipDownloadMeta,
        useZipDownload.isAcceptableOrUnknown(
          data['use_zip_download']!,
          _useZipDownloadMeta,
        ),
      );
    }
    if (data.containsKey('custom_filename_template')) {
      context.handle(
        _customFilenameTemplateMeta,
        customFilenameTemplate.isAcceptableOrUnknown(
          data['custom_filename_template']!,
          _customFilenameTemplateMeta,
        ),
      );
    }
    if (data.containsKey('custom_folder_template')) {
      context.handle(
        _customFolderTemplateMeta,
        customFolderTemplate.isAcceptableOrUnknown(
          data['custom_folder_template']!,
          _customFolderTemplateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {devicePath};
  @override
  DeviceSettingsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceSettingsTableData(
      devicePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_path'],
      )!,
      musicRootFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}music_root_folder'],
      )!,
      playlistFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_folder'],
      )!,
      folderStructure: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_structure'],
      )!,
      filenameFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename_format'],
      )!,
      includeYear: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}include_year'],
      )!,
      overwriteExisting: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}overwrite_existing'],
      )!,
      transcodeFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transcode_format'],
      )!,
      transcodeMaxBitRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transcode_max_bit_rate'],
      ),
      useZipDownload: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_zip_download'],
      )!,
      customFilenameTemplate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_filename_template'],
      )!,
      customFolderTemplate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_folder_template'],
      )!,
    );
  }

  @override
  $DeviceSettingsTableTable createAlias(String alias) {
    return $DeviceSettingsTableTable(attachedDatabase, alias);
  }
}

class DeviceSettingsTableData extends DataClass
    implements Insertable<DeviceSettingsTableData> {
  final String devicePath;
  final String musicRootFolder;
  final String playlistFolder;
  final String folderStructure;
  final String filenameFormat;
  final bool includeYear;
  final bool overwriteExisting;
  final String transcodeFormat;
  final int? transcodeMaxBitRate;
  final bool useZipDownload;
  final String customFilenameTemplate;
  final String customFolderTemplate;
  const DeviceSettingsTableData({
    required this.devicePath,
    required this.musicRootFolder,
    required this.playlistFolder,
    required this.folderStructure,
    required this.filenameFormat,
    required this.includeYear,
    required this.overwriteExisting,
    required this.transcodeFormat,
    this.transcodeMaxBitRate,
    required this.useZipDownload,
    required this.customFilenameTemplate,
    required this.customFolderTemplate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_path'] = Variable<String>(devicePath);
    map['music_root_folder'] = Variable<String>(musicRootFolder);
    map['playlist_folder'] = Variable<String>(playlistFolder);
    map['folder_structure'] = Variable<String>(folderStructure);
    map['filename_format'] = Variable<String>(filenameFormat);
    map['include_year'] = Variable<bool>(includeYear);
    map['overwrite_existing'] = Variable<bool>(overwriteExisting);
    map['transcode_format'] = Variable<String>(transcodeFormat);
    if (!nullToAbsent || transcodeMaxBitRate != null) {
      map['transcode_max_bit_rate'] = Variable<int>(transcodeMaxBitRate);
    }
    map['use_zip_download'] = Variable<bool>(useZipDownload);
    map['custom_filename_template'] = Variable<String>(customFilenameTemplate);
    map['custom_folder_template'] = Variable<String>(customFolderTemplate);
    return map;
  }

  DeviceSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return DeviceSettingsTableCompanion(
      devicePath: Value(devicePath),
      musicRootFolder: Value(musicRootFolder),
      playlistFolder: Value(playlistFolder),
      folderStructure: Value(folderStructure),
      filenameFormat: Value(filenameFormat),
      includeYear: Value(includeYear),
      overwriteExisting: Value(overwriteExisting),
      transcodeFormat: Value(transcodeFormat),
      transcodeMaxBitRate: transcodeMaxBitRate == null && nullToAbsent
          ? const Value.absent()
          : Value(transcodeMaxBitRate),
      useZipDownload: Value(useZipDownload),
      customFilenameTemplate: Value(customFilenameTemplate),
      customFolderTemplate: Value(customFolderTemplate),
    );
  }

  factory DeviceSettingsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceSettingsTableData(
      devicePath: serializer.fromJson<String>(json['devicePath']),
      musicRootFolder: serializer.fromJson<String>(json['musicRootFolder']),
      playlistFolder: serializer.fromJson<String>(json['playlistFolder']),
      folderStructure: serializer.fromJson<String>(json['folderStructure']),
      filenameFormat: serializer.fromJson<String>(json['filenameFormat']),
      includeYear: serializer.fromJson<bool>(json['includeYear']),
      overwriteExisting: serializer.fromJson<bool>(json['overwriteExisting']),
      transcodeFormat: serializer.fromJson<String>(json['transcodeFormat']),
      transcodeMaxBitRate: serializer.fromJson<int?>(
        json['transcodeMaxBitRate'],
      ),
      useZipDownload: serializer.fromJson<bool>(json['useZipDownload']),
      customFilenameTemplate: serializer.fromJson<String>(
        json['customFilenameTemplate'],
      ),
      customFolderTemplate: serializer.fromJson<String>(
        json['customFolderTemplate'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'devicePath': serializer.toJson<String>(devicePath),
      'musicRootFolder': serializer.toJson<String>(musicRootFolder),
      'playlistFolder': serializer.toJson<String>(playlistFolder),
      'folderStructure': serializer.toJson<String>(folderStructure),
      'filenameFormat': serializer.toJson<String>(filenameFormat),
      'includeYear': serializer.toJson<bool>(includeYear),
      'overwriteExisting': serializer.toJson<bool>(overwriteExisting),
      'transcodeFormat': serializer.toJson<String>(transcodeFormat),
      'transcodeMaxBitRate': serializer.toJson<int?>(transcodeMaxBitRate),
      'useZipDownload': serializer.toJson<bool>(useZipDownload),
      'customFilenameTemplate': serializer.toJson<String>(
        customFilenameTemplate,
      ),
      'customFolderTemplate': serializer.toJson<String>(customFolderTemplate),
    };
  }

  DeviceSettingsTableData copyWith({
    String? devicePath,
    String? musicRootFolder,
    String? playlistFolder,
    String? folderStructure,
    String? filenameFormat,
    bool? includeYear,
    bool? overwriteExisting,
    String? transcodeFormat,
    Value<int?> transcodeMaxBitRate = const Value.absent(),
    bool? useZipDownload,
    String? customFilenameTemplate,
    String? customFolderTemplate,
  }) => DeviceSettingsTableData(
    devicePath: devicePath ?? this.devicePath,
    musicRootFolder: musicRootFolder ?? this.musicRootFolder,
    playlistFolder: playlistFolder ?? this.playlistFolder,
    folderStructure: folderStructure ?? this.folderStructure,
    filenameFormat: filenameFormat ?? this.filenameFormat,
    includeYear: includeYear ?? this.includeYear,
    overwriteExisting: overwriteExisting ?? this.overwriteExisting,
    transcodeFormat: transcodeFormat ?? this.transcodeFormat,
    transcodeMaxBitRate: transcodeMaxBitRate.present
        ? transcodeMaxBitRate.value
        : this.transcodeMaxBitRate,
    useZipDownload: useZipDownload ?? this.useZipDownload,
    customFilenameTemplate:
        customFilenameTemplate ?? this.customFilenameTemplate,
    customFolderTemplate: customFolderTemplate ?? this.customFolderTemplate,
  );
  DeviceSettingsTableData copyWithCompanion(DeviceSettingsTableCompanion data) {
    return DeviceSettingsTableData(
      devicePath: data.devicePath.present
          ? data.devicePath.value
          : this.devicePath,
      musicRootFolder: data.musicRootFolder.present
          ? data.musicRootFolder.value
          : this.musicRootFolder,
      playlistFolder: data.playlistFolder.present
          ? data.playlistFolder.value
          : this.playlistFolder,
      folderStructure: data.folderStructure.present
          ? data.folderStructure.value
          : this.folderStructure,
      filenameFormat: data.filenameFormat.present
          ? data.filenameFormat.value
          : this.filenameFormat,
      includeYear: data.includeYear.present
          ? data.includeYear.value
          : this.includeYear,
      overwriteExisting: data.overwriteExisting.present
          ? data.overwriteExisting.value
          : this.overwriteExisting,
      transcodeFormat: data.transcodeFormat.present
          ? data.transcodeFormat.value
          : this.transcodeFormat,
      transcodeMaxBitRate: data.transcodeMaxBitRate.present
          ? data.transcodeMaxBitRate.value
          : this.transcodeMaxBitRate,
      useZipDownload: data.useZipDownload.present
          ? data.useZipDownload.value
          : this.useZipDownload,
      customFilenameTemplate: data.customFilenameTemplate.present
          ? data.customFilenameTemplate.value
          : this.customFilenameTemplate,
      customFolderTemplate: data.customFolderTemplate.present
          ? data.customFolderTemplate.value
          : this.customFolderTemplate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceSettingsTableData(')
          ..write('devicePath: $devicePath, ')
          ..write('musicRootFolder: $musicRootFolder, ')
          ..write('playlistFolder: $playlistFolder, ')
          ..write('folderStructure: $folderStructure, ')
          ..write('filenameFormat: $filenameFormat, ')
          ..write('includeYear: $includeYear, ')
          ..write('overwriteExisting: $overwriteExisting, ')
          ..write('transcodeFormat: $transcodeFormat, ')
          ..write('transcodeMaxBitRate: $transcodeMaxBitRate, ')
          ..write('useZipDownload: $useZipDownload, ')
          ..write('customFilenameTemplate: $customFilenameTemplate, ')
          ..write('customFolderTemplate: $customFolderTemplate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    devicePath,
    musicRootFolder,
    playlistFolder,
    folderStructure,
    filenameFormat,
    includeYear,
    overwriteExisting,
    transcodeFormat,
    transcodeMaxBitRate,
    useZipDownload,
    customFilenameTemplate,
    customFolderTemplate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceSettingsTableData &&
          other.devicePath == this.devicePath &&
          other.musicRootFolder == this.musicRootFolder &&
          other.playlistFolder == this.playlistFolder &&
          other.folderStructure == this.folderStructure &&
          other.filenameFormat == this.filenameFormat &&
          other.includeYear == this.includeYear &&
          other.overwriteExisting == this.overwriteExisting &&
          other.transcodeFormat == this.transcodeFormat &&
          other.transcodeMaxBitRate == this.transcodeMaxBitRate &&
          other.useZipDownload == this.useZipDownload &&
          other.customFilenameTemplate == this.customFilenameTemplate &&
          other.customFolderTemplate == this.customFolderTemplate);
}

class DeviceSettingsTableCompanion
    extends UpdateCompanion<DeviceSettingsTableData> {
  final Value<String> devicePath;
  final Value<String> musicRootFolder;
  final Value<String> playlistFolder;
  final Value<String> folderStructure;
  final Value<String> filenameFormat;
  final Value<bool> includeYear;
  final Value<bool> overwriteExisting;
  final Value<String> transcodeFormat;
  final Value<int?> transcodeMaxBitRate;
  final Value<bool> useZipDownload;
  final Value<String> customFilenameTemplate;
  final Value<String> customFolderTemplate;
  final Value<int> rowid;
  const DeviceSettingsTableCompanion({
    this.devicePath = const Value.absent(),
    this.musicRootFolder = const Value.absent(),
    this.playlistFolder = const Value.absent(),
    this.folderStructure = const Value.absent(),
    this.filenameFormat = const Value.absent(),
    this.includeYear = const Value.absent(),
    this.overwriteExisting = const Value.absent(),
    this.transcodeFormat = const Value.absent(),
    this.transcodeMaxBitRate = const Value.absent(),
    this.useZipDownload = const Value.absent(),
    this.customFilenameTemplate = const Value.absent(),
    this.customFolderTemplate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceSettingsTableCompanion.insert({
    required String devicePath,
    this.musicRootFolder = const Value.absent(),
    this.playlistFolder = const Value.absent(),
    this.folderStructure = const Value.absent(),
    this.filenameFormat = const Value.absent(),
    this.includeYear = const Value.absent(),
    this.overwriteExisting = const Value.absent(),
    this.transcodeFormat = const Value.absent(),
    this.transcodeMaxBitRate = const Value.absent(),
    this.useZipDownload = const Value.absent(),
    this.customFilenameTemplate = const Value.absent(),
    this.customFolderTemplate = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : devicePath = Value(devicePath);
  static Insertable<DeviceSettingsTableData> custom({
    Expression<String>? devicePath,
    Expression<String>? musicRootFolder,
    Expression<String>? playlistFolder,
    Expression<String>? folderStructure,
    Expression<String>? filenameFormat,
    Expression<bool>? includeYear,
    Expression<bool>? overwriteExisting,
    Expression<String>? transcodeFormat,
    Expression<int>? transcodeMaxBitRate,
    Expression<bool>? useZipDownload,
    Expression<String>? customFilenameTemplate,
    Expression<String>? customFolderTemplate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (devicePath != null) 'device_path': devicePath,
      if (musicRootFolder != null) 'music_root_folder': musicRootFolder,
      if (playlistFolder != null) 'playlist_folder': playlistFolder,
      if (folderStructure != null) 'folder_structure': folderStructure,
      if (filenameFormat != null) 'filename_format': filenameFormat,
      if (includeYear != null) 'include_year': includeYear,
      if (overwriteExisting != null) 'overwrite_existing': overwriteExisting,
      if (transcodeFormat != null) 'transcode_format': transcodeFormat,
      if (transcodeMaxBitRate != null)
        'transcode_max_bit_rate': transcodeMaxBitRate,
      if (useZipDownload != null) 'use_zip_download': useZipDownload,
      if (customFilenameTemplate != null)
        'custom_filename_template': customFilenameTemplate,
      if (customFolderTemplate != null)
        'custom_folder_template': customFolderTemplate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceSettingsTableCompanion copyWith({
    Value<String>? devicePath,
    Value<String>? musicRootFolder,
    Value<String>? playlistFolder,
    Value<String>? folderStructure,
    Value<String>? filenameFormat,
    Value<bool>? includeYear,
    Value<bool>? overwriteExisting,
    Value<String>? transcodeFormat,
    Value<int?>? transcodeMaxBitRate,
    Value<bool>? useZipDownload,
    Value<String>? customFilenameTemplate,
    Value<String>? customFolderTemplate,
    Value<int>? rowid,
  }) {
    return DeviceSettingsTableCompanion(
      devicePath: devicePath ?? this.devicePath,
      musicRootFolder: musicRootFolder ?? this.musicRootFolder,
      playlistFolder: playlistFolder ?? this.playlistFolder,
      folderStructure: folderStructure ?? this.folderStructure,
      filenameFormat: filenameFormat ?? this.filenameFormat,
      includeYear: includeYear ?? this.includeYear,
      overwriteExisting: overwriteExisting ?? this.overwriteExisting,
      transcodeFormat: transcodeFormat ?? this.transcodeFormat,
      transcodeMaxBitRate: transcodeMaxBitRate ?? this.transcodeMaxBitRate,
      useZipDownload: useZipDownload ?? this.useZipDownload,
      customFilenameTemplate:
          customFilenameTemplate ?? this.customFilenameTemplate,
      customFolderTemplate: customFolderTemplate ?? this.customFolderTemplate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (devicePath.present) {
      map['device_path'] = Variable<String>(devicePath.value);
    }
    if (musicRootFolder.present) {
      map['music_root_folder'] = Variable<String>(musicRootFolder.value);
    }
    if (playlistFolder.present) {
      map['playlist_folder'] = Variable<String>(playlistFolder.value);
    }
    if (folderStructure.present) {
      map['folder_structure'] = Variable<String>(folderStructure.value);
    }
    if (filenameFormat.present) {
      map['filename_format'] = Variable<String>(filenameFormat.value);
    }
    if (includeYear.present) {
      map['include_year'] = Variable<bool>(includeYear.value);
    }
    if (overwriteExisting.present) {
      map['overwrite_existing'] = Variable<bool>(overwriteExisting.value);
    }
    if (transcodeFormat.present) {
      map['transcode_format'] = Variable<String>(transcodeFormat.value);
    }
    if (transcodeMaxBitRate.present) {
      map['transcode_max_bit_rate'] = Variable<int>(transcodeMaxBitRate.value);
    }
    if (useZipDownload.present) {
      map['use_zip_download'] = Variable<bool>(useZipDownload.value);
    }
    if (customFilenameTemplate.present) {
      map['custom_filename_template'] = Variable<String>(
        customFilenameTemplate.value,
      );
    }
    if (customFolderTemplate.present) {
      map['custom_folder_template'] = Variable<String>(
        customFolderTemplate.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceSettingsTableCompanion(')
          ..write('devicePath: $devicePath, ')
          ..write('musicRootFolder: $musicRootFolder, ')
          ..write('playlistFolder: $playlistFolder, ')
          ..write('folderStructure: $folderStructure, ')
          ..write('filenameFormat: $filenameFormat, ')
          ..write('includeYear: $includeYear, ')
          ..write('overwriteExisting: $overwriteExisting, ')
          ..write('transcodeFormat: $transcodeFormat, ')
          ..write('transcodeMaxBitRate: $transcodeMaxBitRate, ')
          ..write('useZipDownload: $useZipDownload, ')
          ..write('customFilenameTemplate: $customFilenameTemplate, ')
          ..write('customFolderTemplate: $customFolderTemplate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ArtistsTableTable artistsTable = $ArtistsTableTable(this);
  late final $AlbumsTableTable albumsTable = $AlbumsTableTable(this);
  late final $SongsTableTable songsTable = $SongsTableTable(this);
  late final $DeviceSettingsTableTable deviceSettingsTable =
      $DeviceSettingsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    artistsTable,
    albumsTable,
    songsTable,
    deviceSettingsTable,
  ];
}

typedef $$ArtistsTableTableCreateCompanionBuilder =
    ArtistsTableCompanion Function({
      required String id,
      required String name,
      Value<String?> coverArtId,
      Value<int> albumCount,
      Value<int> rowid,
    });
typedef $$ArtistsTableTableUpdateCompanionBuilder =
    ArtistsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> coverArtId,
      Value<int> albumCount,
      Value<int> rowid,
    });

class $$ArtistsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ArtistsTableTable> {
  $$ArtistsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get albumCount => $composableBuilder(
    column: $table.albumCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArtistsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ArtistsTableTable> {
  $$ArtistsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get albumCount => $composableBuilder(
    column: $table.albumCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArtistsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArtistsTableTable> {
  $$ArtistsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get albumCount => $composableBuilder(
    column: $table.albumCount,
    builder: (column) => column,
  );
}

class $$ArtistsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArtistsTableTable,
          ArtistsTableData,
          $$ArtistsTableTableFilterComposer,
          $$ArtistsTableTableOrderingComposer,
          $$ArtistsTableTableAnnotationComposer,
          $$ArtistsTableTableCreateCompanionBuilder,
          $$ArtistsTableTableUpdateCompanionBuilder,
          (
            ArtistsTableData,
            BaseReferences<_$AppDatabase, $ArtistsTableTable, ArtistsTableData>,
          ),
          ArtistsTableData,
          PrefetchHooks Function()
        > {
  $$ArtistsTableTableTableManager(_$AppDatabase db, $ArtistsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtistsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtistsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtistsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> coverArtId = const Value.absent(),
                Value<int> albumCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArtistsTableCompanion(
                id: id,
                name: name,
                coverArtId: coverArtId,
                albumCount: albumCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> coverArtId = const Value.absent(),
                Value<int> albumCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArtistsTableCompanion.insert(
                id: id,
                name: name,
                coverArtId: coverArtId,
                albumCount: albumCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArtistsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArtistsTableTable,
      ArtistsTableData,
      $$ArtistsTableTableFilterComposer,
      $$ArtistsTableTableOrderingComposer,
      $$ArtistsTableTableAnnotationComposer,
      $$ArtistsTableTableCreateCompanionBuilder,
      $$ArtistsTableTableUpdateCompanionBuilder,
      (
        ArtistsTableData,
        BaseReferences<_$AppDatabase, $ArtistsTableTable, ArtistsTableData>,
      ),
      ArtistsTableData,
      PrefetchHooks Function()
    >;
typedef $$AlbumsTableTableCreateCompanionBuilder =
    AlbumsTableCompanion Function({
      required String id,
      required String name,
      Value<String?> artistId,
      Value<String?> artist,
      Value<String?> coverArtId,
      Value<int?> year,
      Value<String?> genre,
      Value<int> songCount,
      Value<int> duration,
      Value<int> rowid,
    });
typedef $$AlbumsTableTableUpdateCompanionBuilder =
    AlbumsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> artistId,
      Value<String?> artist,
      Value<String?> coverArtId,
      Value<int?> year,
      Value<String?> genre,
      Value<int> songCount,
      Value<int> duration,
      Value<int> rowid,
    });

class $$AlbumsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTableTable> {
  $$AlbumsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get songCount => $composableBuilder(
    column: $table.songCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlbumsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTableTable> {
  $$AlbumsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get songCount => $composableBuilder(
    column: $table.songCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTableTable> {
  $$AlbumsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get songCount =>
      $composableBuilder(column: $table.songCount, builder: (column) => column);

  GeneratedColumn<int> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);
}

class $$AlbumsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlbumsTableTable,
          AlbumsTableData,
          $$AlbumsTableTableFilterComposer,
          $$AlbumsTableTableOrderingComposer,
          $$AlbumsTableTableAnnotationComposer,
          $$AlbumsTableTableCreateCompanionBuilder,
          $$AlbumsTableTableUpdateCompanionBuilder,
          (
            AlbumsTableData,
            BaseReferences<_$AppDatabase, $AlbumsTableTable, AlbumsTableData>,
          ),
          AlbumsTableData,
          PrefetchHooks Function()
        > {
  $$AlbumsTableTableTableManager(_$AppDatabase db, $AlbumsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> artistId = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> coverArtId = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int> songCount = const Value.absent(),
                Value<int> duration = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumsTableCompanion(
                id: id,
                name: name,
                artistId: artistId,
                artist: artist,
                coverArtId: coverArtId,
                year: year,
                genre: genre,
                songCount: songCount,
                duration: duration,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> artistId = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> coverArtId = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int> songCount = const Value.absent(),
                Value<int> duration = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumsTableCompanion.insert(
                id: id,
                name: name,
                artistId: artistId,
                artist: artist,
                coverArtId: coverArtId,
                year: year,
                genre: genre,
                songCount: songCount,
                duration: duration,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlbumsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlbumsTableTable,
      AlbumsTableData,
      $$AlbumsTableTableFilterComposer,
      $$AlbumsTableTableOrderingComposer,
      $$AlbumsTableTableAnnotationComposer,
      $$AlbumsTableTableCreateCompanionBuilder,
      $$AlbumsTableTableUpdateCompanionBuilder,
      (
        AlbumsTableData,
        BaseReferences<_$AppDatabase, $AlbumsTableTable, AlbumsTableData>,
      ),
      AlbumsTableData,
      PrefetchHooks Function()
    >;
typedef $$SongsTableTableCreateCompanionBuilder =
    SongsTableCompanion Function({
      required String id,
      required String title,
      Value<String?> albumId,
      Value<String?> artistId,
      Value<String?> album,
      Value<String?> artist,
      Value<int?> duration,
      Value<int?> bitRate,
      Value<String?> contentType,
      Value<String?> suffix,
      Value<int?> size,
      Value<String?> coverArtId,
      Value<int?> track,
      Value<int?> discNumber,
      Value<int?> year,
      Value<String?> genre,
      Value<int> rowid,
    });
typedef $$SongsTableTableUpdateCompanionBuilder =
    SongsTableCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> albumId,
      Value<String?> artistId,
      Value<String?> album,
      Value<String?> artist,
      Value<int?> duration,
      Value<int?> bitRate,
      Value<String?> contentType,
      Value<String?> suffix,
      Value<int?> size,
      Value<String?> coverArtId,
      Value<int?> track,
      Value<int?> discNumber,
      Value<int?> year,
      Value<String?> genre,
      Value<int> rowid,
    });

class $$SongsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SongsTableTable> {
  $$SongsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bitRate => $composableBuilder(
    column: $table.bitRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suffix => $composableBuilder(
    column: $table.suffix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get track => $composableBuilder(
    column: $table.track,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SongsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SongsTableTable> {
  $$SongsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bitRate => $composableBuilder(
    column: $table.bitRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suffix => $composableBuilder(
    column: $table.suffix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get track => $composableBuilder(
    column: $table.track,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongsTableTable> {
  $$SongsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<int> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);

  GeneratedColumn<int> get bitRate =>
      $composableBuilder(column: $table.bitRate, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get suffix =>
      $composableBuilder(column: $table.suffix, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get coverArtId => $composableBuilder(
    column: $table.coverArtId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get track =>
      $composableBuilder(column: $table.track, builder: (column) => column);

  GeneratedColumn<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);
}

class $$SongsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongsTableTable,
          SongsTableData,
          $$SongsTableTableFilterComposer,
          $$SongsTableTableOrderingComposer,
          $$SongsTableTableAnnotationComposer,
          $$SongsTableTableCreateCompanionBuilder,
          $$SongsTableTableUpdateCompanionBuilder,
          (
            SongsTableData,
            BaseReferences<_$AppDatabase, $SongsTableTable, SongsTableData>,
          ),
          SongsTableData,
          PrefetchHooks Function()
        > {
  $$SongsTableTableTableManager(_$AppDatabase db, $SongsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<String?> artistId = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<int?> duration = const Value.absent(),
                Value<int?> bitRate = const Value.absent(),
                Value<String?> contentType = const Value.absent(),
                Value<String?> suffix = const Value.absent(),
                Value<int?> size = const Value.absent(),
                Value<String?> coverArtId = const Value.absent(),
                Value<int?> track = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsTableCompanion(
                id: id,
                title: title,
                albumId: albumId,
                artistId: artistId,
                album: album,
                artist: artist,
                duration: duration,
                bitRate: bitRate,
                contentType: contentType,
                suffix: suffix,
                size: size,
                coverArtId: coverArtId,
                track: track,
                discNumber: discNumber,
                year: year,
                genre: genre,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> albumId = const Value.absent(),
                Value<String?> artistId = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<int?> duration = const Value.absent(),
                Value<int?> bitRate = const Value.absent(),
                Value<String?> contentType = const Value.absent(),
                Value<String?> suffix = const Value.absent(),
                Value<int?> size = const Value.absent(),
                Value<String?> coverArtId = const Value.absent(),
                Value<int?> track = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SongsTableCompanion.insert(
                id: id,
                title: title,
                albumId: albumId,
                artistId: artistId,
                album: album,
                artist: artist,
                duration: duration,
                bitRate: bitRate,
                contentType: contentType,
                suffix: suffix,
                size: size,
                coverArtId: coverArtId,
                track: track,
                discNumber: discNumber,
                year: year,
                genre: genre,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SongsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongsTableTable,
      SongsTableData,
      $$SongsTableTableFilterComposer,
      $$SongsTableTableOrderingComposer,
      $$SongsTableTableAnnotationComposer,
      $$SongsTableTableCreateCompanionBuilder,
      $$SongsTableTableUpdateCompanionBuilder,
      (
        SongsTableData,
        BaseReferences<_$AppDatabase, $SongsTableTable, SongsTableData>,
      ),
      SongsTableData,
      PrefetchHooks Function()
    >;
typedef $$DeviceSettingsTableTableCreateCompanionBuilder =
    DeviceSettingsTableCompanion Function({
      required String devicePath,
      Value<String> musicRootFolder,
      Value<String> playlistFolder,
      Value<String> folderStructure,
      Value<String> filenameFormat,
      Value<bool> includeYear,
      Value<bool> overwriteExisting,
      Value<String> transcodeFormat,
      Value<int?> transcodeMaxBitRate,
      Value<bool> useZipDownload,
      Value<String> customFilenameTemplate,
      Value<String> customFolderTemplate,
      Value<int> rowid,
    });
typedef $$DeviceSettingsTableTableUpdateCompanionBuilder =
    DeviceSettingsTableCompanion Function({
      Value<String> devicePath,
      Value<String> musicRootFolder,
      Value<String> playlistFolder,
      Value<String> folderStructure,
      Value<String> filenameFormat,
      Value<bool> includeYear,
      Value<bool> overwriteExisting,
      Value<String> transcodeFormat,
      Value<int?> transcodeMaxBitRate,
      Value<bool> useZipDownload,
      Value<String> customFilenameTemplate,
      Value<String> customFolderTemplate,
      Value<int> rowid,
    });

class $$DeviceSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $DeviceSettingsTableTable> {
  $$DeviceSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get devicePath => $composableBuilder(
    column: $table.devicePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get musicRootFolder => $composableBuilder(
    column: $table.musicRootFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistFolder => $composableBuilder(
    column: $table.playlistFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderStructure => $composableBuilder(
    column: $table.folderStructure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filenameFormat => $composableBuilder(
    column: $table.filenameFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includeYear => $composableBuilder(
    column: $table.includeYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get overwriteExisting => $composableBuilder(
    column: $table.overwriteExisting,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transcodeFormat => $composableBuilder(
    column: $table.transcodeFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transcodeMaxBitRate => $composableBuilder(
    column: $table.transcodeMaxBitRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get useZipDownload => $composableBuilder(
    column: $table.useZipDownload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customFilenameTemplate => $composableBuilder(
    column: $table.customFilenameTemplate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customFolderTemplate => $composableBuilder(
    column: $table.customFolderTemplate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeviceSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DeviceSettingsTableTable> {
  $$DeviceSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get devicePath => $composableBuilder(
    column: $table.devicePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get musicRootFolder => $composableBuilder(
    column: $table.musicRootFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistFolder => $composableBuilder(
    column: $table.playlistFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderStructure => $composableBuilder(
    column: $table.folderStructure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filenameFormat => $composableBuilder(
    column: $table.filenameFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includeYear => $composableBuilder(
    column: $table.includeYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get overwriteExisting => $composableBuilder(
    column: $table.overwriteExisting,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transcodeFormat => $composableBuilder(
    column: $table.transcodeFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transcodeMaxBitRate => $composableBuilder(
    column: $table.transcodeMaxBitRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get useZipDownload => $composableBuilder(
    column: $table.useZipDownload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customFilenameTemplate => $composableBuilder(
    column: $table.customFilenameTemplate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customFolderTemplate => $composableBuilder(
    column: $table.customFolderTemplate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeviceSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeviceSettingsTableTable> {
  $$DeviceSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get devicePath => $composableBuilder(
    column: $table.devicePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get musicRootFolder => $composableBuilder(
    column: $table.musicRootFolder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playlistFolder => $composableBuilder(
    column: $table.playlistFolder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get folderStructure => $composableBuilder(
    column: $table.folderStructure,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filenameFormat => $composableBuilder(
    column: $table.filenameFormat,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get includeYear => $composableBuilder(
    column: $table.includeYear,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get overwriteExisting => $composableBuilder(
    column: $table.overwriteExisting,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transcodeFormat => $composableBuilder(
    column: $table.transcodeFormat,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transcodeMaxBitRate => $composableBuilder(
    column: $table.transcodeMaxBitRate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get useZipDownload => $composableBuilder(
    column: $table.useZipDownload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customFilenameTemplate => $composableBuilder(
    column: $table.customFilenameTemplate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customFolderTemplate => $composableBuilder(
    column: $table.customFolderTemplate,
    builder: (column) => column,
  );
}

class $$DeviceSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeviceSettingsTableTable,
          DeviceSettingsTableData,
          $$DeviceSettingsTableTableFilterComposer,
          $$DeviceSettingsTableTableOrderingComposer,
          $$DeviceSettingsTableTableAnnotationComposer,
          $$DeviceSettingsTableTableCreateCompanionBuilder,
          $$DeviceSettingsTableTableUpdateCompanionBuilder,
          (
            DeviceSettingsTableData,
            BaseReferences<
              _$AppDatabase,
              $DeviceSettingsTableTable,
              DeviceSettingsTableData
            >,
          ),
          DeviceSettingsTableData,
          PrefetchHooks Function()
        > {
  $$DeviceSettingsTableTableTableManager(
    _$AppDatabase db,
    $DeviceSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DeviceSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> devicePath = const Value.absent(),
                Value<String> musicRootFolder = const Value.absent(),
                Value<String> playlistFolder = const Value.absent(),
                Value<String> folderStructure = const Value.absent(),
                Value<String> filenameFormat = const Value.absent(),
                Value<bool> includeYear = const Value.absent(),
                Value<bool> overwriteExisting = const Value.absent(),
                Value<String> transcodeFormat = const Value.absent(),
                Value<int?> transcodeMaxBitRate = const Value.absent(),
                Value<bool> useZipDownload = const Value.absent(),
                Value<String> customFilenameTemplate = const Value.absent(),
                Value<String> customFolderTemplate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceSettingsTableCompanion(
                devicePath: devicePath,
                musicRootFolder: musicRootFolder,
                playlistFolder: playlistFolder,
                folderStructure: folderStructure,
                filenameFormat: filenameFormat,
                includeYear: includeYear,
                overwriteExisting: overwriteExisting,
                transcodeFormat: transcodeFormat,
                transcodeMaxBitRate: transcodeMaxBitRate,
                useZipDownload: useZipDownload,
                customFilenameTemplate: customFilenameTemplate,
                customFolderTemplate: customFolderTemplate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String devicePath,
                Value<String> musicRootFolder = const Value.absent(),
                Value<String> playlistFolder = const Value.absent(),
                Value<String> folderStructure = const Value.absent(),
                Value<String> filenameFormat = const Value.absent(),
                Value<bool> includeYear = const Value.absent(),
                Value<bool> overwriteExisting = const Value.absent(),
                Value<String> transcodeFormat = const Value.absent(),
                Value<int?> transcodeMaxBitRate = const Value.absent(),
                Value<bool> useZipDownload = const Value.absent(),
                Value<String> customFilenameTemplate = const Value.absent(),
                Value<String> customFolderTemplate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceSettingsTableCompanion.insert(
                devicePath: devicePath,
                musicRootFolder: musicRootFolder,
                playlistFolder: playlistFolder,
                folderStructure: folderStructure,
                filenameFormat: filenameFormat,
                includeYear: includeYear,
                overwriteExisting: overwriteExisting,
                transcodeFormat: transcodeFormat,
                transcodeMaxBitRate: transcodeMaxBitRate,
                useZipDownload: useZipDownload,
                customFilenameTemplate: customFilenameTemplate,
                customFolderTemplate: customFolderTemplate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeviceSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeviceSettingsTableTable,
      DeviceSettingsTableData,
      $$DeviceSettingsTableTableFilterComposer,
      $$DeviceSettingsTableTableOrderingComposer,
      $$DeviceSettingsTableTableAnnotationComposer,
      $$DeviceSettingsTableTableCreateCompanionBuilder,
      $$DeviceSettingsTableTableUpdateCompanionBuilder,
      (
        DeviceSettingsTableData,
        BaseReferences<
          _$AppDatabase,
          $DeviceSettingsTableTable,
          DeviceSettingsTableData
        >,
      ),
      DeviceSettingsTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ArtistsTableTableTableManager get artistsTable =>
      $$ArtistsTableTableTableManager(_db, _db.artistsTable);
  $$AlbumsTableTableTableManager get albumsTable =>
      $$AlbumsTableTableTableManager(_db, _db.albumsTable);
  $$SongsTableTableTableManager get songsTable =>
      $$SongsTableTableTableManager(_db, _db.songsTable);
  $$DeviceSettingsTableTableTableManager get deviceSettingsTable =>
      $$DeviceSettingsTableTableTableManager(_db, _db.deviceSettingsTable);
}
