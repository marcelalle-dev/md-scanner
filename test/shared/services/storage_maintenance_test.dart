import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/services/storage_maintenance.dart';
import 'package:path/path.dart' as p;

import '../support/library_harness.dart';

void main() {
  /// The cleanup runs "a month from now": folders created by the test are
  /// then old, and each file gets an explicit age relative to that date.
  final cleanupDate = DateTime.now().add(const Duration(days: 30));

  late LibraryHarness lib;
  late AppLogger logger;
  late StorageMaintenance maintenance;

  setUp(() async {
    lib = await LibraryHarness.create();
    logger = AppLogger();
    maintenance = StorageMaintenance(
      db: lib.db,
      storage: lib.storage,
      logger: logger,
      clock: () => cleanupDate,
    );
  });
  tearDown(() => lib.dispose());

  Future<void> age(String relativePath, Duration age) =>
      lib.storage.file(relativePath).setLastModified(cleanupDate.subtract(age));

  Future<String> aged(
    StorageArea area,
    Duration fileAge, {
    String? group,
  }) async {
    final path = await lib.writeFile(area, group: group);
    await age(path, fileAge);
    return path;
  }

  const old = Duration(days: 2);
  const recent = Duration(hours: 2);

  test('purges stale temp and export files only', () async {
    final staleTemp = await aged(StorageArea.temp, old);
    final freshTemp = await aged(StorageArea.temp, recent);
    final staleExport = await aged(
      StorageArea.exports,
      const Duration(days: 8),
    );
    final freshExport = await aged(
      StorageArea.exports,
      const Duration(days: 6),
    );

    final report = valueOf(await maintenance.runStartupCleanup());

    expect(
      report,
      const CleanupReport(tempFiles: 1, exportFiles: 1, orphanFiles: 0),
    );
    expect(await lib.storage.exists(staleTemp), isFalse);
    expect(await lib.storage.exists(freshTemp), isTrue);
    expect(await lib.storage.exists(staleExport), isFalse);
    expect(await lib.storage.exists(freshExport), isTrue);
  });

  test('deletes old files that no row references', () async {
    final document = await lib.addDocument('Gardé', pages: 2, thumbnail: true);
    final pages = valueOf(await lib.repository.pagesOf(document.id));
    final referenced = [
      document.filePath,
      document.thumbnailPath!,
      for (final page in pages) page.imagePath,
    ];
    for (final path in referenced) {
      await age(path, const Duration(days: 400));
    }
    final orphans = [
      await aged(StorageArea.documents, old),
      await aged(StorageArea.thumbnails, old),
      await aged(StorageArea.pages, old, group: 'scan'),
      await aged(StorageArea.pages, old, group: 'abandoned'),
    ];
    final inProgress = [
      await aged(StorageArea.documents, recent),
      await aged(StorageArea.pages, recent, group: 'current'),
    ];
    final untouchedAreas = [
      await aged(StorageArea.vault, old),
      await aged(StorageArea.sessions, old, group: 'session'),
    ];

    final report = valueOf(await maintenance.runStartupCleanup());

    expect(report.orphanFiles, 4);
    expect(report.totalFiles, 4);
    expect(report.failedSteps, 0);
    for (final path in orphans) {
      expect(await lib.storage.exists(path), isFalse, reason: path);
    }
    for (final path in [...referenced, ...inProgress, ...untouchedAreas]) {
      expect(await lib.storage.exists(path), isTrue, reason: path);
    }
    final pagesRoot = lib.storage.directoryOf(StorageArea.pages).path;
    expect(
      await Directory(p.join(pagesRoot, 'abandoned')).exists(),
      isFalse,
      reason: 'a group folder left empty is removed',
    );
    expect(await Directory(p.join(pagesRoot, 'scan')).exists(), isTrue);
    expect(await Directory(p.join(pagesRoot, 'current')).exists(), isTrue);
  });

  test('files of trashed and vault documents are still referenced', () async {
    final trashed = await lib.addDocument('Jeté', thumbnail: true);
    await lib.repository.moveToTrash([trashed.id]);
    final secret = await lib.moveToVault(
      await lib.addDocument('Coffre', pages: 1, thumbnail: true),
    );
    for (final area in StorageArea.values) {
      for (final path in await lib.filesIn(area)) {
        await age(path, const Duration(days: 90));
      }
    }
    final before = {
      for (final area in StorageArea.values) area: await lib.filesIn(area),
    };

    final report = valueOf(await maintenance.runStartupCleanup());

    expect(report.totalFiles, 0);
    for (final area in StorageArea.values) {
      expect(await lib.filesIn(area), before[area], reason: area.name);
    }
    expect(await lib.storage.exists(secret.filePath), isTrue);
  });

  test('logs counts only', () async {
    await aged(StorageArea.temp, old);
    await aged(StorageArea.documents, old);
    await aged(StorageArea.documents, old);

    await maintenance.runStartupCleanup();

    final event = logger.events.single;
    expect(event.name, 'storage.cleanup');
    expect(event.level, LogLevel.info);
    expect(event.attributes, {
      'temp_files': 1,
      'export_files': 0,
      'orphan_files': 2,
      'failed_steps': 0,
    });
  });

  test('touches no library file when the database cannot be read', () async {
    final orphan = await aged(StorageArea.documents, old);
    await lib.database.close();

    final result = await maintenance.runStartupCleanup();

    expect(
      failureIn(result),
      isA<StorageFailure>().having(
        (failure) => failure.kind,
        'kind',
        StorageFailureKind.readError,
      ),
    );
    expect(await lib.storage.exists(orphan), isTrue);
    expect(logger.events, isEmpty);
  });

  test('storageMaintenanceProvider builds the service from the app', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(lib.database),
        fileStorageProvider.overrideWithValue(lib.storage),
      ],
    );
    addTearDown(container.dispose);
    await lib.writeFile(StorageArea.temp);

    final report = valueOf(
      await container.read(storageMaintenanceProvider).runStartupCleanup(),
    );

    expect(report.totalFiles, 0, reason: 'a fresh temp file is kept');
    expect(
      container.read(appLoggerProvider).events.single.name,
      'storage.cleanup',
    );
  });
}
