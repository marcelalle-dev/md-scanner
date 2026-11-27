import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/services/library/library_sql.dart';
import 'package:sqflite/sqflite.dart';

/// What a startup cleanup removed.
class CleanupReport extends Equatable {
  const CleanupReport({
    required this.tempFiles,
    required this.exportFiles,
    required this.orphanFiles,
    this.failedSteps = 0,
  });

  /// Stale working files purged from the `temp` area.
  final int tempFiles;

  /// Stale share/export files purged from the `exports` area.
  final int exportFiles;

  /// Files of `documents`, `pages` and `thumbnails` that no row referenced.
  final int orphanFiles;

  /// Cleanup steps cut short by a file system error; they resume next start.
  final int failedSteps;

  int get totalFiles => tempFiles + exportFiles + orphanFiles;

  @override
  List<Object?> get props => [tempFiles, exportFiles, orphanFiles, failedSteps];
}

/// Housekeeping of the private storage, meant to run once per app start.
class StorageMaintenance {
  StorageMaintenance({
    required this._db,
    required this._storage,
    required this._logger,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Working files normally die with their operation; a day covers a crash
  /// without touching an operation still running.
  static const Duration tempMaxAge = Duration(days: 1);

  /// Exports are handed to another app (share sheet), which may read them
  /// well after the user left the screen.
  static const Duration exportMaxAge = Duration(days: 7);

  /// A file is written before its row is committed: young unreferenced files
  /// may belong to a scan or an import in progress.
  static const Duration orphanMinAge = Duration(days: 1);

  static const List<StorageArea> _libraryAreas = [
    StorageArea.documents,
    StorageArea.pages,
    StorageArea.thumbnails,
  ];

  final Database _db;
  final FileStorage _storage;
  final AppLogger _logger;
  final DateTime Function() _clock;

  /// Purges stale `temp` and `exports` files and deletes the library files
  /// that no database row references any more.
  ///
  /// Each step is independent: a file system error ends that step only and is
  /// counted in [CleanupReport.failedSteps]. Fails only when the database
  /// cannot be read, in which case no library file is touched.
  Future<Result<CleanupReport>> runStartupCleanup() => guard(
    () async {
      final now = _clock();
      var failedSteps = 0;
      Future<int> step(Future<int> Function() run) async {
        try {
          return await run();
        } on FileSystemException {
          failedSteps++;
          return 0;
        }
      }

      final tempFiles = await step(
        () => _storage.purge(StorageArea.temp, olderThan: tempMaxAge, now: now),
      );
      final exportFiles = await step(
        () => _storage.purge(
          StorageArea.exports,
          olderThan: exportMaxAge,
          now: now,
        ),
      );
      final referenced = await _referencedPaths();
      final threshold = now.subtract(orphanMinAge);
      var orphanFiles = 0;
      for (final area in _libraryAreas) {
        orphanFiles += await step(
          () => _deleteOrphans(area, referenced, threshold),
        );
      }

      final report = CleanupReport(
        tempFiles: tempFiles,
        exportFiles: exportFiles,
        orphanFiles: orphanFiles,
        failedSteps: failedSteps,
      );
      _logger.info('storage.cleanup', {
        'temp_files': report.tempFiles,
        'export_files': report.exportFiles,
        'orphan_files': report.orphanFiles,
        'failed_steps': report.failedSteps,
      });
      return report;
    },
    onError: (error, _) => libraryFailure(error, StorageFailureKind.readError),
  );

  Future<Set<String>> _referencedPaths() async {
    final rows = await _db.rawQuery(
      'SELECT file_path AS path FROM documents '
      'UNION SELECT thumbnail_path FROM documents '
      'WHERE thumbnail_path IS NOT NULL '
      'UNION SELECT image_path FROM document_pages',
    );
    return {for (final row in rows) row['path']! as String};
  }

  Future<int> _deleteOrphans(
    StorageArea area,
    Set<String> referenced,
    DateTime threshold,
  ) async {
    final root = _storage.directoryOf(area);
    if (!await root.exists()) return 0;
    var deleted = 0;
    final directories = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        directories.add(entity);
        continue;
      }
      if (entity is! File) continue;
      if (referenced.contains(_storage.relativePath(entity.path))) continue;
      if ((await entity.lastModified()).isAfter(threshold)) continue;
      await entity.delete();
      deleted++;
    }
    await _removeEmptyGroups(directories, threshold);
    return deleted;
  }

  /// Drops the group folders a deleted document left empty, deepest first.
  /// Recent ones are kept: a writer may be about to fill them.
  Future<void> _removeEmptyGroups(
    List<Directory> directories,
    DateTime threshold,
  ) async {
    directories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in directories) {
      try {
        if ((await directory.stat()).modified.isAfter(threshold)) continue;
        if (await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
        }
      } on FileSystemException {
        continue;
      }
    }
  }
}

final storageMaintenanceProvider = Provider<StorageMaintenance>(
  (ref) => StorageMaintenance(
    db: ref.watch(databaseProvider),
    storage: ref.watch(fileStorageProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
