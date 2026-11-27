import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/services/backup/backup_archive.dart';
import 'package:md_scanner/shared/services/backup/backup_format.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Everything the zip step needs, plus the figures of the summary.
class ExportPlan {
  const ExportPlan({
    required this.sources,
    required this.manifest,
    required this.skippedMissingFiles,
  });

  /// Manifest first, then the metadata, then the files.
  final List<ZipSource> sources;
  final BackupManifest manifest;
  final int skippedMissingFiles;
}

/// Reads the exportable library and writes its metadata as JSON Lines.
///
/// Rows are read by pages and written straight to disk, so the OCR text of a
/// large library never sits in memory at once.
class BackupExporter {
  BackupExporter({required this._db, required this._storage});

  static const int _pageSize = 200;

  /// Rows of the documents that are exported: outside the vault, since the
  /// key of a vault document cannot leave the device.
  static const String _exportable =
      'document_id IN (SELECT id FROM documents WHERE is_in_vault = 0)';

  final Database _db;
  final FileStorage _storage;

  /// Writes `manifest.json` and one `.jsonl` file per table into [workDir].
  ///
  /// Runs inside one transaction so that the rows form a consistent
  /// snapshot. A document whose file is missing is left out with all its
  /// dependents; a missing thumbnail or page image only drops that reference.
  Future<ExportPlan> prepare(
    Directory workDir, {
    required DateTime createdAt,
    required int schemaVersion,
  }) => _db.transaction((txn) async {
    final files = <ZipSource>[];
    final included = <String>{};
    final exported = <String>{};
    final usedTags = <String>{};
    final counts = <String, int>{};
    var missing = 0;

    Future<void> table(
      String name,
      String sql,
      FutureOr<Map<String, Object?>?> Function(Map<String, Object?> row) keep,
    ) async {
      final target = File(p.join(workDir.path, '$name.jsonl'));
      counts[name] = await _writeRows(txn, target, sql, keep);
    }

    /// Adds a stored file to the archive; false when it cannot be exported:
    /// unusable path, missing file, or file already carried for another row
    /// (an archive entry backs exactly one reference).
    Future<bool> include(String relativePath) async {
      if (!isSafeArchivePath(relativePath) || relativePath.endsWith('/')) {
        return false;
      }
      final file = _storage.file(relativePath);
      if (!await file.exists() || !included.add(relativePath)) return false;
      files.add(
        ZipSource(
          path: file.path,
          entry: BackupFormat.fileEntry(relativePath),
          compress: relativePath.toLowerCase().endsWith('.txt'),
        ),
      );
      return true;
    }

    bool ofExported(Map<String, Object?> row) =>
        exported.contains(row['document_id']);

    await table(
      BackupFormat.documents,
      'SELECT * FROM documents WHERE is_in_vault = 0 ORDER BY rowid',
      (row) async {
        if (!await include(row['file_path']! as String)) {
          missing++;
          return null;
        }
        exported.add(row['id']! as String);
        final thumbnail = row['thumbnail_path'] as String?;
        if (thumbnail == null || await include(thumbnail)) return row;
        return {...row, 'thumbnail_path': null};
      },
    );
    await table(
      BackupFormat.pages,
      'SELECT * FROM document_pages WHERE $_exportable ORDER BY rowid',
      (row) async =>
          ofExported(row) && await include(row['image_path']! as String)
          ? row
          : null,
    );
    await table(
      BackupFormat.documentTags,
      'SELECT * FROM document_tags WHERE $_exportable ORDER BY rowid',
      (row) {
        if (!ofExported(row)) return null;
        usedTags.add(row['tag_id']! as String);
        return row;
      },
    );
    await table(
      BackupFormat.tags,
      'SELECT * FROM tags ORDER BY rowid',
      (row) => usedTags.contains(row['id']) ? row : null,
    );
    await table(
      BackupFormat.folders,
      'SELECT * FROM folders ORDER BY rowid',
      (row) => row,
    );
    await table(
      BackupFormat.ocrResults,
      'SELECT * FROM ocr_results WHERE $_exportable ORDER BY rowid',
      (row) => ofExported(row) ? row : null,
    );
    await table(
      BackupFormat.favorites,
      'SELECT * FROM favorites WHERE $_exportable ORDER BY rowid',
      (row) => ofExported(row) ? row : null,
    );

    final vault = await txn.rawQuery(
      'SELECT COUNT(*) AS total FROM documents WHERE is_in_vault = 1',
    );
    final manifest = BackupManifest(
      formatVersion: BackupFormat.version,
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      counts: counts,
      files: files.length,
      skippedVaultDocuments: vault.first['total']! as int,
    );
    final manifestFile = File(p.join(workDir.path, BackupFormat.manifestEntry));
    await manifestFile.writeAsString(manifest.encode(), flush: true);

    return ExportPlan(
      manifest: manifest,
      skippedMissingFiles: missing,
      sources: [
        ZipSource(
          path: manifestFile.path,
          entry: BackupFormat.manifestEntry,
          compress: true,
        ),
        for (final name in BackupFormat.tables)
          ZipSource(
            path: p.join(workDir.path, '$name.jsonl'),
            entry: BackupFormat.tableEntry(name),
            compress: true,
          ),
        ...files,
      ],
    );
  });

  /// Streams the rows of [sql] through [keep] into [target], one JSON object
  /// per line, and returns how many were written.
  Future<int> _writeRows(
    DatabaseExecutor db,
    File target,
    String sql,
    FutureOr<Map<String, Object?>?> Function(Map<String, Object?> row) keep,
  ) async {
    final sink = target.openWrite();
    var written = 0;
    try {
      for (var offset = 0; ; offset += _pageSize) {
        final rows = await db.rawQuery('$sql LIMIT ? OFFSET ?', [
          _pageSize,
          offset,
        ]);
        for (final row in rows) {
          final kept = await keep(row);
          if (kept == null) continue;
          sink.writeln(jsonEncode(kept));
          written++;
        }
        await sink.flush();
        if (rows.length < _pageSize) break;
      }
    } finally {
      await sink.close();
    }
    return written;
  }
}
