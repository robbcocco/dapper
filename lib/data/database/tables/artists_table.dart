import 'package:drift/drift.dart';

class ArtistsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get coverArtId => text().nullable()();
  IntColumn get albumCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
