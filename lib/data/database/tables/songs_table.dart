import 'package:drift/drift.dart';

class SongsTable extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get albumId => text().nullable()();
  TextColumn get artistId => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get artist => text().nullable()();
  IntColumn get duration => integer().nullable()();
  IntColumn get bitRate => integer().nullable()();
  TextColumn get contentType => text().nullable()();
  TextColumn get suffix => text().nullable()();
  IntColumn get size => integer().nullable()();
  TextColumn get coverArtId => text().nullable()();
  IntColumn get track => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get genre => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
