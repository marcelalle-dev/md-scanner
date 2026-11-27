import 'dart:io';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/services/backup/backup_archive.dart';
import 'package:md_scanner/shared/services/backup/backup_format.dart';
import 'package:md_scanner/shared/services/backup/backup_import_plan.dart';
import 'package:md_scanner/shared/services/backup/backup_import_writer.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Restores a backup archive into the library.
///
/// Nothing of the archive is trusted: entry names are checked before any
/// extraction, rows are type-checked, and files are extracted to paths
/// allocated by [FileStorage] (never to a path read from the archive), so a
/// crafted backup cannot write or reference anything outside the storage.
///
/// Order of operations: new files are written first under fresh names, rows
/// are committed in one transaction, and only then are the files replaced by
/// a `replace` restore deleted. An interruption therefore leaves unreferenced
/// files (swept by the startup cleanup), never a row without its file.
class BackupImporter {
  BackupImporter({
    required this._db,
    required this._storage,
    required this._uuid,
  });

  final Database _db;
  final FileStorage _storage;
  final Uuid _uuid;

  Future<RestoreSummary> run({
    required String archivePath,
    required Directory workDir,
    required RestoreMode mode,
    required int schemaVersion,
    void Function(double fraction)? onProgress,
  }) async {
    final entries = await inspectBackupZip(archivePath);
    final metadata = {
      BackupFormat.manifestEntry: p.join(workDir.path, 'manifest.json'),
      for (final table in BackupFormat.tables)
        BackupFormat.tableEntry(table): p.join(workDir.path, '$table.jsonl'),
    };
    if (!metadata.keys.every(entries.containsKey)) {
      throw const BackupFormatException('entries_missing');
    }
    await extractBackupEntries(zipPath: archivePath, targets: metadata);

    final manifest = BackupManifest.decode(
      await File(metadata[BackupFormat.manifestEntry]!).readAsString(),
    );
    if (manifest.formatVersion != BackupFormat.version ||
        manifest.schemaVersion < 1 ||
        manifest.schemaVersion > schemaVersion) {
      throw const FailureException(
        ValidationFailure('backup_unsupported_version'),
      );
    }
    final storedFiles = entries.keys
        .where((name) => name.startsWith(BackupFormat.filesPrefix))
        .length;
    if (storedFiles != manifest.files) {
      throw const BackupFormatException('file_count_mismatch');
    }

    File table(String name) => File(metadata[BackupFormat.tableEntry(name)]!);
    final plan = ImportPlan(
      mode: mode,
      manifest: manifest,
      ocrFile: table(BackupFormat.ocrResults),
    );
    try {
      await _planRows(plan, table, entries);
      if (plan.targets.isNotEmpty) {
        await extractBackupEntries(
          zipPath: archivePath,
          targets: plan.targets,
          onProgress: onProgress,
        );
      }
      final outcome = await BackupImportWriter(
        db: _db,
        uuid: _uuid,
      ).write(plan);
      await _deleteFiles(outcome.obsoleteFiles);
      return RestoreSummary(
        mode: mode,
        documentsImported: plan.documents.length,
        documentsSkipped: plan.skippedDocuments,
        foldersImported: outcome.foldersCreated,
        tagsImported: outcome.tagsCreated,
        filesRestored: plan.targets.length,
      );
    } catch (_) {
      await _deleteFiles(plan.newFiles);
      rethrow;
    }
  }

