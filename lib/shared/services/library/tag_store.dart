import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/services/library/library_sql.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Tags of the library. Methods throw [FailureException]; the repository
/// wraps them into a `Result`.
class TagStore {
  TagStore({required this._db, required this._uuid, required this._now});

  final Database _db;
  final Uuid _uuid;
  final int Function() _now;

  Future<List<TagEntity>> all() async {
    final rows = await _db.query(
      'tags',
      columns: ['id', 'name'],
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(tagFromRow).toList();
  }

  Future<List<TagEntity>> of(String documentId) async {
    await _requireDocument(_db, documentId);
    final rows = await _db.rawQuery(
      'SELECT t.id, t.name FROM tags t '
      'JOIN document_tags dt ON dt.tag_id = t.id '
      'WHERE dt.document_id = ? ORDER BY t.name COLLATE NOCASE ASC, t.id ASC',
      [documentId],
    );
    return rows.map(tagFromRow).toList();
  }

  /// Replaces the tags of [documentId] with [names].
  ///
  /// Names are trimmed and compared case-insensitively: the first spelling of
  /// a new tag is kept, an existing tag keeps its own. Tags left without any
  /// document are deleted so the tag filter never lists a dead entry.
  Future<void> replace(String documentId, List<String> names) =>
      _db.transaction<void>((txn) async {
        await _requireDocument(txn, documentId);
        final wanted = <String, String>{};
        for (final raw in names) {
          final name = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (name.isEmpty) continue;
          wanted.putIfAbsent(name.toLowerCase(), () => name);
        }
        final known = {
          for (final row in await txn.query('tags', columns: ['id', 'name']))
            (row['name']! as String).toLowerCase(): row['id']! as String,
        };
        await txn.delete(
          'document_tags',
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
        for (final MapEntry(key: folded, value: name) in wanted.entries) {
          var tagId = known[folded];
          if (tagId == null) {
            tagId = _uuid.v4();
            await txn.insert('tags', {
              'id': tagId,
              'name': name,
              'created_at': _now(),
            });
          }
          await txn.insert('document_tags', {
            'document_id': documentId,
            'tag_id': tagId,
          });
        }
        await deleteUnused(txn);
      });

  /// Drops the tags no document carries any more.
  static Future<void> deleteUnused(DatabaseExecutor db) => db.rawDelete(
    'DELETE FROM tags WHERE id NOT IN (SELECT tag_id FROM document_tags)',
  );

  Future<void> _requireDocument(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'documents',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw kNotFound;
  }
}
