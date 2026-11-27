import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/migrations.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/services/backup/backup_format.dart';
import 'package:md_scanner/shared/services/backup_service.dart';
import 'package:path/path.dart' as p;

import '../support/backup_fixture.dart';
import '../support/library_harness.dart';

void main() {
  late LibraryHarness lib;
  late AppLogger logger;
  late BackupService backup;
  late SeededLibrary seeded;
  late String archivePath;
  late Map<String, Object?> libraryBefore;
  late Set<String> filesBefore;

  setUp(() async {
    lib = await LibraryHarness.create();
    logger = AppLogger();
    backup = backupServiceFor(lib, logger: logger);
    seeded = await seedLibrary(lib);
    archivePath = exportPathOf(lib);
    valueOf(await backup.exportBackup(destinationPath: archivePath));
    logger.clear();
    libraryBefore = await snapshotOf(lib);
    filesBefore = await storedLibraryFilesOf(lib);
  });
  tearDown(() => lib.dispose());

  /// A refused restore changes nothing: same rows, same files, no working
  /// file left in the temp area, nothing logged as restored.
  Future<void> expectLibraryUntouched() async {
    expect(await snapshotOf(lib), libraryBefore);
    expect(await storedLibraryFilesOf(lib), filesBefore);
    expect(
      await lib.storage.directoryOf(StorageArea.temp).list().toList(),
      isEmpty,
    );
    expect(logger.events, isEmpty);
    expect(
      valueOf(await lib.repository.getById(seeded.secret.id)).isInVault,
      isTrue,
    );
  }

  Future<Failure> restoreFailure(
    String path, {
    RestoreMode mode = RestoreMode.replace,
  }) async =>
      failureIn(await backup.restoreBackup(archivePath: path, mode: mode));

  Matcher corrupted(String reason) => isA<StorageFailure>()
      .having((failure) => failure.kind, 'kind', StorageFailureKind.corrupted)
      .having((failure) => failure.debugMessage, 'debugMessage', reason);

  String rewriteManifest(void Function(Map<String, Object?> manifest) change) =>
      tamperArchive(
        archivePath,
        (archive) => rewriteEntry(archive, 'manifest.json', (text) {
          final manifest = jsonDecode(text) as Map<String, Object?>;
          change(manifest);
          return jsonEncode(manifest);
        }),
      );

  /// Rewrites the rows of a metadata table, one decoded row at a time.
  String rewriteRows(
    String table,
    Map<String, Object?> Function(Map<String, Object?> row) change,
  ) => tamperArchive(
    archivePath,
    (archive) => rewriteEntry(
      archive,
      'metadata/$table.jsonl',
      (text) => const LineSplitter()
          .convert(text)
          .where((line) => line.isNotEmpty)
          .map(
            (line) =>
                jsonEncode(change(jsonDecode(line) as Map<String, Object?>)),
          )
          .join('\n'),
    ),
  );

  group('isSafeArchivePath', () {
    test('accepts plain relative paths', () {
      for (final name in const [
        'manifest.json',
        'metadata/documents.jsonl',
        'files/pages/group/a.jpg',
        'files/documents/',
      ]) {
        expect(isSafeArchivePath(name), isTrue, reason: name);
      }
    });

    test('rejects every way out of the extraction folder', () {
      for (final name in [
        '',
        '/',
        '../evil.pdf',
        'files/../../evil.pdf',
        'files/documents/..',
        './manifest.json',
        'files//a.pdf',
        '/etc/passwd',
        r'files\..\evil.pdf',
        r'C:\Windows\evil.dll',
        'C:/Windows/evil.dll',
        'file:///data/evil',
        'files/a\u0000.pdf',
        'files/a\n.pdf',
        'files/${'a' * 1100}',
      ]) {
        expect(isSafeArchivePath(name), isFalse, reason: name);
      }
    });
  });

  group('restoreBackup refuses', () {
    test('an archive that does not exist', () async {
      final missing = exportPathOf(lib, 'missing.zip');

      expect(
        await backup.restoreBackup(
          archivePath: missing,
          mode: RestoreMode.merge,
        ),
        isNotFound,
      );
      await expectLibraryUntouched();
    });

    test('a file that is not a zip', () async {
      final path = exportPathOf(lib, 'photo.zip');
      File(path).writeAsBytesSync(List.generate(4096, (index) => index % 251));

      expect(await restoreFailure(path), corrupted('backup_unreadable'));
      await expectLibraryUntouched();
    });

    test('a truncated archive', () async {
      final bytes = File(archivePath).readAsBytesSync();
      final path = exportPathOf(lib, 'truncated.zip');
      File(path).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));

      expect(
        await restoreFailure(path),
        isA<StorageFailure>().having(
          (failure) => failure.kind,
          'kind',
          StorageFailureKind.corrupted,
        ),
      );
      await expectLibraryUntouched();
    });

    test('a zip that is not a backup', () async {
      final path = exportPathOf(lib, 'other.zip');
      File(path).writeAsBytesSync(
        ZipEncoder().encodeBytes(
          Archive()..add(ArchiveFile.string('readme.txt', 'hello')),
        ),
      );

      expect(await restoreFailure(path), corrupted('backup_entries_missing'));
      await expectLibraryUntouched();
    });

    for (final (label, name) in const [
      ('a parent traversal', '../evil.txt'),
      ('a traversal below files/', 'files/documents/../../../evil.txt'),
      ('an absolute path', '/evil.txt'),
      ('a drive path', 'C:/evil.txt'),
    ]) {
      test('an entry escaping the storage root: $label', () async {
        final path = tamperArchive(
          archivePath,
          (archive) => archive.add(ArchiveFile.string(name, 'escaped')),
        );
        final outside = File(p.join(lib.storage.root.parent.path, 'evil.txt'));
        addTearDown(() {
          if (outside.existsSync()) outside.deleteSync();
        });

        for (final mode in RestoreMode.values) {
          expect(
            await restoreFailure(path, mode: mode),
            corrupted('backup_unsafe_entry'),
          );
        }
        expect(outside.existsSync(), isFalse);
        expect(
          File(p.join(lib.storage.root.path, 'evil.txt')).existsSync(),
          isFalse,
        );
        await expectLibraryUntouched();
      });
    }

    test('a row pointing outside the storage root', () async {
      final path = rewriteRows(
        'documents',
        (row) => row['id'] == seeded.note.id
            ? {...row, 'file_path': '../../outside.txt'}
            : row,
      );

      expect(await restoreFailure(path), corrupted('backup_row_invalid'));
      await expectLibraryUntouched();
    });

    test('a row pointing at a file the archive does not hold', () async {
      final path = rewriteRows(
        'document_pages',
        (row) => {...row, 'image_path': 'pages/scan/absent.jpg'},
      );

      expect(await restoreFailure(path), corrupted('backup_row_invalid'));
      await expectLibraryUntouched();
    });

    test('a backup written by a newer format', () async {
      final path = rewriteManifest((manifest) => manifest['formatVersion'] = 2);

      expect(
        await restoreFailure(path),
        const ValidationFailure('backup_unsupported_version'),
      );
      await expectLibraryUntouched();
    });

    test('a backup of a newer database schema', () async {
      final path = rewriteManifest(
        (manifest) => manifest['schemaVersion'] = kMigrations.length + 1,
      );

      expect(
        await restoreFailure(path, mode: RestoreMode.merge),
        const ValidationFailure('backup_unsupported_version'),
      );
      await expectLibraryUntouched();
    });

    test('a manifest that is missing, malformed or incomplete', () async {
      final missing = tamperArchive(
        archivePath,
        (archive) => archive.removeFile(archive.find('manifest.json')!),
        name: 'missing_manifest.zip',
      );
      final malformed = tamperArchive(
        archivePath,
        (archive) => rewriteEntry(archive, 'manifest.json', (_) => '{"app":'),
        name: 'malformed_manifest.zip',
      );
      final foreign = rewriteManifest((manifest) => manifest['app'] = 'other');

      expect(
        await restoreFailure(missing),
        corrupted('backup_entries_missing'),
      );
      expect(
        await restoreFailure(malformed),
        corrupted('backup_manifest_invalid'),
      );
      expect(
        await restoreFailure(foreign),
        corrupted('backup_manifest_invalid'),
      );
      final incomplete = rewriteManifest(
        (manifest) =>
            (manifest['counts']! as Map<String, Object?>).remove('documents'),
      );
      expect(
        await restoreFailure(incomplete),
        corrupted('backup_manifest_invalid'),
      );
      await expectLibraryUntouched();
    });

    test('counts that do not match the content', () async {
      final rows = rewriteManifest(
        (manifest) =>
            (manifest['counts']! as Map<String, Object?>)['documents'] = 7,
      );
      expect(
        await restoreFailure(rows),
        corrupted('backup_row_count_mismatch'),
      );

      final files = tamperArchive(
        archivePath,
        (archive) => archive.add(
          ArchiveFile.bytes('files/documents/extra.pdf', [1, 2, 3]),
        ),
        name: 'extra_file.zip',
      );
      expect(
        await restoreFailure(files),
        corrupted('backup_file_count_mismatch'),
      );
      await expectLibraryUntouched();
    });

    test('rows of the wrong shape', () async {
      final cases = {
        'unknown file type': rewriteRows(
          'documents',
          (row) => {...row, 'file_type': 'exe'},
        ),
        'vault document': rewriteRows(
          'documents',
          (row) => {...row, 'is_in_vault': 1},
        ),
        'mistyped date': rewriteRows(
          'documents',
          (row) => {...row, 'created_at': 'yesterday'},
        ),
        'missing column': rewriteRows(
          'folders',
          (row) => {...row}..remove('name'),
        ),
        'duplicated id': rewriteRows(
          'documents',
          (row) => {...row, 'id': seeded.lease.id},
        ),
      };

      for (final MapEntry(key: label, value: path) in cases.entries) {
        expect(
          await restoreFailure(path),
          corrupted('backup_row_invalid'),
          reason: label,
        );
      }
      final notJson = tamperArchive(
        archivePath,
        (archive) =>
            rewriteEntry(archive, 'metadata/tags.jsonl', (_) => 'not json\n'),
        name: 'not_json.zip',
      );
      expect(await restoreFailure(notJson), corrupted('backup_row_invalid'));
      await expectLibraryUntouched();
    });

    test('a folder tree that is not a tree', () async {
      final path = rewriteRows(
        'folders',
        (row) => row['id'] == seeded.house.id
            ? {...row, 'parent_id': seeded.works.id}
            : row,
      );

      expect(await restoreFailure(path), corrupted('backup_row_invalid'));
      await expectLibraryUntouched();
    });
  });

  group('a restore failing while rows are written', () {
    /// The link table names a tag the backup does not define: the error only
    /// shows up inside the transaction, after `replace` emptied the library.
    String archiveWithUnknownTag() => rewriteRows(
      'document_tags',
      (row) => {...row, 'tag_id': 'unknown-tag'},
    );

    test('rolls a replace back and removes the extracted files', () async {
      expect(
        await restoreFailure(archiveWithUnknownTag()),
        corrupted('backup_row_invalid'),
      );
      await expectLibraryUntouched();
    });

    test('rolls a merge back and removes the extracted files', () async {
      valueOf(await lib.repository.deletePermanently([seeded.note.id]));
      libraryBefore = await snapshotOf(lib);
      filesBefore = await storedLibraryFilesOf(lib);

      expect(
        await restoreFailure(archiveWithUnknownTag(), mode: RestoreMode.merge),
        corrupted('backup_row_invalid'),
      );
      await expectLibraryUntouched();
    });

    test('does not notify the library', () async {
      var changes = 0;
      final subscription = lib.repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);

      await restoreFailure(archiveWithUnknownTag());
      await pumpEventQueue();

      expect(changes, 0);
    });

    test('lets the next restore run', () async {
      await restoreFailure(archiveWithUnknownTag());

      expect(
        (await backup.restoreBackup(
          archivePath: archivePath,
          mode: RestoreMode.replace,
        )).isSuccess,
        isTrue,
      );
      expect(await snapshotOf(lib), libraryBefore);
    });
  });
}
