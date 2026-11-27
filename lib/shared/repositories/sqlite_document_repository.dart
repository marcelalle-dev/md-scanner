import 'dart:async';
import 'dart:io';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:md_scanner/shared/services/library/document_rows.dart';
import 'package:md_scanner/shared/services/library/folder_store.dart';
import 'package:md_scanner/shared/services/library/library_sql.dart';
import 'package:md_scanner/shared/services/library/tag_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// [DocumentRepository] backed by SQLite (metadata) and [FileStorage] (bytes).
///
/// Rules applied on top of the interface contract:
/// - names go through [sanitizeFileName]; `register`, `importExternalFile`
///   and `rename` append " (2)", " (3)"… when a live, non-vault document of
///   the same folder already carries the name;
/// - a stored file belongs to one document only: registering a path twice
///   fails with `StorageFailure(alreadyExists)`;
/// - operations on a list of ids are all-or-nothing;
/// - only `rename` and `replaceFile` move `updatedAt`, so trashing, moving or
///   starring a document does not reorder a "most recent" list.
class SqliteDocumentRepository implements DocumentRepository {
  SqliteDocumentRepository({
    required this._db,
    required this._storage,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now {
    _folders = FolderStore(db: _db, uuid: _uuid, now: _now);
    _tags = TagStore(db: _db, uuid: _uuid, now: _now);
  }

  static const Success<void> _done = Success<void>(null);

  final Database _db;
  final FileStorage _storage;
  final Uuid _uuid;
  final DateTime Function() _clock;
  late final FolderStore _folders;
  late final TagStore _tags;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  /// Announces a change made behind the repository's back (OCR text saved,
  /// backup restored) so that open lists reload.
  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();

  int _now() => _clock().toUtc().millisecondsSinceEpoch;

  Future<Result<T>> _read<T>(Future<T> Function() body) => guard(
    body,
    onError: (error, _) => libraryFailure(error, StorageFailureKind.readError),
  );

  Future<Result<T>> _write<T>(Future<T> Function() body) async {
    final result = await guard(
      body,
      onError: (error, _) =>
          libraryFailure(error, StorageFailureKind.writeError),
    );
    if (result.isSuccess) notifyChanged();
    return result;
  }

  @override
  Future<Result<List<DocumentEntity>>> query(DocumentQuery query) =>
      _read(() async {
        final statement = DocumentQuerySql.build(query);
        final rows = await _db.rawQuery(statement.sql, statement.args);
        return rows.map(documentFromRow).toList();
      });

  @override
  Future<Result<DocumentEntity>> getById(String id) =>
      _read(() => requireDocument(_db, id));

  @override
  Future<Result<DocumentEntity>> register(NewDocument draft) =>
      _write(() => _insert(draft));

  @override
  Future<Result<DocumentEntity>> importExternalFile(
    String absolutePath, {
    String? name,
    String? folderId,
    DocumentSource source = DocumentSource.import,
  }) => _write(() async {
    final type = DocumentFileType.fromExtension(p.extension(absolutePath));
    if (type == null) {
      throw const FailureException(ValidationFailure('unsupported_file_type'));
    }
    final origin = File(absolutePath);
    if (!await origin.exists()) throw kNotFound;
    final label = name == null || name.trim().isEmpty
        ? p.basenameWithoutExtension(absolutePath)
        : name;
    final relative = _storage.allocate(
      StorageArea.documents,
      extension: type.extension,
    );
    try {
      final target = _storage.file(relative);
      await target.parent.create(recursive: true);
      await origin.copy(target.path);
      return await _insert(
        NewDocument(
          name: label,
          filePath: relative,
          fileType: type,
          source: source,
          folderId: folderId,
        ),
      );
    } catch (_) {
      await _deleteFiles([relative]);
      rethrow;
    }
  });

  @override
  Future<Result<DocumentEntity>> rename(String id, String newName) =>
      _write(() async {
        final cleaned = sanitizeFileName(newName, fallback: '');
        if (cleaned.isEmpty) {
          throw const FailureException(ValidationFailure('empty_name'));
        }
        return _db.transaction((txn) async {
          final current = await requireDocument(txn, id);
          if (current.name == cleaned) return current;
          final name = current.isInTrash || current.isInVault
              ? cleaned
              : await uniqueDocumentName(
                  txn,
                  cleaned,
                  folderId: current.folderId,
                  excludingId: id,
                );
          await txn.update(
            'documents',
            {'name': name, 'updated_at': _now()},
            where: 'id = ?',
            whereArgs: [id],
          );
          return requireDocument(txn, id);
        });
      });

  @override
  Future<Result<DocumentEntity>> replaceFile(
    String id, {
    required String newFilePath,
    required DocumentFileType fileType,
    int? pageCount,
    String? thumbnailPath,
  }) => _write(() async {
    final size = await _requireFileSize(newFilePath);
    final (previous, updated) = await _db.transaction((txn) async {
      final previous = await requireDocument(txn, id);
      if (previous.filePath != newFilePath) {
        await requireUnusedFilePath(txn, newFilePath);
      }
      await txn.update(
        'documents',
        {
          'file_path': newFilePath,
          'file_type': fileType.extension,
          'file_size': size,
          'page_count': pageCount,
          'thumbnail_path': thumbnailPath,
          'updated_at': _now(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return (previous, await requireDocument(txn, id));
    });
    await _deleteFiles([
      if (previous.filePath != updated.filePath) previous.filePath,
      if (previous.thumbnailPath != updated.thumbnailPath)
        ?previous.thumbnailPath,
    ]);
    return updated;
  });

  @override
  Future<Result<void>> moveToFolder(List<String> ids, String? folderId) {
    final unique = ids.toSet();
    if (unique.isEmpty) return Future.value(_done);
    return _write(
      () => _db.transaction<void>((txn) async {
        if (folderId != null) await _folders.require(txn, folderId);
        await requireAllDocuments(txn, unique);
        await updateDocuments(txn, unique, 'folder_id = ?', [folderId]);
      }),
    );
  }

  @override
  Future<Result<void>> setFavorite(String id, {required bool favorite}) =>
      _write(
        () => _db.transaction<void>((txn) async {
          await requireDocument(txn, id);
          if (favorite) {
            await txn.insert('favorites', {
              'id': _uuid.v4(),
              'document_id': id,
              'created_at': _now(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            await txn.delete(
              'favorites',
              where: 'document_id = ?',
              whereArgs: [id],
            );
          }
        }),
      );

  @override
  Future<Result<void>> moveToTrash(List<String> ids) {
    final unique = ids.toSet();
    if (unique.isEmpty) return Future.value(_done);
    return _write(
      () => _db.transaction<void>((txn) async {
        await requireAllDocuments(txn, unique);
        // A document already in the trash keeps its original deletion date.
        await updateDocuments(
          txn,
          unique,
          'deleted_at = IFNULL(deleted_at, ?)',
          [_now()],
        );
      }),
    );
  }

  @override
  Future<Result<void>> restoreFromTrash(List<String> ids) {
    final unique = ids.toSet();
    if (unique.isEmpty) return Future.value(_done);
    return _write(
      () => _db.transaction<void>((txn) async {
        await requireAllDocuments(txn, unique);
        await updateDocuments(txn, unique, 'deleted_at = NULL');
      }),
    );
  }

  @override
  Future<Result<void>> deletePermanently(List<String> ids) {
    final unique = ids.toSet();
    if (unique.isEmpty) return Future.value(_done);
    return _write(() async {
      final files = await _db.transaction((txn) async {
        await requireAllDocuments(txn, unique);
        return deleteDocumentRows(txn, unique);
      });
      await _deleteFiles(files);
    });
  }

  @override
  Future<Result<void>> emptyTrash() => _write(() async {
    final files = await _db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT id FROM documents WHERE deleted_at IS NOT NULL',
      );
      return deleteDocumentRows(txn, rows.map((row) => row['id']! as String));
    });
    await _deleteFiles(files);
  });

  /// The previous file is left untouched: the vault owns the move and
  /// decides how the plain or encrypted source is destroyed.
  @override
  Future<Result<DocumentEntity>> updateVaultState(
    String id, {
    required String filePath,
    required bool isInVault,
    required bool isEncrypted,
  }) => _write(() async {
    final size = await _requireFileSize(filePath);
    return _db.transaction((txn) async {
      final current = await requireDocument(txn, id);
      if (current.filePath != filePath) {
        await requireUnusedFilePath(txn, filePath);
      }
      await txn.update(
        'documents',
        {
          'file_path': filePath,
          'file_size': size,
          'is_in_vault': isInVault ? 1 : 0,
          'is_encrypted': isEncrypted ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return requireDocument(txn, id);
    });
  });

  @override
  Future<Result<List<DocumentPage>>> pagesOf(String documentId) =>
      _read(() async {
        await requireDocument(_db, documentId);
        final rows = await _db.query(
          'document_pages',
          where: 'document_id = ?',
          whereArgs: [documentId],
          orderBy: 'page_order ASC',
        );
        return rows.map(pageFromRow).toList();
      });

  @override
  Future<Result<List<FolderEntity>>> folders({String? parentId}) =>
      _read(() => _folders.list(parentId));

  @override
  Future<Result<FolderEntity>> getFolder(String id) =>
      _read(() => _folders.get(id));

  @override
  Future<Result<FolderEntity>> createFolder(String name, {String? parentId}) =>
      _write(() => _folders.create(name, parentId: parentId));

  @override
  Future<Result<FolderEntity>> renameFolder(String id, String newName) =>
      _write(() => _folders.rename(id, newName));

  @override
  Future<Result<void>> deleteFolder(String id) =>
      _write(() => _folders.delete(id));

  @override
  Future<Result<List<TagEntity>>> allTags() => _read(_tags.all);

  @override
  Future<Result<List<TagEntity>>> tagsOf(String documentId) =>
      _read(() => _tags.of(documentId));

  @override
  Future<Result<void>> setTags(String documentId, List<String> tagNames) =>
      _write(() => _tags.replace(documentId, tagNames));

  /// Rows first, then every storage area: scan sessions, exports and vault
  /// files are user data too. Lists are told as soon as the rows are gone,
  /// even if a file later resists deletion (reported as a failure).
  @override
  Future<Result<void>> wipeAll() => guard(
    () async {
      await _db.transaction<void>((txn) async {
        for (final table in const [
          'ocr_results',
          'document_tags',
          'favorites',
          'document_pages',
          'documents',
          'tags',
          'folders',
        ]) {
          await txn.delete(table);
        }
      });
      notifyChanged();
      FileSystemException? firstError;
      for (final area in StorageArea.values) {
        try {
          final directory = _storage.directoryOf(area);
          if (await directory.exists()) await directory.delete(recursive: true);
          await directory.create(recursive: true);
        } on FileSystemException catch (error) {
          firstError ??= error;
        }
      }
      if (firstError != null) throw firstError;
    },
    onError: (error, _) => libraryFailure(error, StorageFailureKind.writeError),
  );

  Future<DocumentEntity> _insert(NewDocument draft) async {
    final size = await _requireFileSize(draft.filePath);
    final id = _uuid.v4();
    final now = _now();
    final pages = draft.pageImagePaths;
    return _db.transaction((txn) async {
      final folderId = draft.folderId;
      if (folderId != null) await _folders.require(txn, folderId);
      await requireUnusedFilePath(txn, draft.filePath);
      final name = await uniqueDocumentName(
        txn,
        sanitizeFileName(draft.name),
        folderId: folderId,
      );
      await txn.insert('documents', {
        'id': id,
        'name': name,
        'file_path': draft.filePath,
        'file_type': draft.fileType.extension,
        'file_size': size,
        'page_count': draft.pageCount ?? (pages.isEmpty ? null : pages.length),
        'thumbnail_path': draft.thumbnailPath,
        'folder_id': folderId,
        'source': draft.source.dbValue,
        'created_at': now,
        'updated_at': now,
      });
      final batch = txn.batch();
      for (final (index, imagePath) in pages.indexed) {
        batch.insert('document_pages', {
          'id': _uuid.v4(),
          'document_id': id,
          'page_order': index,
          'image_path': imagePath,
          'created_at': now,
        });
      }
      await batch.commit(noResult: true);
      return requireDocument(txn, id);
    });
  }

  /// Size of a stored file. A missing file, or a path leaving the storage
  /// root, is `notFound`: nothing outside the library is ever registered.
  Future<int> _requireFileSize(String relativePath) async {
    final File file;
    try {
      file = _storage.file(relativePath);
    } on ArgumentError {
      throw kNotFound;
    }
    if (!await file.exists()) throw kNotFound;
    return file.length();
  }

  /// Best effort: the rows are already gone, so a missing or locked file must
  /// not turn the operation into a failure. Leftovers are swept at startup.
  Future<void> _deleteFiles(Iterable<String> relativePaths) async {
    for (final path in relativePaths) {
      try {
        await _storage.delete(path);
      } on FileSystemException {
        continue;
      } on ArgumentError {
        continue;
      }
    }
  }
}
