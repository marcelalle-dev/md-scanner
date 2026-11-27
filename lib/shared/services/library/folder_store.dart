import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/services/library/library_sql.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Folder tree of the library. Methods throw [FailureException]; the
/// repository wraps them into a `Result`.
class FolderStore {
  FolderStore({required this._db, required this._uuid, required this._now});

  final Database _db;
  final Uuid _uuid;
  final int Function() _now;

  /// `document_count` only counts what the library lists: live, non-vault
  /// documents directly inside the folder.
  static const String _select = '''
    SELECT f.*, (
      SELECT COUNT(*) FROM documents d
      WHERE d.folder_id = f.id AND d.deleted_at IS NULL AND d.is_in_vault = 0
    ) AS document_count
    FROM folders f
  ''';

  /// Recursive set of a folder and all its descendants, bound to one `?`.
  static const String _subtree = '''
    WITH RECURSIVE subtree(id) AS (
      SELECT ?
      UNION ALL
      SELECT f.id FROM folders f JOIN subtree s ON f.parent_id = s.id
    )
    SELECT id FROM subtree
  ''';

  /// Sub-folders of [parentId] (root folders when null), sorted by name.
  /// An unknown parent has no children: the list is empty.
  Future<List<FolderEntity>> list(String? parentId) async {
    final rows = await _db.rawQuery(
      '$_select WHERE ${parentId == null ? 'f.parent_id IS NULL' : 'f.parent_id = ?'} '
      'ORDER BY f.name COLLATE NOCASE ASC, f.id ASC',
      [?parentId],
    );
    return rows.map(folderFromRow).toList();
  }

  Future<FolderEntity> require(DatabaseExecutor db, String id) async {
    final rows = await db.rawQuery('$_select WHERE f.id = ?', [id]);
    if (rows.isEmpty) throw kNotFound;
    return folderFromRow(rows.first);
  }

  Future<FolderEntity> get(String id) => require(_db, id);

  Future<FolderEntity> create(String name, {String? parentId}) async {
    final cleaned = _validName(name);
    return _db.transaction((txn) async {
      if (parentId != null) await require(txn, parentId);
      await _requireFreeName(txn, cleaned, parentId: parentId);
      final id = _uuid.v4();
      final now = _now();
      await txn.insert('folders', {
        'id': id,
        'name': cleaned,
        'parent_id': parentId,
        'created_at': now,
        'updated_at': now,
      });
      return require(txn, id);
    });
  }

  Future<FolderEntity> rename(String id, String newName) async {
    final cleaned = _validName(newName);
    return _db.transaction((txn) async {
      final current = await require(txn, id);
      if (current.name == cleaned) return current;
      await _requireFreeName(
        txn,
        cleaned,
        parentId: current.parentId,
        excludingId: id,
      );
      await txn.update(
        'folders',
        {'name': cleaned, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );
      return require(txn, id);
    });
  }

  /// Removes the folder and its whole sub-tree. Every document found in it,
  /// trashed and vault ones included, moves to the root first: deleting a
  /// folder never deletes a document.
  Future<void> delete(String id) => _db.transaction<void>((txn) async {
    await require(txn, id);
    await txn.rawUpdate(
      'UPDATE documents SET folder_id = NULL WHERE folder_id IN ($_subtree)',
      [id],
    );
    await txn.rawDelete('DELETE FROM folders WHERE id IN ($_subtree)', [id]);
  });

  String _validName(String name) {
    final cleaned = sanitizeFileName(name, fallback: '');
    if (cleaned.isEmpty) {
      throw const FailureException(ValidationFailure('empty_name'));
    }
    return cleaned;
  }

  /// The unique index only folds ASCII case; comparing in Dart also rejects
  /// "École" next to "école".
  Future<void> _requireFreeName(
    DatabaseExecutor db,
    String name, {
    required String? parentId,
    String? excludingId,
  }) async {
    final siblings = await db.rawQuery(
      "SELECT id, name FROM folders WHERE IFNULL(parent_id, '') = ?",
      [parentId ?? ''],
    );
    final wanted = name.toLowerCase();
    final taken = siblings.any(
      (row) =>
          row['id'] != excludingId &&
          (row['name']! as String).toLowerCase() == wanted,
    );
    if (taken) {
      throw const FailureException(
        StorageFailure(StorageFailureKind.alreadyExists),
      );
    }
  }
}
