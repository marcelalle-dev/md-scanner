import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/storage/database/migrations.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const String kDatabaseFileName = 'md_scanner.db';

/// Opens the SQLite database that stores metadata only.
///
/// Document bytes live on the file system (see FileStorage); SQLite keeps
/// names, relative paths, relations and settings.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  /// [factory] and [path] are injectable so tests can use
  /// `databaseFactoryFfi` with `inMemoryDatabasePath`.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
    List<List<String>> migrations = kMigrations,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), kDatabaseFileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: migrations.length,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, migrations, 0, version),
        onUpgrade: (db, from, to) => _migrate(db, migrations, from, to),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _migrate(
    Database db,
    List<List<String>> migrations,
    int from,
    int to,
  ) async {
    for (var version = from; version < to; version++) {
      for (final statement in migrations[version]) {
        await db.execute(statement);
      }
    }
  }

  Future<void> close() => db.close();
}

/// Overridden in `bootstrap()` (and in tests) with an opened database.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('appDatabaseProvider must be overridden'),
);

final databaseProvider = Provider<Database>(
  (ref) => ref.watch(appDatabaseProvider).db,
);
