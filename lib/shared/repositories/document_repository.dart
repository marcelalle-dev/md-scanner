import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/shared/models/document_entity.dart';

/// Persistent document library: metadata in SQLite, bytes in FileStorage.
///
/// Every feature that produces a file (scanner, PDF tools, OCR export, ID
/// scanner, generators) registers it here so it shows up in the library.
abstract interface class DocumentRepository {
  /// Emits after every successful mutation so open lists can reload.
  Stream<void> get changes;

  Future<Result<List<DocumentEntity>>> query(DocumentQuery query);

  Future<Result<DocumentEntity>> getById(String id);

  /// Registers a file already stored inside FileStorage. Size is measured
  /// from disk; fails with `StorageFailure(notFound)` if the file is missing.
  Future<Result<DocumentEntity>> register(NewDocument draft);

  /// Copies an external file into the `documents` area, then registers it.
  /// Fails with `ImageFailure`/`StorageFailure` for unsupported extensions.
  Future<Result<DocumentEntity>> importExternalFile(
    String absolutePath, {
    String? name,
    String? folderId,
    DocumentSource source = DocumentSource.import,
  });

  Future<Result<DocumentEntity>> rename(String id, String newName);

  /// Points the document at a new file (after an edit). The previous file is
  /// deleted from storage once the database is updated.
  Future<Result<DocumentEntity>> replaceFile(
    String id, {
    required String newFilePath,
    required DocumentFileType fileType,
    int? pageCount,
    String? thumbnailPath,
  });

  /// [folderId] null moves the documents back to the root.
  Future<Result<void>> moveToFolder(List<String> ids, String? folderId);

  Future<Result<void>> setFavorite(String id, {required bool favorite});

  Future<Result<void>> moveToTrash(List<String> ids);

  Future<Result<void>> restoreFromTrash(List<String> ids);

  /// Deletes database rows AND files (document, pages, thumbnail).
  Future<Result<void>> deletePermanently(List<String> ids);

  Future<Result<void>> emptyTrash();

  /// Records the result of moving a document in or out of the vault.
  Future<Result<DocumentEntity>> updateVaultState(
    String id, {
    required String filePath,
    required bool isInVault,
    required bool isEncrypted,
  });

  Future<Result<List<DocumentPage>>> pagesOf(String documentId);

  Future<Result<List<FolderEntity>>> folders({String? parentId});

  Future<Result<FolderEntity>> getFolder(String id);

  Future<Result<FolderEntity>> createFolder(String name, {String? parentId});

  Future<Result<FolderEntity>> renameFolder(String id, String newName);

  /// Deletes the folder and its sub-folders; contained documents move to the
  /// root (they are never deleted implicitly).
  Future<Result<void>> deleteFolder(String id);

  Future<Result<List<TagEntity>>> allTags();

  Future<Result<List<TagEntity>>> tagsOf(String documentId);

  /// Replaces the document's tags; unknown tag names are created.
  Future<Result<void>> setTags(String documentId, List<String> tagNames);

  /// Deletes every document, folder, tag and file. Used by "erase my data".
  Future<Result<void>> wipeAll();
}

/// Text extracted by OCR, saved per document so the library can search it.
abstract interface class OcrTextRepository {
  Future<Result<void>> save({
    required String documentId,
    required String text,
    String? language,
    int? pageIndex,
  });

  /// Concatenated text of the document, pages in order. Null if none saved.
  Future<Result<String?>> textOf(String documentId);

  Future<Result<void>> deleteFor(String documentId);
}

/// Bound to the SQLite implementations in `shared/providers/repositories.dart`.
final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => throw StateError('documentRepositoryProvider must be overridden'),
);

final ocrTextRepositoryProvider = Provider<OcrTextRepository>(
  (ref) => throw StateError('ocrTextRepositoryProvider must be overridden'),
);
