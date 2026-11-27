import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:md_scanner/shared/services/library/library_sql.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// [OcrTextRepository] storing the text in the `ocr_results` table, where
/// the library search reads it.
///
/// A document holds either one document-level text (`pageIndex` null) or one
/// text per page, never both: saving in one form drops the other, so
/// [textOf] never returns the same passage twice. Saving a blank text removes
/// the entry.
class SqliteOcrTextRepository implements OcrTextRepository {
  SqliteOcrTextRepository({
    required this._db,
    Uuid? uuid,
    DateTime Function()? clock,
    this._onChanged,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  /// Separates the pages in [textOf].
  static const String pageSeparator = '\n\n';

  final Database _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Called after each change: search results depend on the saved text, so
  /// the document lists have to reload.
  final void Function()? _onChanged;

  @override
  Future<Result<void>> save({
    required String documentId,
    required String text,
    String? language,
    int? pageIndex,
  }) => _write(() async {
    if (pageIndex != null && pageIndex < 0) {
      throw const FailureException(ValidationFailure('invalid_page_index'));
    }
    await _db.transaction<void>((txn) async {
      final document = await txn.query(
        'documents',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [documentId],
        limit: 1,
      );
      if (document.isEmpty) throw kNotFound;

      final sameScope = pageIndex == null
          ? 'page_index IS NULL'
          : 'page_index = ?';
      final otherForm = pageIndex == null
          ? 'page_index IS NOT NULL'
          : 'page_index IS NULL';
      final scopeArgs = [documentId, ?pageIndex];
      await txn.delete(
        'ocr_results',
        where: 'document_id = ? AND $otherForm',
        whereArgs: [documentId],
      );
      if (text.trim().isEmpty) {
        await txn.delete(
          'ocr_results',
          where: 'document_id = ? AND $sameScope',
          whereArgs: scopeArgs,
        );
        return;
      }
      final now = _clock().toUtc().millisecondsSinceEpoch;
      final updated = await txn.update(
        'ocr_results',
        {'extracted_text': text, 'language': language, 'updated_at': now},
        where: 'document_id = ? AND $sameScope',
        whereArgs: scopeArgs,
      );
      if (updated == 0) {
        await txn.insert('ocr_results', {
          'id': _uuid.v4(),
          'document_id': documentId,
          'page_index': pageIndex,
          'extracted_text': text,
          'language': language,
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  });

  @override
  Future<Result<String?>> textOf(String documentId) => guard(
    () async {
      final rows = await _db.query(
        'ocr_results',
        columns: ['extracted_text'],
        where: 'document_id = ?',
        whereArgs: [documentId],
        orderBy: 'page_index ASC, created_at ASC',
      );
      if (rows.isEmpty) return null;
      return rows
          .map((row) => row['extracted_text']! as String)
          .join(pageSeparator);
    },
    onError: (error, _) => libraryFailure(error, StorageFailureKind.readError),
  );

  /// Idempotent: succeeds when nothing was saved for [documentId].
  @override
  Future<Result<void>> deleteFor(String documentId) => _write(() async {
    await _db.delete(
      'ocr_results',
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
  });

  Future<Result<void>> _write(Future<void> Function() body) async {
    final result = await guard(
      body,
      onError: (error, _) =>
          libraryFailure(error, StorageFailureKind.writeError),
    );
    if (result.isSuccess) _onChanged?.call();
    return result;
  }
}
