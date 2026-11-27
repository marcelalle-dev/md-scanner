import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/database/migrations.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:md_scanner/shared/repositories/sqlite_document_repository.dart';
import 'package:md_scanner/shared/services/backup/backup_archive.dart';
import 'package:md_scanner/shared/services/backup/backup_exporter.dart';
import 'package:md_scanner/shared/services/backup/backup_format.dart';
import 'package:md_scanner/shared/services/backup/backup_importer.dart';
import 'package:md_scanner/shared/services/library/library_sql.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

export 'package:md_scanner/shared/services/backup/backup_format.dart'
    show BackupSummary, RestoreMode, RestoreSummary;

/// Exports the library to a single zip archive and restores it.
///
/// Vault documents are never part of a backup: their encryption key is bound
/// to the device, so an exported copy could not be opened anywhere else and
/// a plain copy would defeat the vault. The summaries say how many were left
/// out.
///
/// Failures:
/// - `StorageFailure(notFound)`: the archive to restore does not exist;
/// - `StorageFailure(corrupted)`: not a backup, damaged, or holding an entry
///   that tries to leave the storage root;
/// - `ValidationFailure('backup_unsupported_version')`: written by a newer
///   version of the app;
/// - `ValidationFailure('backup_in_progress')`: an export or a restore is
///   already running;
/// - `StorageFailure(insufficientSpace / readError / writeError)`.
class BackupService {
  BackupService({
    required this._db,
    required this._storage,
    required this._logger,
    Uuid? uuid,
    DateTime Function()? clock,
    this._onLibraryChanged,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final Database _db;
  final FileStorage _storage;
  final AppLogger _logger;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Called after a restore so that open lists reload.
  final void Function()? _onLibraryChanged;

  bool _running = false;

  /// Writes the backup archive to [destinationPath] (an existing file is
  /// replaced) and reports what it holds.
  ///
  /// The archive only appears under its final name once complete; it is
  /// built off the UI thread, one file at a time. [onProgress] receives the
  /// fraction of bytes written, from 0 to 1.
  Future<Result<BackupSummary>> exportBackup({
    required String destinationPath,
    void Function(double fraction)? onProgress,
  }) => _exclusive(exporting: true, (workDir) async {
    final partial = File('$destinationPath.part');
    try {
      final plan = await BackupExporter(db: _db, storage: _storage).prepare(
        workDir,
        createdAt: _clock().toUtc(),
        schemaVersion: kMigrations.length,
      );
      await partial.parent.create(recursive: true);
      await writeBackupZip(
        zipPath: partial.path,
        sources: plan.sources,
        onProgress: onProgress,
      );
      final archive = await partial.rename(destinationPath);
      final manifest = plan.manifest;
      final summary = BackupSummary(
        documents: manifest.counts[BackupFormat.documents]!,
        folders: manifest.counts[BackupFormat.folders]!,
        tags: manifest.counts[BackupFormat.tags]!,
        files: manifest.files,
        archiveBytes: await archive.length(),
        skippedVaultDocuments: manifest.skippedVaultDocuments,
        skippedMissingFiles: plan.skippedMissingFiles,
      );
      _logger.info('backup.exported', {
        'documents': summary.documents,
        'folders': summary.folders,
        'files': summary.files,
        'skipped_vault': summary.skippedVaultDocuments,
        'skipped_missing': summary.skippedMissingFiles,
      });
      return summary;
    } catch (_) {
      try {
        if (await partial.exists()) await partial.delete();
      } on FileSystemException {
        // Nothing more can be done; the original error matters more.
      }
      rethrow;
    }
  });

  /// Restores the archive at [archivePath] into the library.
  ///
  /// The manifest and every entry name are validated before anything is
  /// written, and all rows are imported in one transaction: a failed restore
  /// leaves the library as it was. See [RestoreMode] for what each mode
  /// keeps. [onProgress] follows the extraction of the files.
  Future<Result<RestoreSummary>> restoreBackup({
    required String archivePath,
    required RestoreMode mode,
    void Function(double fraction)? onProgress,
  }) => _exclusive(exporting: false, (workDir) async {
    if (!await File(archivePath).exists()) throw kNotFound;
    final summary =
        await BackupImporter(db: _db, storage: _storage, uuid: _uuid).run(
          archivePath: archivePath,
          workDir: workDir,
          mode: mode,
          schemaVersion: kMigrations.length,
          onProgress: onProgress,
        );
    _onLibraryChanged?.call();
    _logger.info('backup.restored', {
      'mode': mode,
      'documents': summary.documentsImported,
      'skipped': summary.documentsSkipped,
      'folders': summary.foldersImported,
      'tags': summary.tagsImported,
      'files': summary.filesRestored,
    });
    return summary;
  });

  /// Runs [body] with a private working folder of the `temp` area, removed
  /// whatever the outcome, and refuses a second run in parallel: two
  /// restores, or an export during a restore, would see half-written data.
  Future<Result<T>> _exclusive<T>(
    Future<T> Function(Directory workDir) body, {
    required bool exporting,
  }) async {
    if (_running) {
      return const Err(ValidationFailure('backup_in_progress'));
    }
    _running = true;
    final workDir = Directory(
      p.join(
        _storage.directoryOf(StorageArea.temp).path,
        'backup_${_uuid.v4()}',
      ),
    );
    try {
      return await guard(() async {
        await workDir.create(recursive: true);
        return body(workDir);
      }, onError: (error, _) => _failureOf(error, exporting: exporting));
    } finally {
      try {
        if (await workDir.exists()) await workDir.delete(recursive: true);
      } on FileSystemException {
        // Left to the startup cleanup of the temp area.
      }
      _running = false;
    }
  }

  Failure? _failureOf(Object error, {required bool exporting}) {
    if (error is BackupArchiveException) {
      return error.toFailure(writing: exporting);
    }
    if (error is BackupFormatException) {
      return StorageFailure(
        StorageFailureKind.corrupted,
        debugMessage: 'backup_${error.reason}',
      );
    }
    // Malformed UTF-8 or JSON in a metadata file.
    if (error is FormatException) {
      return const StorageFailure(
        StorageFailureKind.corrupted,
        debugMessage: 'backup_metadata_unreadable',
      );
    }
    // While restoring, SQLite only refuses rows that break the schema's
    // constraints: the backup is the culprit, not the device.
    if (error is DatabaseException && !exporting) {
      return const StorageFailure(
        StorageFailureKind.corrupted,
        debugMessage: 'backup_rows_rejected',
      );
    }
    return libraryFailure(error, StorageFailureKind.readError);
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  final repository = ref.watch(documentRepositoryProvider);
  return BackupService(
    db: ref.watch(databaseProvider),
    storage: ref.watch(fileStorageProvider),
    logger: ref.watch(appLoggerProvider),
    onLibraryChanged: repository is SqliteDocumentRepository
        ? repository.notifyChanged
        : null,
  );
});
