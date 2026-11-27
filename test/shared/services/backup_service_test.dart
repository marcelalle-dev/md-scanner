import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/database/migrations.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/services/backup_service.dart';
import 'package:path/path.dart' as p;

import '../support/backup_fixture.dart';
import '../support/library_harness.dart';

void main() {
  late LibraryHarness lib;
  late AppLogger logger;
  late BackupService backup;
  late Directory destination;
  late String archivePath;

  /// The archive is written outside the app storage, as a backup the user
  /// saved elsewhere: `wipeAll` erases the exports area with everything else.
  setUp(() async {
    lib = await LibraryHarness.create();
    logger = AppLogger();
    backup = backupServiceFor(lib, logger: logger);
    destination = await Directory.systemTemp.createTemp('md_scanner_backup_');
    archivePath = p.join(destination.path, 'backup.zip');
  });
  tearDown(() async {
    await lib.dispose();
    await destination.delete(recursive: true);
  });

  Future<List<FileSystemEntity>> tempContent() =>
      lib.storage.directoryOf(StorageArea.temp).list().toList();

  group('exportBackup', () {
    test(
      'writes the manifest, the metadata and the files in one zip',
      () async {
        final seeded = await seedLibrary(lib);
        final fractions = <double>[];

        final summary = valueOf(
          await backup.exportBackup(
            destinationPath: archivePath,
            onProgress: fractions.add,
          ),
        );

        // Bail (file, thumbnail, 2 pages), Note and Vieux; the vault document
        // and its 3 files are left out.
        expect(summary.documents, 3);
        expect(summary.folders, 2);
        expect(summary.tags, 2);
        expect(summary.files, 6);
        expect(summary.skippedVaultDocuments, 1);
        expect(summary.skippedMissingFiles, 0);
        expect(summary.archiveBytes, File(archivePath).lengthSync());

        final archive = readArchive(archivePath);
        final manifest =
            jsonDecode(textOfEntry(archive, 'manifest.json'))
                as Map<String, Object?>;
        expect(manifest['app'], 'md_scanner');
        expect(manifest['formatVersion'], 1);
        expect(manifest['schemaVersion'], kMigrations.length);
        expect(manifest['createdAt'], '2026-11-27T09:30:00.000Z');
        expect(manifest['skippedVaultDocuments'], 1);
        expect(manifest['counts'], {
          'folders': 2,
          'tags': 2,
          'documents': 3,
          'document_pages': 2,
          'document_tags': 3,
          'ocr_results': 3,
          'favorites': 1,
          'files': 6,
        });

        final names = {for (final entry in archive) entry.name};
        expect(
          names,
          containsAll([
            'manifest.json',
            for (final table in const [
              'folders',
              'tags',
              'documents',
              'document_pages',
              'document_tags',
              'ocr_results',
              'favorites',
            ])
              'metadata/$table.jsonl',
            'files/${seeded.lease.filePath}',
            'files/${seeded.lease.thumbnailPath}',
            'files/${seeded.note.filePath}',
            'files/${seeded.old.filePath}',
          ]),
        );
        expect(names, hasLength(8 + 6));
        expect(
          archive.find('files/${seeded.lease.filePath}')!.content,
          lib.storage.file(seeded.lease.filePath).readAsBytesSync(),
        );

        expect(fractions, isNotEmpty);
        expect(fractions.last, 1.0);
        expect(fractions, orderedEquals([...fractions]..sort()));
      },
    );

    test('nothing of a vault document leaves the device', () async {
      final seeded = await seedLibrary(lib);

      valueOf(await backup.exportBackup(destinationPath: archivePath));

      final archive = readArchive(archivePath);
      expect(archive.where((entry) => entry.name.contains('vault/')), isEmpty);
      final metadata = [
        for (final entry in archive)
          if (entry.name.endsWith('.jsonl')) textOfEntry(archive, entry.name),
      ].join('\n');
      expect(metadata, isNot(contains(seeded.secret.id)));
      expect(metadata, isNot(contains('Secret')));
      expect(metadata, isNot(contains('code du coffre')));
      expect(metadata, isNot(contains('Privé')));
      expect(metadata, isNot(contains(seeded.secret.thumbnailPath)));
      expect(metadata, contains('Entre les soussignés'));
    });

    test('leaves out a document whose file is missing', () async {
      final seeded = await seedLibrary(lib);
      await lib.storage.delete(seeded.note.filePath);
      await lib.storage.delete(seeded.lease.thumbnailPath!);

      final summary = valueOf(
        await backup.exportBackup(destinationPath: archivePath),
      );

      expect(summary.documents, 2);
      expect(summary.skippedMissingFiles, 1);
      // Bail keeps its file and pages but loses its thumbnail reference.
      expect(summary.files, 4);
      final archive = readArchive(archivePath);
      final documents = textOfEntry(archive, 'metadata/documents.jsonl');
      expect(documents, isNot(contains(seeded.note.id)));
      expect(
        textOfEntry(archive, 'metadata/ocr_results.jsonl'),
        isNot(contains('Penser au virement')),
      );
      final lease = const LineSplitter()
          .convert(documents)
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .firstWhere((row) => row['id'] == seeded.lease.id);
      expect(lease['thumbnail_path'], isNull);
    });

    test('exports an empty library', () async {
      final summary = valueOf(
        await backup.exportBackup(destinationPath: archivePath),
      );

      expect(summary.documents, 0);
      expect(summary.files, 0);
      expect(
        valueOf(
          await backup.restoreBackup(
            archivePath: archivePath,
            mode: RestoreMode.replace,
          ),
        ).documentsImported,
        0,
      );
    });

    test('replaces a previous archive and leaves no working file', () async {
      await seedLibrary(lib);
      File(archivePath).writeAsStringSync('previous export');

      valueOf(await backup.exportBackup(destinationPath: archivePath));

      expect(readArchive(archivePath).find('manifest.json'), isNotNull);
      expect(File('$archivePath.part').existsSync(), isFalse);
      expect(await tempContent(), isEmpty);
    });

    test('fails without leaving a partial archive', () async {
      await seedLibrary(lib);
      final blocker = File(exportPathOf(lib, 'blocker'))
        ..writeAsStringSync('a file, not a folder');
      final target = p.join(blocker.path, 'backup.zip');

      final failure = failureIn(
        await backup.exportBackup(destinationPath: target),
      );

      expect(failure, isA<StorageFailure>());
      expect(File(target).existsSync(), isFalse);
      expect(File('$target.part').existsSync(), isFalse);
      expect(await tempContent(), isEmpty);
      expect(logger.events, isEmpty);
    });

    test('refuses to run twice at the same time', () async {
      await seedLibrary(lib);

      final first = backup.exportBackup(destinationPath: archivePath);
      final second = await backup.exportBackup(
        destinationPath: exportPathOf(lib, 'second.zip'),
      );

      expect(second, isValidationError('backup_in_progress'));
      expect((await first).isSuccess, isTrue);
      expect(File(exportPathOf(lib, 'second.zip')).existsSync(), isFalse);
      expect(
        (await backup.exportBackup(destinationPath: archivePath)).isSuccess,
        isTrue,
      );
    });
  });

  group('round trip', () {
    test('replace restores a wiped library exactly', () async {
      await seedLibrary(lib);
      final before = await snapshotOf(lib);
      valueOf(await backup.exportBackup(destinationPath: archivePath));
      valueOf(await lib.repository.wipeAll());
      expect(await lib.count('documents'), 0);
      var changes = 0;
      final subscription = lib.repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);
      final fractions = <double>[];

      final summary = valueOf(
        await backup.restoreBackup(
          archivePath: archivePath,
          mode: RestoreMode.replace,
          onProgress: fractions.add,
        ),
      );
      await pumpEventQueue();

      expect(
        summary,
        const RestoreSummary(
          mode: RestoreMode.replace,
          documentsImported: 3,
          documentsSkipped: 0,
          foldersImported: 2,
          tagsImported: 2,
          filesRestored: 6,
        ),
      );
      expect(await snapshotOf(lib), before);
      expect(await storedLibraryFilesOf(lib), await referencedFilesOf(lib));
      expect(await lib.count('favorites'), 1);
      expect(await lib.count('ocr_results'), 3);
      expect(changes, 1);
      expect(fractions.last, 1.0);
      expect(await tempContent(), isEmpty);
      expect(
        await lib.names(const DocumentQuery(search: 'cotonou')),
        ['Bail'],
        reason: 'restored OCR text is searchable',
      );
    });

    test('merge restores a wiped library exactly', () async {
      await seedLibrary(lib);
      final before = await snapshotOf(lib);
      valueOf(await backup.exportBackup(destinationPath: archivePath));
      valueOf(await lib.repository.wipeAll());

      final summary = valueOf(
        await backup.restoreBackup(
          archivePath: archivePath,
          mode: RestoreMode.merge,
        ),
      );

      expect(summary.documentsImported, 3);
      expect(summary.documentsSkipped, 0);
      expect(await snapshotOf(lib), before);
      expect(await storedLibraryFilesOf(lib), await referencedFilesOf(lib));
    });

    test('replace discards what the device held, except the vault', () async {
      final seeded = await seedLibrary(lib);
      final before = await snapshotOf(lib);
      valueOf(await backup.exportBackup(destinationPath: archivePath));

      valueOf(await lib.repository.rename(seeded.lease.id, 'Bail modifié'));
      valueOf(await lib.repository.deletePermanently([seeded.note.id]));
      valueOf(await lib.repository.createFolder('Ajouté après'));
      final intruder = await lib.addDocument('Intrus', pages: 1);
      valueOf(await lib.repository.setTags(intruder.id, ['Éphémère']));

      final summary = valueOf(
        await backup.restoreBackup(
          archivePath: archivePath,
          mode: RestoreMode.replace,
        ),
      );

      expect(summary.documentsImported, 3);
      expect(summary.documentsSkipped, 0);
      expect(await snapshotOf(lib), before);
      expect(lib.storage.file(intruder.filePath).existsSync(), isFalse);
      expect(lib.storage.file(seeded.lease.filePath).existsSync(), isFalse);

      // The vault document was not in the backup: it stays, with its file,
      // its folder (restored under the same id), its tag and its favorite.
      final secret = valueOf(await lib.repository.getById(seeded.secret.id));
      expect(secret.isInVault, isTrue);
      expect(secret.isFavorite, isTrue);
      expect(secret.folderId, seeded.works.id);
      expect(lib.storage.file(secret.filePath).existsSync(), isTrue);
      expect(
        valueOf(await lib.repository.tagsOf(secret.id)).map((tag) => tag.name),
        ['Privé'],
      );
      expect(await storedLibraryFilesOf(lib), await referencedFilesOf(lib));
    });

    test('merge only adds the documents the device does not have', () async {
      final seeded = await seedLibrary(lib);
      valueOf(await backup.exportBackup(destinationPath: archivePath));

      valueOf(await lib.repository.rename(seeded.lease.id, 'Bail modifié'));
      valueOf(await lib.repository.deletePermanently([seeded.note.id]));
      final added = await lib.addDocument('Ajouté après');
      final filesBefore = await storedLibraryFilesOf(lib);

      final summary = valueOf(
        await backup.restoreBackup(
          archivePath: archivePath,
          mode: RestoreMode.merge,
        ),
      );

      expect(
        summary,
        const RestoreSummary(
          mode: RestoreMode.merge,
          documentsImported: 1,
          documentsSkipped: 2,
          foldersImported: 0,
          tagsImported: 0,
          filesRestored: 1,
        ),
      );
      expect(
        await lib.names(
          const DocumentQuery(sort: DocumentSort(DocumentSortField.name)),
        ),
        ['Note', 'Bail modifié', 'Ajouté après'],
      );
      final note = valueOf(await lib.repository.getById(seeded.note.id));
      expect(note.filePath, isNot(seeded.note.filePath));
      expect(lib.storage.file(note.filePath).readAsBytesSync(), hasLength(50));
      expect(valueOf(await lib.ocr.textOf(note.id)), 'Penser au virement');
      expect(
        valueOf(await lib.repository.tagsOf(note.id)).map((tag) => tag.name),
        ['Banque'],
      );
      expect(valueOf(await lib.repository.getById(added.id)).name, added.name);
      expect(await lib.count('folders'), 2);
      expect(await lib.count('tags'), 3);
      expect(await storedLibraryFilesOf(lib), {...filesBefore, note.filePath});

      final again = valueOf(
        await backup.restoreBackup(
          archivePath: archivePath,
          mode: RestoreMode.merge,
        ),
      );
      expect(again.documentsImported, 0);
      expect(again.documentsSkipped, 3);
      expect(again.filesRestored, 0);
      expect(await storedLibraryFilesOf(lib), {...filesBefore, note.filePath});
    });

    test('merge on another device reuses folders and tags by name', () async {
      final seeded = await seedLibrary(lib);
      valueOf(await backup.exportBackup(destinationPath: archivePath));
      final other = await LibraryHarness.create(ownDatabase: true);
      addTearDown(other.dispose);
      final house = valueOf(await other.repository.createFolder('maison'));
      final local = await other.addDocument('Local', folderId: house.id);
      valueOf(await other.repository.setTags(local.id, ['banque']));

      final summary = valueOf(
        await backupServiceFor(
          other,
        ).restoreBackup(archivePath: archivePath, mode: RestoreMode.merge),
      );

      expect(summary.documentsImported, 3);
      expect(summary.foldersImported, 1, reason: 'only Travaux is new');
      expect(summary.tagsImported, 1, reason: 'only Logement is new');
      final lease = valueOf(await other.repository.getById(seeded.lease.id));
      expect(lease.folderId, house.id);
      expect(lease.isFavorite, isTrue);
      expect(valueOf(await other.repository.pagesOf(lease.id)), hasLength(2));
      final works = valueOf(await other.repository.folders(parentId: house.id));
      expect(works.single.name, 'Travaux');
      expect(
        valueOf(await other.repository.getById(seeded.old.id)).folderId,
        works.single.id,
      );
      expect(
        valueOf(await other.repository.allTags()).map((tag) => tag.name),
        unorderedEquals(['banque', 'Logement']),
      );
      expect(await storedLibraryFilesOf(other), await referencedFilesOf(other));
    });
  });

  test('logs counts and enum names only', () async {
    await seedLibrary(lib);

    valueOf(await backup.exportBackup(destinationPath: archivePath));
    valueOf(
      await backup.restoreBackup(
        archivePath: archivePath,
        mode: RestoreMode.merge,
      ),
    );

    expect(logger.events.map((event) => event.name), [
      'backup.exported',
      'backup.restored',
    ]);
    expect(logger.events.first.attributes, {
      'documents': 3,
      'folders': 2,
      'files': 6,
      'skipped_vault': 1,
      'skipped_missing': 0,
    });
    expect(logger.events.last.attributes, {
      'mode': 'merge',
      'documents': 0,
      'skipped': 3,
      'folders': 0,
      'tags': 0,
      'files': 0,
    });
  });

  test('backupServiceProvider serves the library of the app', () async {
    final seeded = await seedLibrary(lib);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(lib.database),
        fileStorageProvider.overrideWithValue(lib.storage),
        ...libraryRepositoryOverrides,
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(backupServiceProvider);
    valueOf(await service.exportBackup(destinationPath: archivePath));
    valueOf(await lib.repository.deletePermanently([seeded.note.id]));
    final liveDocuments = documentListProvider(const DocumentQuery());
    final listener = container.listen(liveDocuments, (_, _) {});
    addTearDown(listener.close);
    expect(await container.read(liveDocuments.future), hasLength(1));

    valueOf(
      await service.restoreBackup(
        archivePath: archivePath,
        mode: RestoreMode.merge,
      ),
    );
    await pumpEventQueue();

    expect(
      await container.read(liveDocuments.future),
      hasLength(2),
      reason: 'a restore refreshes the open lists',
    );
  });
}
