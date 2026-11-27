import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:md_scanner/shared/repositories/sqlite_document_repository.dart';
import 'package:md_scanner/shared/repositories/sqlite_ocr_text_repository.dart';

/// The SQLite library, built on the app database and storage.
final sqliteDocumentRepositoryProvider = Provider<SqliteDocumentRepository>((
  ref,
) {
  final repository = SqliteDocumentRepository(
    db: ref.watch(databaseProvider),
    storage: ref.watch(fileStorageProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Saving OCR text changes what a search returns, hence the link to the
/// document repository's change stream.
final sqliteOcrTextRepositoryProvider = Provider<SqliteOcrTextRepository>(
  (ref) => SqliteOcrTextRepository(
    db: ref.watch(databaseProvider),
    onChanged: ref.watch(sqliteDocumentRepositoryProvider).notifyChanged,
  ),
);

/// Binds the repository contracts to SQLite. Spread into the overrides of the
/// root `ProviderScope`, next to the database and storage overrides.
final List<Override> libraryRepositoryOverrides = [
  documentRepositoryProvider.overrideWith(
    (ref) => ref.watch(sqliteDocumentRepositoryProvider),
  ),
  ocrTextRepositoryProvider.overrideWith(
    (ref) => ref.watch(sqliteOcrTextRepositoryProvider),
  ),
];

/// A typed failure is an answer, not an incident: Riverpod's automatic retry
/// would only keep the screen on its loading state before showing it.
Duration? _noRetry(int retryCount, Object error) => null;

/// Returns the repository and re-runs the calling provider after each of its
/// changes, so every list stays current without manual invalidation.
DocumentRepository _watchLibrary(Ref ref) {
  final repository = ref.watch(documentRepositoryProvider);
  final subscription = repository.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return repository;
}

/// Screens turn the thrown [FailureException] into a message with
/// `failureOf(error)`.
T _unwrap<T>(Result<T> result) => switch (result) {
  Success<T>(:final value) => value,
  Err<T>(:final failure) => throw FailureException(failure),
};

/// Documents matching a [DocumentQuery].
final documentListProvider = FutureProvider.autoDispose
    .family<List<DocumentEntity>, DocumentQuery>(
      (ref, query) async => _unwrap(await _watchLibrary(ref).query(query)),
      retry: _noRetry,
    );

/// One document, whatever its state (live, trashed, in the vault). Fails with
/// `StorageFailure(notFound)` once it has been deleted permanently.
final documentByIdProvider = FutureProvider.autoDispose
    .family<DocumentEntity, String>(
      (ref, id) async => _unwrap(await _watchLibrary(ref).getById(id)),
      retry: _noRetry,
    );

/// Sub-folders of a parent folder id; `null` lists the root folders.
final folderListProvider = FutureProvider.autoDispose
    .family<List<FolderEntity>, String?>(
      (ref, parentId) async =>
          _unwrap(await _watchLibrary(ref).folders(parentId: parentId)),
      retry: _noRetry,
    );

final allTagsProvider = FutureProvider.autoDispose<List<TagEntity>>(
  (ref) async => _unwrap(await _watchLibrary(ref).allTags()),
  retry: _noRetry,
);

/// Tags of one document, keyed by its id.
final documentTagsProvider = FutureProvider.autoDispose
    .family<List<TagEntity>, String>(
      (ref, documentId) async =>
          _unwrap(await _watchLibrary(ref).tagsOf(documentId)),
      retry: _noRetry,
    );

/// Number and size of a set of documents, as recorded in the library.
class DocumentTotals extends Equatable {
  const DocumentTotals({required this.count, required this.bytes});

  factory DocumentTotals.of(Iterable<DocumentEntity> documents) {
    var count = 0;
    var bytes = 0;
    for (final document in documents) {
      count++;
      bytes += document.fileSize;
    }
    return DocumentTotals(count: count, bytes: bytes);
  }

  final int count;
  final int bytes;

  @override
  List<Object?> get props => [count, bytes];
}

/// What the app stores on the device, for the storage screen.
class StorageUsage extends Equatable {
  const StorageUsage({
    required this.bytesByArea,
    required this.library,
    required this.trash,
    required this.vault,
  });

  /// Bytes measured on disk for each storage area.
  final Map<StorageArea, int> bytesByArea;

  /// Live documents outside the vault.
  final DocumentTotals library;

  /// Everything emptying the trash would delete.
  final DocumentTotals trash;

  /// Live documents of the vault.
  final DocumentTotals vault;

  int bytesOf(StorageArea area) => bytesByArea[area] ?? 0;

  int get totalBytes =>
      bytesByArea.values.fold(0, (total, bytes) => total + bytes);

  /// Working files that can be cleared without losing a document.
  int get reclaimableBytes =>
      bytesOf(StorageArea.temp) + bytesOf(StorageArea.exports);

  @override
  List<Object?> get props => [bytesByArea, library, trash, vault];
}

final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((
  ref,
) async {
  final repository = _watchLibrary(ref);
  final storage = ref.watch(fileStorageProvider);
  Future<List<DocumentEntity>> list(DocumentQuery query) async =>
      _unwrap(await repository.query(query));

  final library = await list(const DocumentQuery());
  final vault = await list(const DocumentQuery(inVault: true));
  final trash = [
    ...await list(const DocumentQuery(inTrash: true)),
    ...await list(const DocumentQuery(inTrash: true, inVault: true)),
  ];
  final bytesByArea = _unwrap(
    await guard(() async {
      return {
        for (final area in StorageArea.values)
          area: await storage.usedBytes(area),
      };
    }),
  );
  return StorageUsage(
    bytesByArea: bytesByArea,
    library: DocumentTotals.of(library),
    trash: DocumentTotals.of(trash),
    vault: DocumentTotals.of(vault),
  );
}, retry: _noRetry);
