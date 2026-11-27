import 'package:md_scanner/shared/services/backup/backup_format.dart';
import 'package:md_scanner/shared/services/backup/backup_import_plan.dart';
import 'package:md_scanner/shared/services/library/document_rows.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Applies an [ImportPlan] to the database in a single transaction: either
/// every row of the restore is written, or the library is left untouched.
class BackupImportWriter {
  BackupImportWriter({required this._db, required this._uuid});

  static const int _batchSize = 100;

  final Database _db;
  final Uuid _uuid;

  Future<ImportOutcome> write(ImportPlan plan) => _db.transaction((txn) async {
    var obsoleteFiles = <String>{};
    final vaultFolders = <String, String>{};
    if (plan.mode == RestoreMode.replace) {
      final replaced = await txn.rawQuery(
        'SELECT id FROM documents WHERE is_in_vault = 0',
      );
      obsoleteFiles = await deleteDocumentRows(
        txn,
        replaced.map((row) => row['id']! as String),
      );
      // Only vault documents are left: remember where they were filed so
      // they return to their folder if the backup brings it back.
      final filed = await txn.rawQuery(
        'SELECT id, folder_id FROM documents WHERE folder_id IS NOT NULL',
      );
      for (final row in filed) {
        vaultFolders[row['id']! as String] = row['folder_id']! as String;
      }
      await txn.rawUpdate('UPDATE documents SET folder_id = NULL');
      await txn.delete('folders');
    }

    final (folderIds, foldersCreated) = await _writeFolders(txn, plan.folders);
    var batch = txn.batch();
    for (final row in plan.documents) {
      batch.insert('documents', {
        ...row,
        'folder_id': folderIds[row['folder_id']],
      });
    }
    for (final row in plan.pages) {
      batch.insert('document_pages', row);
    }
    await batch.commit(noResult: true);

    final tagsCreated = await _writeTagLinks(txn, plan);
    batch = txn.batch();
    for (final row in plan.favorites) {
      batch.insert('favorites', row);
    }
    await batch.commit(noResult: true);
    await _writeOcrText(txn, plan);

    for (final MapEntry(key: documentId, value: folderId)
        in vaultFolders.entries) {
      final restored = folderIds[folderId];
      if (restored == null) continue;
      await txn.update(
        'documents',
        {'folder_id': restored},
        where: 'id = ?',
        whereArgs: [documentId],
      );
    }
    return ImportOutcome(
      foldersCreated: foldersCreated,
      tagsCreated: tagsCreated,
      obsoleteFiles: obsoleteFiles,
    );
  });

  /// Creates the folders of the backup, parents first, and returns the device
  /// id of each backup folder id.
  ///
  /// A folder already on the device (same id, or same name under the same
  /// parent) is reused rather than duplicated: restoring twice, or restoring
  /// after re-creating a folder by hand, merges into it.
  Future<(Map<String, String>, int)> _writeFolders(
    Transaction txn,
    List<Map<String, Object?>> folders,
  ) async {
    final deviceIds = <String>{};
    final siblings = <String, Map<String, String>>{};
    for (final row in await txn.query('folders')) {
      final id = row['id']! as String;
      deviceIds.add(id);
      siblings.putIfAbsent(
        (row['parent_id'] as String?) ?? '',
        () => {},
      )[(row['name']! as String).toLowerCase()] = id;
    }
    final children = <String?, List<Map<String, Object?>>>{};
    for (final folder in folders) {
      children
          .putIfAbsent(folder['parent_id'] as String?, () => [])
          .add(folder);
    }

    final mapping = <String, String>{};
    final queue = [...?children[null]];
    var handled = 0;
    var created = 0;
    while (queue.isNotEmpty) {
      final folder = queue.removeLast();
      handled++;
      final id = folder['id']! as String;
      final backupParent = folder['parent_id'] as String?;
      final parentId = backupParent == null ? null : mapping[backupParent];
      final names = siblings.putIfAbsent(parentId ?? '', () => {});
      final folded = (folder['name']! as String).toLowerCase();
      if (deviceIds.contains(id)) {
        mapping[id] = id;
      } else if (names[folded] case final existing?) {
        mapping[id] = existing;
      } else {
        await txn.insert('folders', {...folder, 'parent_id': parentId});
        deviceIds.add(id);
        names[folded] = id;
        mapping[id] = id;
        created++;
      }
      queue.addAll(children[id] ?? const []);
    }
    // A folder never reached from a root has an unknown parent or sits in a
    // cycle: the tree of the backup is not a tree.
    if (handled != folders.length) throw kInvalidBackupRow;
    return (mapping, created);
  }

  /// Links the restored documents to their tags, creating a tag only when a
  /// document needs it and no tag of that name exists on the device.
  Future<int> _writeTagLinks(Transaction txn, ImportPlan plan) async {
    final deviceIds = <String>{};
    final byName = <String, String>{};
    for (final row in await txn.query('tags')) {
      deviceIds.add(row['id']! as String);
      byName[(row['name']! as String).toLowerCase()] = row['id']! as String;
    }
    final mapping = <String, String>{};
    var created = 0;
    for (final link in plan.documentTags) {
      final backupId = link['tag_id']! as String;
      var tagId = mapping[backupId];
      if (tagId == null) {
        final tag = plan.tags[backupId];
        if (tag == null) throw kInvalidBackupRow;
        final folded = (tag['name']! as String).toLowerCase();
        tagId = deviceIds.contains(backupId) ? backupId : byName[folded];
        if (tagId == null) {
          await txn.insert('tags', tag);
          deviceIds.add(backupId);
          byName[folded] = backupId;
          tagId = backupId;
          created++;
        }
        mapping[backupId] = tagId;
      }
      await txn.insert('document_tags', {
        'document_id': link['document_id'],
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return created;
  }

  Future<void> _writeOcrText(Transaction txn, ImportPlan plan) async {
    var seen = 0;
    var pending = 0;
    var batch = txn.batch();
    await for (final row in readBackupRows(plan.ocrFile)) {
      seen++;
      final documentId = backupField<String>(row, 'document_id');
      if (!plan.importedIds.contains(documentId)) continue;
      batch.insert('ocr_results', {
        'id': _uuid.v4(),
        'document_id': documentId,
        'page_index': backupField<int?>(row, 'page_index'),
        'extracted_text': backupField<String>(row, 'extracted_text'),
        'language': backupField<String?>(row, 'language'),
        'created_at': backupField<int>(row, 'created_at'),
        'updated_at': backupField<int>(row, 'updated_at'),
      });
      if (++pending == _batchSize) {
        await batch.commit(noResult: true);
        batch = txn.batch();
        pending = 0;
      }
    }
    await batch.commit(noResult: true);
    if (seen != plan.manifest.counts[BackupFormat.ocrResults]) {
      throw kInvalidBackupRow;
    }
  }
}
