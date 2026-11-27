import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:sqflite/sqflite.dart';

/// Upper bound of bound values per `IN (...)` list: older Android SQLite
/// builds refuse statements with more than 999 variables.
const int kSqlChunkSize = 400;

const FailureException kNotFound = FailureException(
  StorageFailure(StorageFailureKind.notFound),
);

DateTime dateFromDb(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

String placeholders(int count) => List.filled(count, '?').join(', ');

/// Escapes the LIKE wildcards of [input]; pair with `ESCAPE '\'`.
String escapeLike(String input) =>
    input.replaceAllMapped(RegExp(r'[\\%_]'), (match) => '\\${match[0]}');

/// `%term%` patterns for a search.
///
/// SQLite's LIKE only folds ASCII letters, so the lower-case, upper-case and
/// capitalized spellings are tried as well: "été" then finds "Été 2024".
List<String> searchPatterns(String term) {
  final lower = term.toLowerCase();
  final capitalized = lower.replaceAllMapped(
    RegExp(r'(^|\s)(\S)'),
    (match) => '${match[1]}${match[2]!.toUpperCase()}',
  );
  return [
    for (final variant in {term, lower, term.toUpperCase(), capitalized})
      '%${escapeLike(variant)}%',
  ];
}

/// Maps a storage exception to a typed failure. Exception messages are
/// dropped on purpose: SQLite echoes values (names, paths) in them.
Failure? libraryFailure(Object error, StorageFailureKind databaseKind) {
  if (error is FailureException) return error.failure;
  if (error is DatabaseException) {
    if (error.isUniqueConstraintError()) {
      return const StorageFailure(
        StorageFailureKind.alreadyExists,
        debugMessage: 'unique_constraint',
      );
    }
    return StorageFailure(
      databaseKind,
      debugMessage: 'DatabaseException(code=${error.getResultCode()})',
    );
  }
  return null;
}

DocumentEntity documentFromRow(Map<String, Object?> row) {
  final type = DocumentFileType.fromExtension(row['file_type']! as String);
  if (type == null) {
    throw const FailureException(
      StorageFailure(
        StorageFailureKind.corrupted,
        debugMessage: 'unknown_file_type',
      ),
    );
  }
  final deletedAt = row['deleted_at'] as int?;
  return DocumentEntity(
    id: row['id']! as String,
    name: row['name']! as String,
    filePath: row['file_path']! as String,
    fileType: type,
    fileSize: row['file_size']! as int,
    pageCount: row['page_count'] as int?,
    thumbnailPath: row['thumbnail_path'] as String?,
    folderId: row['folder_id'] as String?,
    source: DocumentSource.fromDb(row['source']! as String),
    createdAt: dateFromDb(row['created_at']! as int),
    updatedAt: dateFromDb(row['updated_at']! as int),
    isFavorite: row['is_favorite'] == 1,
    isEncrypted: row['is_encrypted'] == 1,
    isInVault: row['is_in_vault'] == 1,
    deletedAt: deletedAt == null ? null : dateFromDb(deletedAt),
  );
}

DocumentPage pageFromRow(Map<String, Object?> row) => DocumentPage(
  id: row['id']! as String,
  documentId: row['document_id']! as String,
  pageOrder: row['page_order']! as int,
  imagePath: row['image_path']! as String,
  createdAt: dateFromDb(row['created_at']! as int),
);

/// Expects the extra `document_count` column computed by the folder queries.
FolderEntity folderFromRow(Map<String, Object?> row) => FolderEntity(
  id: row['id']! as String,
  name: row['name']! as String,
  parentId: row['parent_id'] as String?,
  createdAt: dateFromDb(row['created_at']! as int),
  updatedAt: dateFromDb(row['updated_at']! as int),
  documentCount: (row['document_count'] as int?) ?? 0,
);

TagEntity tagFromRow(Map<String, Object?> row) =>
    TagEntity(id: row['id']! as String, name: row['name']! as String);

/// SELECT statement and arguments for a [DocumentQuery].
class DocumentQuerySql {
  const DocumentQuerySql._(this.sql, this.args);

  factory DocumentQuerySql.build(DocumentQuery query) {
    final where = <String>[
      query.inTrash ? 'd.deleted_at IS NOT NULL' : 'd.deleted_at IS NULL',
      'd.is_in_vault = ?',
    ];
    final args = <Object?>[query.inVault ? 1 : 0];

    if (query.favoritesOnly) where.add('d.is_favorite = 1');
    if (query.restrictToFolder) {
      if (query.folderId == null) {
        where.add('d.folder_id IS NULL');
      } else {
        where.add('d.folder_id = ?');
        args.add(query.folderId);
      }
    }
    if (query.tagId != null) {
      where.add(
        'EXISTS (SELECT 1 FROM document_tags dt '
        'WHERE dt.document_id = d.id AND dt.tag_id = ?)',
      );
      args.add(query.tagId);
    }
    final types = query.types;
    if (types != null) {
      if (types.isEmpty) {
        where.add('0');
      } else {
        where.add('d.file_type IN (${placeholders(types.length)})');
        args.addAll(types.map((type) => type.extension));
      }
    }
    final search = query.search?.trim() ?? '';
    if (search.isNotEmpty) {
      final patterns = searchPatterns(search);
      String anyLike(String column) =>
          patterns.map((_) => "$column LIKE ? ESCAPE '\\'").join(' OR ');
      where.add(
        '(${anyLike('d.name')} OR EXISTS (SELECT 1 FROM ocr_results o '
        'WHERE o.document_id = d.id AND (${anyLike('o.extracted_text')})))',
      );
      args
        ..addAll(patterns)
        ..addAll(patterns);
    }

    final buffer = StringBuffer('SELECT d.* FROM documents d WHERE ')
      ..write(where.join(' AND '))
      ..write(' ORDER BY ${_orderBy(query.sort)}');
    final limit = query.limit;
    if (limit != null) {
      buffer.write(' LIMIT ?');
      args.add(limit < 0 ? 0 : limit);
    }
    return DocumentQuerySql._(buffer.toString(), args);
  }

  final String sql;
  final List<Object?> args;

  /// Secondary keys keep the order stable when the main key ties.
  static String _orderBy(DocumentSort sort) {
    final direction = sort.ascending ? 'ASC' : 'DESC';
    return switch (sort.field) {
      DocumentSortField.name =>
        'd.name COLLATE NOCASE $direction, d.updated_at DESC, d.id ASC',
      DocumentSortField.date =>
        'd.updated_at $direction, d.name COLLATE NOCASE ASC, d.id ASC',
      DocumentSortField.size =>
        'd.file_size $direction, d.name COLLATE NOCASE ASC, d.id ASC',
    };
  }
}
