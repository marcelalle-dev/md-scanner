import 'package:collection/collection.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/services/library/library_sql.dart';
import 'package:md_scanner/shared/services/library/tag_store.dart';
import 'package:sqflite/sqflite.dart';

/// Longest document name kept in the library (same bound as
/// `sanitizeFileName`), numbering suffix included.
const int kMaxDocumentNameLength = 80;

/// Loads a document row or throws `notFound`.
Future<DocumentEntity> requireDocument(DatabaseExecutor db, String id) async {
  final rows = await db.query(
    'documents',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  if (rows.isEmpty) throw kNotFound;
  return documentFromRow(rows.first);
}

/// Throws `notFound` unless every id of [ids] is a document.
Future<void> requireAllDocuments(DatabaseExecutor db, Set<String> ids) async {
  var found = 0;
  for (final chunk in ids.slices(kSqlChunkSize)) {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM documents '
      'WHERE id IN (${placeholders(chunk.length)})',
      chunk,
    );
    found += rows.first['total']! as int;
  }
  if (found != ids.length) throw kNotFound;
}

/// Runs `UPDATE documents SET [assignment]` on [ids]; [args] feed the
/// assignment's own placeholders.
Future<void> updateDocuments(
  DatabaseExecutor db,
  Set<String> ids,
  String assignment, [
  List<Object?> args = const [],
]) async {
  for (final chunk in ids.slices(kSqlChunkSize)) {
    await db.rawUpdate(
      'UPDATE documents SET $assignment '
      'WHERE id IN (${placeholders(chunk.length)})',
      [...args, ...chunk],
    );
  }
}

/// A stored file belongs to one document: sharing it would let the deletion
/// of one document destroy the other's content.
Future<void> requireUnusedFilePath(DatabaseExecutor db, String filePath) async {
  final rows = await db.query(
    'documents',
    columns: ['id'],
    where: 'file_path = ?',
    whereArgs: [filePath],
    limit: 1,
  );
  if (rows.isNotEmpty) {
    throw const FailureException(
      StorageFailure(
        StorageFailureKind.alreadyExists,
        debugMessage: 'file_already_registered',
      ),
    );
  }
}

/// Returns [desired], or "desired (n)" when a live, non-vault document of
/// the folder already uses it (vault names must not leak through a suffix).
/// The result never exceeds [kMaxDocumentNameLength].
Future<String> uniqueDocumentName(
  DatabaseExecutor db,
  String desired, {
  required String? folderId,
  String? excludingId,
}) async {
  const suffixRoom = 10;
  final stem = desired.length <= kMaxDocumentNameLength - suffixRoom
      ? desired
      : desired.substring(0, kMaxDocumentNameLength - suffixRoom).trimRight();
  final rows = await db.rawQuery(
    'SELECT name FROM documents '
    'WHERE deleted_at IS NULL AND is_in_vault = 0 '
    "AND IFNULL(folder_id, '') = ? AND id <> ? "
    "AND name LIKE ? ESCAPE '\\'",
    [folderId ?? '', excludingId ?? '', '${escapeLike(stem)}%'],
  );
  final taken = {
    for (final row in rows) (row['name']! as String).toLowerCase(),
  };
  var candidate = desired;
  for (var n = 2; taken.contains(candidate.toLowerCase()); n++) {
    final suffix = ' ($n)';
    final room = kMaxDocumentNameLength - suffix.length;
    final base = desired.length <= room
        ? desired
        : desired.substring(0, room).trimRight();
    candidate = '$base$suffix';
  }
  return candidate;
}

/// Deletes the rows of [ids] (pages, OCR text, favorite and tag links go
/// with them through the foreign keys), drops the tags left unused and
/// returns the files that no remaining row references.
Future<Set<String>> deleteDocumentRows(
  Transaction txn,
  Iterable<String> ids,
) async {
  final files = <String>{};
  for (final chunk in ids.slices(kSqlChunkSize)) {
    final marks = placeholders(chunk.length);
    final documents = await txn.rawQuery(
      'SELECT file_path, thumbnail_path FROM documents WHERE id IN ($marks)',
      chunk,
    );
    for (final row in documents) {
      files.add(row['file_path']! as String);
      final thumbnail = row['thumbnail_path'] as String?;
      if (thumbnail != null) files.add(thumbnail);
    }
    final pages = await txn.rawQuery(
      'SELECT image_path FROM document_pages WHERE document_id IN ($marks)',
      chunk,
    );
    files.addAll(pages.map((row) => row['image_path']! as String));
    await txn.rawDelete('DELETE FROM documents WHERE id IN ($marks)', chunk);
  }
  await TagStore.deleteUnused(txn);
  files.removeAll(await referencedFilePaths(txn, files));
  return files;
}

/// Subset of [paths] still referenced by a document, a thumbnail or a page.
Future<Set<String>> referencedFilePaths(
  DatabaseExecutor db,
  Iterable<String> paths,
) async {
  final referenced = <String>{};
  for (final chunk in paths.slices(kSqlChunkSize ~/ 3)) {
    final marks = placeholders(chunk.length);
    final rows = await db.rawQuery(
      'SELECT file_path AS path FROM documents WHERE file_path IN ($marks) '
      'UNION SELECT thumbnail_path FROM documents '
      'WHERE thumbnail_path IN ($marks) '
      'UNION SELECT image_path FROM document_pages '
      'WHERE image_path IN ($marks)',
      [...chunk, ...chunk, ...chunk],
    );
    referenced.addAll(rows.map((row) => row['path']! as String));
  }
  return referenced;
}
