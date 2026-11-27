import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:sqflite/sqflite.dart';

/// Key-value preferences persisted in the `app_settings` table.
///
/// Not for secrets: PIN hashes and encryption keys go through the secure
/// key store, never through this table.
///
/// Each feature owns its keys and prefixes them with its name
/// (`scanner.default_mode`, `security.auto_lock_seconds`).
class SettingsStore {
  SettingsStore(this._db);

  final Database _db;

  static const String _table = 'app_settings';

  Future<String?> read(String key) async {
    final rows = await _db.query(
      _table,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<Map<String, String>> readAll() async {
    final rows = await _db.query(_table);
    return {
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
  }

  Future<void> write(String key, String value) async {
    await _db.insert(_table, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String key) async {
    await _db.delete(_table, where: 'key = ?', whereArgs: [key]);
  }

  Future<void> clear() async {
    await _db.delete(_table);
  }

  Future<bool> readBool(String key, {bool defaultValue = false}) async {
    final value = await read(key);
    return value == null ? defaultValue : value == 'true';
  }

  Future<void> writeBool(String key, {required bool value}) =>
      write(key, value.toString());

  Future<int?> readInt(String key) async {
    final value = await read(key);
    return value == null ? null : int.tryParse(value);
  }

  Future<void> writeInt(String key, int value) => write(key, value.toString());
}

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(databaseProvider)),
);
