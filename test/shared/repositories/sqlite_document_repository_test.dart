import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:path/path.dart' as p;

import '../support/library_harness.dart';

void main() {
  late LibraryHarness lib;

  setUp(() async => lib = await LibraryHarness.create());
  tearDown(() => lib.dispose());

  group('register', () {
    test(
      'stores the metadata, measures the size and keeps the pages',
      () async {
        final events = <void>[];
        final subscription = lib.repository.changes.listen(events.add);
        addTearDown(subscription.cancel);

        final document = await lib.addDocument(
          'Contrat',
          size: 321,
          pages: 3,
          thumbnail: true,
        );
        await pumpEventQueue();

        expect(document.name, 'Contrat');
        expect(document.fileSize, 321);
        expect(document.fileType, DocumentFileType.pdf);
        expect(document.source, DocumentSource.scan);
        expect(document.pageCount, 3);
        expect(document.createdAt, lib.now);
        expect(document.createdAt.isUtc, isTrue);
        expect(document.updatedAt, document.createdAt);
        expect(document.isFavorite, isFalse);
        expect(document.isInTrash, isFalse);
        expect(document.thumbnailPath, startsWith('thumbnails/'));
        expect(events, hasLength(1));

        final pages = valueOf(await lib.repository.pagesOf(document.id));
        expect(pages.map((page) => page.pageOrder), [0, 1, 2]);
        expect(pages.every((page) => page.documentId == document.id), isTrue);
        expect(
          pages.map((page) => page.imagePath).toSet(),
          await lib.filesIn(StorageArea.pages),
        );
        expect(valueOf(await lib.repository.getById(document.id)), document);
      },
    );

    test('fails with notFound when the file is missing', () async {
      final events = <void>[];
      final subscription = lib.repository.changes.listen(events.add);
      addTearDown(subscription.cancel);

      final result = await lib.repository.register(
        const NewDocument(
          name: 'Fantôme',
          filePath: 'documents/absent.pdf',
          fileType: DocumentFileType.pdf,
          source: DocumentSource.scan,
        ),
      );
      await pumpEventQueue();

      expect(result, isNotFound);
      expect(await lib.count('documents'), 0);
      expect(events, isEmpty);
    });

    test('refuses a path that leaves the storage root', () async {
      final outside = File(p.join(lib.storage.root.parent.path, 'leak.pdf'));
      await outside.writeAsBytes([1, 2, 3]);
      addTearDown(outside.delete);

      final result = await lib.repository.register(
        const NewDocument(
          name: 'Fuite',
          filePath: '../leak.pdf',
          fileType: DocumentFileType.pdf,
          source: DocumentSource.import,
        ),
      );

      expect(result, isNotFound);
      expect(await lib.count('documents'), 0);
    });

    test('sanitizes the name and falls back when nothing is left', () async {
      final cleaned = await lib.addDocument('  Facture: 2024/03?  ');
      final fallback = await lib.addDocument(' /// ');

      expect(cleaned.name, 'Facture 2024 03');
      expect(fallback.name, 'document');
    });

    test('numbers a name already used in the same folder', () async {
      final folder = valueOf(await lib.repository.createFolder('Banque'));

      final first = await lib.addDocument('Relevé');
      final second = await lib.addDocument('relevé');
      final third = await lib.addDocument('Relevé');
      final elsewhere = await lib.addDocument('Relevé', folderId: folder.id);

      expect(first.name, 'Relevé');
      expect(second.name, 'relevé (2)');
      expect(third.name, 'Relevé (3)');
      expect(elsewhere.name, 'Relevé');
    });

    test('ignores trashed and vault documents when numbering', () async {
      final trashed = await lib.addDocument('Passeport');
      await lib.repository.moveToTrash([trashed.id]);
      await lib.moveToVault(await lib.addDocument('Passeport'));

      expect((await lib.addDocument('Passeport')).name, 'Passeport');
    });

    test('keeps a numbered name within the length limit', () async {
      final long = 'a' * 80;
      await lib.addDocument(long);

      final second = await lib.addDocument(long);

      expect(second.name, '${'a' * 76} (2)');
      expect(second.name.length, 80);
    });

    test('fails with notFound for an unknown folder', () async {
      final path = await lib.writeFile(StorageArea.documents);

      final result = await lib.repository.register(
        NewDocument(
          name: 'Orphelin',
          filePath: path,
          fileType: DocumentFileType.pdf,
          source: DocumentSource.scan,
          folderId: 'nowhere',
        ),
      );

      expect(result, isNotFound);
      expect(await lib.count('documents'), 0);
    });

    test('refuses to register the same file twice', () async {
      final first = await lib.addDocument('Original');

      final result = await lib.repository.register(
        NewDocument(
          name: 'Copie',
          filePath: first.filePath,
          fileType: DocumentFileType.pdf,
          source: DocumentSource.scan,
        ),
      );

      expect(result, isAlreadyExists);
      expect(await lib.count('documents'), 1);
    });
  });

  group('importExternalFile', () {
    late Directory outside;

    setUp(() async {
      outside = await Directory.systemTemp.createTemp('md_scanner_import_');
    });
    tearDown(() => outside.delete(recursive: true));

    Future<String> external(String name, {int size = 64}) async {
      final file = File(p.join(outside.path, name));
      await file.writeAsBytes(List.filled(size, 9));
      return file.path;
    }

    test('copies the file into the documents area', () async {
      final source = await external('Photo de vacances.JPEG', size: 77);

      final document = valueOf(await lib.repository.importExternalFile(source));

      expect(document.name, 'Photo de vacances');
      expect(document.fileType, DocumentFileType.jpg);
      expect(document.fileSize, 77);
      expect(document.source, DocumentSource.import);
      expect(document.filePath, startsWith('documents/'));
      expect(document.filePath, endsWith('.jpg'));
      expect(await lib.storage.exists(document.filePath), isTrue);
      expect(await File(source).exists(), isTrue);
    });

    test('uses the given name, folder and source', () async {
      final folder = valueOf(await lib.repository.createFolder('Impôts'));
      final source = await external('scan_0001.pdf');

      final document = valueOf(
        await lib.repository.importExternalFile(
          source,
          name: 'Avis 2025',
          folderId: folder.id,
          source: DocumentSource.pdfTool,
        ),
      );

      expect(document.name, 'Avis 2025');
      expect(document.folderId, folder.id);
      expect(document.source, DocumentSource.pdfTool);
    });

    test('rejects an unsupported extension without copying', () async {
      final result = await lib.repository.importExternalFile(
        await external('archive.zip'),
      );

      expect(result, isValidationError('unsupported_file_type'));
      expect(await lib.filesIn(StorageArea.documents), isEmpty);
    });

    test('fails with notFound when the source is missing', () async {
      final result = await lib.repository.importExternalFile(
        p.join(outside.path, 'absent.pdf'),
      );

      expect(result, isNotFound);
      expect(await lib.filesIn(StorageArea.documents), isEmpty);
    });

    test('removes the copy when the database insert fails', () async {
      final result = await lib.repository.importExternalFile(
        await external('note.txt'),
        folderId: 'nowhere',
      );

      expect(result, isNotFound);
      expect(await lib.filesIn(StorageArea.documents), isEmpty);
      expect(await lib.count('documents'), 0);
    });
  });

  group('rename', () {
    test('sanitizes the name and moves the update date', () async {
      final document = await lib.addDocument('Brouillon');

      final renamed = valueOf(
        await lib.repository.rename(document.id, ' Final: v2 '),
      );

      expect(renamed.name, 'Final v2');
      expect(renamed.updatedAt.isAfter(document.updatedAt), isTrue);
      expect(renamed.createdAt, document.createdAt);
    });

    test('numbers a name taken by another document', () async {
      await lib.addDocument('Facture');
      final other = await lib.addDocument('Scan');

      final renamed = valueOf(await lib.repository.rename(other.id, 'facture'));
      final unchanged = valueOf(
        await lib.repository.rename(other.id, 'facture (2)'),
      );

      expect(renamed.name, 'facture (2)');
      expect(unchanged.updatedAt, renamed.updatedAt);
    });

    test('rejects a blank name and an unknown id', () async {
      final document = await lib.addDocument('Garde');

      expect(
        await lib.repository.rename(document.id, ' ?? '),
        isValidationError('empty_name'),
      );
      expect(await lib.repository.rename('unknown', 'Nom'), isNotFound);
      expect(valueOf(await lib.repository.getById(document.id)), document);
    });
  });

  group('replaceFile', () {
    test('points at the new file and deletes the previous ones', () async {
      final document = await lib.addDocument('Rapport', thumbnail: true);
      final newFile = await lib.writeFile(
        StorageArea.documents,
        extension: 'docx',
        size: 99,
      );
      final newThumbnail = await lib.writeFile(
        StorageArea.thumbnails,
        extension: 'png',
      );

      final updated = valueOf(
        await lib.repository.replaceFile(
          document.id,
          newFilePath: newFile,
          fileType: DocumentFileType.docx,
          pageCount: 4,
          thumbnailPath: newThumbnail,
        ),
      );

      expect(updated.filePath, newFile);
      expect(updated.fileType, DocumentFileType.docx);
      expect(updated.fileSize, 99);
      expect(updated.pageCount, 4);
      expect(updated.thumbnailPath, newThumbnail);
      expect(updated.updatedAt.isAfter(document.updatedAt), isTrue);
      expect(await lib.filesIn(StorageArea.documents), {newFile});
      expect(await lib.filesIn(StorageArea.thumbnails), {newThumbnail});
    });

    test('keeps everything when the new file is missing', () async {
      final document = await lib.addDocument('Rapport');

      final result = await lib.repository.replaceFile(
        document.id,
        newFilePath: 'documents/absent.pdf',
        fileType: DocumentFileType.pdf,
      );

      expect(result, isNotFound);
      expect(valueOf(await lib.repository.getById(document.id)), document);
      expect(await lib.storage.exists(document.filePath), isTrue);
    });

    test(
      'fails for an unknown id or a file owned by another document',
      () async {
        final first = await lib.addDocument('Un');
        final second = await lib.addDocument('Deux');
        final spare = await lib.writeFile(StorageArea.documents);

        expect(
          await lib.repository.replaceFile(
            'unknown',
            newFilePath: spare,
            fileType: DocumentFileType.pdf,
          ),
          isNotFound,
        );
        expect(
          await lib.repository.replaceFile(
            first.id,
            newFilePath: second.filePath,
            fileType: DocumentFileType.pdf,
          ),
          isAlreadyExists,
        );
        expect(await lib.storage.exists(spare), isTrue);
        expect(await lib.storage.exists(first.filePath), isTrue);
      },
    );
  });

  group('moveToFolder', () {
    test('moves documents into a folder and back to the root', () async {
      final folder = valueOf(await lib.repository.createFolder('Santé'));
      final a = await lib.addDocument('Ordonnance');
      final b = await lib.addDocument('Analyse');

      valueOf(await lib.repository.moveToFolder([a.id, b.id, a.id], folder.id));
      expect(
        await lib.names(
          DocumentQuery(folderId: folder.id, restrictToFolder: true),
        ),
        unorderedEquals(['Ordonnance', 'Analyse']),
      );

      valueOf(await lib.repository.moveToFolder([a.id], null));
      final moved = valueOf(await lib.repository.getById(a.id));
      expect(moved.folderId, isNull);
      expect(moved.updatedAt, a.updatedAt);
    });

    test('changes nothing when a folder or a document is unknown', () async {
      final folder = valueOf(await lib.repository.createFolder('Santé'));
      final document = await lib.addDocument('Ordonnance');

      expect(
        await lib.repository.moveToFolder([document.id], 'nowhere'),
        isNotFound,
      );
      expect(
        await lib.repository.moveToFolder([document.id, 'ghost'], folder.id),
        isNotFound,
      );
      expect(
        valueOf(await lib.repository.getById(document.id)).folderId,
        isNull,
      );
    });
  });

  group('setFavorite', () {
    test('goes through the favorites table and its trigger', () async {
      final document = await lib.addDocument('Carte grise');

      valueOf(await lib.repository.setFavorite(document.id, favorite: true));
      valueOf(await lib.repository.setFavorite(document.id, favorite: true));

      expect(await lib.count('favorites'), 1);
      final starred = valueOf(await lib.repository.getById(document.id));
      expect(starred.isFavorite, isTrue);
      expect(starred.updatedAt, document.updatedAt);
      expect(await lib.names(const DocumentQuery(favoritesOnly: true)), [
        'Carte grise',
      ]);

      valueOf(await lib.repository.setFavorite(document.id, favorite: false));

      expect(await lib.count('favorites'), 0);
      expect(
        valueOf(await lib.repository.getById(document.id)).isFavorite,
        isFalse,
      );
    });

    test('fails with notFound for an unknown id', () async {
      expect(
        await lib.repository.setFavorite('unknown', favorite: true),
        isNotFound,
      );
      expect(await lib.count('favorites'), 0);
    });
  });

  group('trash', () {
    test('moves documents to the trash and restores them', () async {
      final kept = await lib.addDocument('Gardé');
      final thrown = await lib.addDocument('Jeté');

      valueOf(await lib.repository.moveToTrash([thrown.id]));
      final trashed = valueOf(await lib.repository.getById(thrown.id));
      expect(trashed.deletedAt, lib.now);
      expect(trashed.isInTrash, isTrue);
      expect(await lib.names(const DocumentQuery()), ['Gardé']);
      expect(await lib.names(const DocumentQuery(inTrash: true)), ['Jeté']);

      valueOf(await lib.repository.moveToTrash([thrown.id, kept.id]));
      expect(
        valueOf(await lib.repository.getById(thrown.id)).deletedAt,
        trashed.deletedAt,
        reason: 'the first deletion date is kept',
      );

      valueOf(await lib.repository.restoreFromTrash([thrown.id, kept.id]));
      expect(await lib.names(const DocumentQuery(inTrash: true)), isEmpty);
      expect(
        valueOf(await lib.repository.getById(thrown.id)).updatedAt,
        thrown.updatedAt,
      );
      expect(await lib.storage.exists(thrown.filePath), isTrue);
    });

    test('is all-or-nothing when an id is unknown', () async {
      final document = await lib.addDocument('Seul');

      expect(
        await lib.repository.moveToTrash([document.id, 'ghost']),
        isNotFound,
      );
      expect(await lib.repository.restoreFromTrash(['ghost']), isNotFound);
      expect(
        valueOf(await lib.repository.getById(document.id)).isInTrash,
        isFalse,
      );
    });

    test('emptyTrash only deletes what the trash holds', () async {
      final kept = await lib.addDocument('Gardé', pages: 1);
      final thrown = await lib.addDocument('Jeté', pages: 2, thumbnail: true);
      await lib.repository.moveToTrash([thrown.id]);

      valueOf(await lib.repository.emptyTrash());

      expect(await lib.repository.getById(thrown.id), isNotFound);
      expect(await lib.filesIn(StorageArea.documents), {kept.filePath});
      expect(await lib.filesIn(StorageArea.pages), hasLength(1));
      expect(await lib.filesIn(StorageArea.thumbnails), isEmpty);
      expect(await lib.count('document_pages'), 1);
    });
  });

  group('deletePermanently', () {
    test('deletes the rows, their dependents and every file', () async {
      final kept = await lib.addDocument('Gardé', pages: 1, thumbnail: true);
      final gone = await lib.addDocument('Supprimé', pages: 2, thumbnail: true);
      await lib.repository.setFavorite(gone.id, favorite: true);
      await lib.repository.setTags(gone.id, ['Perso', 'Commun']);
      await lib.repository.setTags(kept.id, ['Commun']);
      await lib.ocr.save(documentId: gone.id, text: 'texte reconnu');

      valueOf(await lib.repository.deletePermanently([gone.id]));

      expect(await lib.repository.getById(gone.id), isNotFound);
      expect(await lib.count('documents'), 1);
      expect(await lib.count('document_pages'), 1);
      expect(await lib.count('favorites'), 0);
      expect(await lib.count('ocr_results'), 0);
      expect(await lib.count('document_tags'), 1);
      expect(
        valueOf(await lib.repository.allTags()).map((tag) => tag.name),
        ['Commun'],
        reason: 'a tag left without document is removed',
      );
      expect(await lib.filesIn(StorageArea.documents), {kept.filePath});
      expect(await lib.filesIn(StorageArea.thumbnails), {kept.thumbnailPath});
      expect(await lib.filesIn(StorageArea.pages), hasLength(1));
    });

    test('is not aborted by a file that is already gone', () async {
      final document = await lib.addDocument('Abîmé', pages: 1);
      await lib.storage.delete(document.filePath);

      valueOf(await lib.repository.deletePermanently([document.id]));

      expect(await lib.count('documents'), 0);
      expect(await lib.filesIn(StorageArea.pages), isEmpty);
    });

    test('deletes nothing when an id is unknown', () async {
      final document = await lib.addDocument('Intact');

      expect(
        await lib.repository.deletePermanently([document.id, 'ghost']),
        isNotFound,
      );
      expect(await lib.count('documents'), 1);
      expect(await lib.storage.exists(document.filePath), isTrue);
    });
  });

  group('updateVaultState', () {
    test('records the vault flags, the new path and its size', () async {
      final document = await lib.addDocument('Secret', size: 10);
      final encrypted = await lib.writeFile(
        StorageArea.vault,
        extension: 'enc',
        size: 48,
      );

      final updated = valueOf(
        await lib.repository.updateVaultState(
          document.id,
          filePath: encrypted,
          isInVault: true,
          isEncrypted: true,
        ),
      );

      expect(updated.filePath, encrypted);
      expect(updated.fileSize, 48);
      expect(updated.isInVault, isTrue);
      expect(updated.isEncrypted, isTrue);
      expect(updated.updatedAt, document.updatedAt);
      expect(
        await lib.storage.exists(document.filePath),
        isTrue,
        reason: 'the vault destroys the source itself',
      );
      expect(await lib.names(const DocumentQuery()), isEmpty);
      expect(await lib.names(const DocumentQuery(inVault: true)), ['Secret']);
    });

    test('fails when the file or the document does not exist', () async {
      final document = await lib.addDocument('Secret');
      final encrypted = await lib.writeFile(StorageArea.vault);

      expect(
        await lib.repository.updateVaultState(
          document.id,
          filePath: 'vault/absent.enc',
          isInVault: true,
          isEncrypted: true,
        ),
        isNotFound,
      );
      expect(
        await lib.repository.updateVaultState(
          'unknown',
          filePath: encrypted,
          isInVault: true,
          isEncrypted: true,
        ),
        isNotFound,
      );
      expect(valueOf(await lib.repository.getById(document.id)), document);
    });
  });

  test('getById and pagesOf fail with notFound for an unknown id', () async {
    expect(await lib.repository.getById('unknown'), isNotFound);
    expect(await lib.repository.pagesOf('unknown'), isNotFound);
  });

  test('wipeAll removes every row and every file', () async {
    final folder = valueOf(await lib.repository.createFolder('Tout'));
    final document = await lib.addDocument(
      'Dernier',
      folderId: folder.id,
      pages: 2,
      thumbnail: true,
    );
    await lib.moveToVault(await lib.addDocument('Coffre'));
    await lib.repository.setTags(document.id, ['Tag']);
    await lib.repository.setFavorite(document.id, favorite: true);
    await lib.ocr.save(documentId: document.id, text: 'texte');
    await lib.writeFile(StorageArea.sessions, extension: 'jpg', group: 's1');
    await lib.writeFile(StorageArea.exports);

    valueOf(await lib.repository.wipeAll());

    for (final table in const [
      'documents',
      'document_pages',
      'folders',
      'tags',
      'document_tags',
      'favorites',
      'ocr_results',
    ]) {
      expect(await lib.count(table), 0, reason: table);
    }
    for (final area in StorageArea.values) {
      expect(await lib.storage.directoryOf(area).exists(), isTrue);
      expect(await lib.filesIn(area), isEmpty, reason: area.name);
    }
  });

  test('changes only emits after a successful mutation', () async {
    final document = await lib.addDocument('Témoin');
    var emitted = 0;
    final subscription = lib.repository.changes.listen((_) => emitted++);
    addTearDown(subscription.cancel);

    await lib.repository.rename('unknown', 'Nom');
    await lib.repository.query(const DocumentQuery());
    await lib.repository.moveToTrash(const []);
    await pumpEventQueue();
    expect(emitted, 0);

    await lib.repository.rename(document.id, 'Renommé');
    await lib.repository.setFavorite(document.id, favorite: true);
    await lib.repository.moveToTrash([document.id]);
    await pumpEventQueue();
    expect(emitted, 3);
  });
}
