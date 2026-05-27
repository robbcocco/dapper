import 'package:drift/drift.dart';

class AlbumsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get artistId => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get coverArtId => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get songCount => integer().withDefault(const Constant(0))();
  IntColumn get duration => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
