import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/sqlite_document_repository.dart';
import 'package:md_scanner/shared/repositories/sqlite_ocr_text_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

/// A real SQLite library on a temporary storage, with a clock that advances
/// by one minute at every reading so that dates are distinct and ordered.
class LibraryHarness {
  LibraryHarness._(this.database, this.storage, [this._databaseFolder]) {
    repository = SqliteDocumentRepository(
      db: database.db,
      storage: storage,
      clock: tick,
    );
    ocr = SqliteOcrTextRepository(
      db: database.db,
      clock: tick,
      onChanged: repository.notifyChanged,
    );
  }

  /// In-memory databases opened by `openTestDatabase` are one and the same
  /// within a test: a second library ("another device") needs [ownDatabase],
  /// which opens the production schema in a file of its own.
  static Future<LibraryHarness> create({bool ownDatabase = false}) async {
    if (!ownDatabase) {
      return LibraryHarness._(
        await openTestDatabase(),
        await createTestStorage(),
      );
    }
    sqfliteFfiInit();
    final folder = await Directory.systemTemp.createTemp('md_scanner_db_');
    final database = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: p.join(folder.path, kDatabaseFileName),
    );
    return LibraryHarness._(database, await createTestStorage(), folder);
  }

  final Directory? _databaseFolder;

  final AppDatabase database;
  final FileStorage storage;
  late final SqliteDocumentRepository repository;
  late final SqliteOcrTextRepository ocr;

  DateTime now = DateTime.utc(2026, 1, 1, 8);

  Database get db => database.db;

  DateTime tick() => now = now.add(const Duration(minutes: 1));

  Future<void> dispose() async {
    await repository.dispose();
    await database.close();
    await _databaseFolder?.delete(recursive: true);
    if (await storage.root.exists()) {
      await storage.root.delete(recursive: true);
    }
  }

  /// Writes [size] bytes in [area]; [seed] makes the content recognizable.
  Future<String> writeFile(
    StorageArea area, {
    String extension = 'pdf',
    int size = 12,
    int seed = 7,
    String? group,
  }) => storage.writeBytes(
    area,
    Uint8List.fromList(List.generate(size, (index) => (seed + index) % 251)),
    extension: extension,
    group: group,
  );

  /// Registers a document backed by real files.
  Future<DocumentEntity> addDocument(
    String name, {
    DocumentFileType type = DocumentFileType.pdf,
    int size = 12,
    String? folderId,
    int pages = 0,
    bool thumbnail = false,
    DocumentSource source = DocumentSource.scan,
  }) async {
    final draft = NewDocument(
      name: name,
      filePath: await writeFile(
        StorageArea.documents,
        extension: type.extension,
        size: size,
      ),
      fileType: type,
      source: source,
      folderId: folderId,
      thumbnailPath: thumbnail
          ? await writeFile(StorageArea.thumbnails, extension: 'jpg', size: 5)
          : null,
      pageImagePaths: [
        for (var index = 0; index < pages; index++)
          await writeFile(
            StorageArea.pages,
            extension: 'jpg',
            size: 20 + index,
            group: 'scan',
          ),
      ],
    );
    return valueOf(await repository.register(draft));
  }

  /// Moves a document into the vault the way the vault feature would.
  Future<DocumentEntity> moveToVault(DocumentEntity document) async {
    final encrypted = await writeFile(
      StorageArea.vault,
      extension: 'enc',
      size: 40,
    );
    final updated = valueOf(
      await repository.updateVaultState(
        document.id,
        filePath: encrypted,
        isInVault: true,
        isEncrypted: true,
      ),
    );
    await storage.delete(document.filePath);
    return updated;
  }

  Future<List<String>> names(DocumentQuery query) async => [
    for (final document in valueOf(await repository.query(query)))
      document.name,
  ];

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
    return rows.first['total']! as int;
  }

  /// Relative paths of every file currently stored in [area].
  Future<Set<String>> filesIn(StorageArea area) async => {
    await for (final entity in storage.directoryOf(area).list(recursive: true))
      if (entity is File) storage.relativePath(entity.path),
  };
}

/// Unwraps a success or fails the test with the failure.
T valueOf<T>(Result<T> result) => switch (result) {
  Success<T>(:final value) => value,
  Err<T>(:final failure) => fail('expected a success, got $failure'),
};

Failure failureIn<T>(Result<T> result) => switch (result) {
  Success<T>(:final value) => fail('expected a failure, got $value'),
  Err<T>(:final failure) => failure,
};

const Matcher isNotFound = _StorageKind(StorageFailureKind.notFound);
const Matcher isAlreadyExists = _StorageKind(StorageFailureKind.alreadyExists);

/// Matches an `Err` carrying a [StorageFailure] of a given kind.
class _StorageKind extends Matcher {
  const _StorageKind(this.kind);

  final StorageFailureKind kind;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    if (item is! Result<Object?>) return false;
    final failure = item.failureOrNull;
    return failure is StorageFailure && failure.kind == kind;
  }

  @override
  Description describe(Description description) =>
      description.add('Err(StorageFailure(${kind.name}))');
}

/// Matches an `Err` carrying a [ValidationFailure] with [code].
Matcher isValidationError(String code) => isA<Result<Object?>>().having(
  (result) => result.failureOrNull,
  'failure',
  ValidationFailure(code),
);
