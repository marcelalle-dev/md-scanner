import 'dart:io';

import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a fresh in-memory database with the production schema.
///
/// ```dart
/// late AppDatabase database;
/// setUp(() async => database = await openTestDatabase());
/// tearDown(() => database.close());
/// ```
Future<AppDatabase> openTestDatabase() {
  sqfliteFfiInit();
  return AppDatabase.open(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
}

/// Creates a [FileStorage] rooted in a new temporary directory.
/// Delete `storage.root` in `tearDown`.
Future<FileStorage> createTestStorage() async {
  final directory = await Directory.systemTemp.createTemp('md_scanner_test_');
  final storage = FileStorage(directory);
  await storage.ensureReady();
  return storage;
}