  /// Reads and validates the small tables, decides which documents are
  /// imported and allocates the storage path of each of their files.
  Future<void> _planRows(
    ImportPlan plan,
    File Function(String name) table,
    Map<String, int> entries,
  ) async {
    /// Reads a table and checks its row count against the manifest.
    Future<void> each(
      String name,
      void Function(Map<String, Object?> row) visit,
    ) async {
      var rows = 0;
      await for (final row in readBackupRows(table(name))) {
        rows++;
        visit(row);
      }
      if (rows != plan.manifest.counts[name]) {
        throw const BackupFormatException('row_count_mismatch');
      }
    }

    /// Claims the archive entry behind a stored path and plans its
    /// extraction to a fresh path of [area]. Returns that new stored path.
    String claim(
      String storedPath,
      StorageArea area, {
      String? extension,
      String? group,
    }) {
      final entry = BackupFormat.fileEntry(storedPath);
      if (!isSafeArchivePath(storedPath) ||
          !entries.containsKey(entry) ||
          plan.targets.containsKey(entry)) {
        throw kInvalidBackupRow;
      }
      final written = RegExp(
        r'^\.[A-Za-z0-9]{1,8}$',
      ).stringMatch(p.posix.extension(storedPath));
      final relative = _storage.allocate(
        area,
        extension: extension ?? written ?? 'bin',
        group: group,
      );
      plan.targets[entry] = _storage.absolutePath(relative);
      plan.newFiles.add(relative);
      return relative;
    }

    await each(BackupFormat.folders, (row) {
      final name = sanitizeFileName(
        backupField<String>(row, 'name'),
        fallback: '',
      );
      if (name.isEmpty) throw kInvalidBackupRow;
      plan.folders.add({
        'id': backupField<String>(row, 'id'),
        'name': name,
        'parent_id': backupField<String?>(row, 'parent_id'),
        'created_at': backupField<int>(row, 'created_at'),
        'updated_at': backupField<int>(row, 'updated_at'),
      });
    });
    await each(BackupFormat.tags, (row) {
      final name = backupField<String>(row, 'name').trim();
      if (name.isEmpty) throw kInvalidBackupRow;
      final id = backupField<String>(row, 'id');
      plan.tags[id] = {
        'id': id,
        'name': name,
        'created_at': backupField<int>(row, 'created_at'),
      };
    });

    final existing = await _idsOnDevice(plan.mode);
    final seen = <String>{};
    await each(BackupFormat.documents, (row) {
      final id = backupField<String>(row, 'id');
      if (!seen.add(id)) throw kInvalidBackupRow;
      if (existing.contains(id)) {
        plan.skippedDocuments++;
        return;
      }
      final type = DocumentFileType.fromExtension(
        backupField<String>(row, 'file_type'),
      );
      final pageCount = backupField<int?>(row, 'page_count');
      if (type == null ||
          backupField<int>(row, 'is_in_vault') != 0 ||
          (pageCount != null && pageCount < 0)) {
        throw kInvalidBackupRow;
      }
      final storedFile = backupField<String>(row, 'file_path');
      final thumbnail = backupField<String?>(row, 'thumbnail_path');
      final filePath = claim(
        storedFile,
        StorageArea.documents,
        extension: type.extension,
      );
      plan.importedIds.add(id);
      plan.documents.add({
        'id': id,
        'name': sanitizeFileName(backupField<String>(row, 'name')),
        'file_path': filePath,
        'file_type': type.extension,
        'file_size': entries[BackupFormat.fileEntry(storedFile)],
        'page_count': pageCount,
        'thumbnail_path': thumbnail == null
            ? null
            : claim(thumbnail, StorageArea.thumbnails),
        'folder_id': backupField<String?>(row, 'folder_id'),
        'source': DocumentSource.fromDb(
          backupField<String>(row, 'source'),
        ).dbValue,
        'created_at': backupField<int>(row, 'created_at'),
        'updated_at': backupField<int>(row, 'updated_at'),
        'is_encrypted': backupField<int>(row, 'is_encrypted') == 0 ? 0 : 1,
        'deleted_at': backupField<int?>(row, 'deleted_at'),
      });
    });

    final pageGroups = <String, String>{};
    await each(BackupFormat.pages, (row) {
      final documentId = backupField<String>(row, 'document_id');
      final order = backupField<int>(row, 'page_order');
      if (!plan.importedIds.contains(documentId)) return;
      if (order < 0) throw kInvalidBackupRow;
      plan.pages.add({
        'id': _uuid.v4(),
        'document_id': documentId,
        'page_order': order,
        'image_path': claim(
          backupField<String>(row, 'image_path'),
          StorageArea.pages,
          group: pageGroups.putIfAbsent(documentId, _uuid.v4),
        ),
        'created_at': backupField<int>(row, 'created_at'),
      });
    });
    await each(BackupFormat.documentTags, (row) {
      final documentId = backupField<String>(row, 'document_id');
      final tagId = backupField<String>(row, 'tag_id');
      if (!plan.importedIds.contains(documentId)) return;
      plan.documentTags.add({'document_id': documentId, 'tag_id': tagId});
    });
    final favorites = <String>{};
    await each(BackupFormat.favorites, (row) {
      final documentId = backupField<String>(row, 'document_id');
      final createdAt = backupField<int>(row, 'created_at');
      if (!plan.importedIds.contains(documentId)) return;
      if (!favorites.add(documentId)) return;
      plan.favorites.add({
        'id': _uuid.v4(),
        'document_id': documentId,
        'created_at': createdAt,
      });
    });
  }

  /// Ids a restored document must not reuse: every document in `merge` mode,
  /// only the vault documents in `replace` mode (the others are replaced).
  Future<Set<String>> _idsOnDevice(RestoreMode mode) async {
    final rows = await _db.rawQuery(
      mode == RestoreMode.merge
          ? 'SELECT id FROM documents'
          : 'SELECT id FROM documents WHERE is_in_vault = 1',
    );
    return {for (final row in rows) row['id']! as String};
  }

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
