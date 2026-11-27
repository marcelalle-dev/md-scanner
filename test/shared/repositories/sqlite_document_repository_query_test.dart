import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/shared/models/document_entity.dart';

import '../support/library_harness.dart';

void main() {
  late LibraryHarness lib;

  setUp(() async => lib = await LibraryHarness.create());
  tearDown(() => lib.dispose());

  group('query filters', () {
    test('default lists live documents outside the vault', () async {
      await lib.addDocument('Visible');
      final trashed = await lib.addDocument('Corbeille');
      await lib.repository.moveToTrash([trashed.id]);
      final secret = await lib.moveToVault(await lib.addDocument('Coffre'));
      final both = await lib.moveToVault(await lib.addDocument('Coffre jeté'));
      await lib.repository.moveToTrash([both.id]);

      expect(await lib.names(const DocumentQuery()), ['Visible']);
      expect(await lib.names(const DocumentQuery(inTrash: true)), [
        'Corbeille',
      ]);
      expect(await lib.names(const DocumentQuery(inVault: true)), ['Coffre']);
      expect(
        await lib.names(const DocumentQuery(inVault: true, inTrash: true)),
        ['Coffre jeté'],
      );
      expect(secret.isInVault, isTrue);
    });

    test('restricts to a folder or to the root', () async {
      final folder = valueOf(await lib.repository.createFolder('Maison'));
      await lib.addDocument('Bail', folderId: folder.id);
      await lib.addDocument('Libre');

      expect(
        await lib.names(const DocumentQuery()),
        unorderedEquals(['Bail', 'Libre']),
      );
      expect(
        await lib.names(
          DocumentQuery(folderId: folder.id, restrictToFolder: true),
        ),
        ['Bail'],
      );
      expect(await lib.names(const DocumentQuery(restrictToFolder: true)), [
        'Libre',
      ]);
      expect(
        await lib.names(
          const DocumentQuery(folderId: 'nowhere', restrictToFolder: true),
        ),
        isEmpty,
      );
      expect(
        await lib.names(DocumentQuery(folderId: folder.id)),
        hasLength(2),
        reason: 'folderId is ignored without restrictToFolder',
      );
    });

    test('filters by favorite, tag and file type', () async {
      final pdf = await lib.addDocument('Pdf');
      final jpg = await lib.addDocument('Photo', type: DocumentFileType.jpg);
      await lib.addDocument('Texte', type: DocumentFileType.txt);
      await lib.repository.setFavorite(jpg.id, favorite: true);
      await lib.repository.setTags(pdf.id, ['Travail']);
      await lib.repository.setTags(jpg.id, ['Travail', 'Perso']);
      final tags = {
        for (final tag in valueOf(await lib.repository.allTags()))
          tag.name: tag.id,
      };

      expect(await lib.names(const DocumentQuery(favoritesOnly: true)), [
        'Photo',
      ]);
      expect(
        await lib.names(DocumentQuery(tagId: tags['Travail'])),
        unorderedEquals(['Pdf', 'Photo']),
      );
      expect(await lib.names(DocumentQuery(tagId: tags['Perso'])), ['Photo']);
      expect(
        await lib.names(
          const DocumentQuery(
            types: {DocumentFileType.jpg, DocumentFileType.txt},
          ),
        ),
        unorderedEquals(['Photo', 'Texte']),
      );
      expect(await lib.names(const DocumentQuery(types: {})), isEmpty);
      expect(
        await lib.names(
          DocumentQuery(
            tagId: tags['Travail'],
            favoritesOnly: true,
            types: const {DocumentFileType.jpg},
          ),
        ),
        ['Photo'],
      );
    });
  });

  group('query search', () {
    test('matches the name without regard to case', () async {
      await lib.addDocument('Facture EDF mars');
      await lib.addDocument('Été 2024');
      await lib.addDocument('ÉTÉ INDIEN');
      await lib.addDocument('Contrat');

      expect(await lib.names(const DocumentQuery(search: 'edf')), [
        'Facture EDF mars',
      ]);
      expect(await lib.names(const DocumentQuery(search: '  FACTURE  ')), [
        'Facture EDF mars',
      ]);
      expect(
        await lib.names(const DocumentQuery(search: 'été')),
        unorderedEquals(['Été 2024', 'ÉTÉ INDIEN']),
      );
      expect(await lib.names(const DocumentQuery(search: 'absent')), isEmpty);
      expect(await lib.names(const DocumentQuery(search: '   ')), hasLength(4));
    });

    test('treats LIKE wildcards as plain characters', () async {
      await lib.addDocument('Remise 100% garantie');
      await lib.addDocument('Remise 1000 euros');
      await lib.addDocument('note_finale');
      await lib.addDocument('note finale');
      await lib.addDocument(r'dossier\archive');

      expect(await lib.names(const DocumentQuery(search: '100%')), [
        'Remise 100% garantie',
      ]);
      expect(await lib.names(const DocumentQuery(search: 'note_')), [
        'note_finale',
      ]);
      expect(await lib.names(const DocumentQuery(search: '%')), [
        'Remise 100% garantie',
      ]);
      expect(await lib.names(const DocumentQuery(search: r'\')), isEmpty);
    });

    test('matches the saved OCR text', () async {
      final scanned = await lib.addDocument('Scan 12');
      final paged = await lib.addDocument('Scan 13');
      await lib.addDocument('Scan 14');
      await lib.ocr.save(
        documentId: scanned.id,
        text: 'Attestation de domicile délivrée à Cotonou',
      );
      await lib.ocr.save(documentId: paged.id, text: 'page une', pageIndex: 0);
      await lib.ocr.save(
        documentId: paged.id,
        text: 'Relevé bancaire COTONOU',
        pageIndex: 1,
      );

      expect(
        await lib.names(const DocumentQuery(search: 'cotonou')),
        unorderedEquals(['Scan 12', 'Scan 13']),
      );
      expect(await lib.names(const DocumentQuery(search: 'attestation')), [
        'Scan 12',
      ]);
      expect(
        await lib.names(const DocumentQuery(search: 'scan')),
        hasLength(3),
      );

      await lib.repository.moveToTrash([scanned.id]);
      expect(await lib.names(const DocumentQuery(search: 'cotonou')), [
        'Scan 13',
      ]);
    });
  });

  group('query sort', () {
    setUp(() async {
      await lib.addDocument('banane', size: 300);
      await lib.addDocument('Cerise', size: 100);
      await lib.addDocument('abricot', size: 200);
    });

    test('newest first by default', () async {
      expect(await lib.names(const DocumentQuery()), [
        'abricot',
        'Cerise',
        'banane',
      ]);
      expect(
        await lib.names(
          const DocumentQuery(
            sort: DocumentSort(DocumentSortField.date, ascending: true),
          ),
        ),
        ['banane', 'Cerise', 'abricot'],
      );
    });

    test('date follows the last update', () async {
      final all = valueOf(await lib.repository.query(const DocumentQuery()));
      final oldest = all.last;

      await lib.repository.rename(oldest.id, 'banane mûre');

      expect((await lib.names(const DocumentQuery())).first, 'banane mûre');
    });

    test('by name ignores case', () async {
      expect(
        await lib.names(
          const DocumentQuery(
            sort: DocumentSort(DocumentSortField.name, ascending: true),
          ),
        ),
        ['abricot', 'banane', 'Cerise'],
      );
      expect(
        await lib.names(
          const DocumentQuery(sort: DocumentSort(DocumentSortField.name)),
        ),
        ['Cerise', 'banane', 'abricot'],
      );
    });

    test('by size, with a limit', () async {
      expect(
        await lib.names(
          const DocumentQuery(sort: DocumentSort(DocumentSortField.size)),
        ),
        ['banane', 'abricot', 'Cerise'],
      );
      expect(
        await lib.names(
          const DocumentQuery(
            sort: DocumentSort(DocumentSortField.size, ascending: true),
            limit: 2,
          ),
        ),
        ['Cerise', 'abricot'],
      );
      expect(await lib.names(const DocumentQuery(limit: 0)), isEmpty);
    });
  });

  group('folders', () {
    test('createFolder cleans the name and nests under a parent', () async {
      final parent = valueOf(await lib.repository.createFolder('  Maison  '));
      final child = valueOf(
        await lib.repository.createFolder('Travaux', parentId: parent.id),
      );

      expect(parent.name, 'Maison');
      expect(parent.parentId, isNull);
      expect(parent.createdAt, parent.updatedAt);
      expect(child.parentId, parent.id);
      expect(valueOf(await lib.repository.getFolder(child.id)), child);
    });

    test('createFolder rejects blank, duplicate and orphan folders', () async {
      final parent = valueOf(await lib.repository.createFolder('École'));

      expect(
        await lib.repository.createFolder('   '),
        isValidationError('empty_name'),
      );
      expect(await lib.repository.createFolder('école'), isAlreadyExists);
      expect(await lib.repository.createFolder('ÉCOLE '), isAlreadyExists);
      expect(
        await lib.repository.createFolder('Notes', parentId: 'nowhere'),
        isNotFound,
      );
      expect(
        (await lib.repository.createFolder(
          'École',
          parentId: parent.id,
        )).isSuccess,
        isTrue,
        reason: 'the same name is free under another parent',
      );
      expect(await lib.count('folders'), 2);
    });

    test('folders lists a level sorted by name with its counts', () async {
      final zoo = valueOf(await lib.repository.createFolder('zoo'));
      final alpha = valueOf(await lib.repository.createFolder('Alpha'));
      await lib.repository.createFolder('Sous-dossier', parentId: alpha.id);
      await lib.addDocument('Un', folderId: alpha.id);
      final trashed = await lib.addDocument('Deux', folderId: alpha.id);
      await lib.repository.moveToTrash([trashed.id]);
      await lib.moveToVault(await lib.addDocument('Trois', folderId: alpha.id));
      await lib.addDocument('Quatre', folderId: zoo.id);

      final roots = valueOf(await lib.repository.folders());
      final children = valueOf(
        await lib.repository.folders(parentId: alpha.id),
      );

      expect(roots.map((folder) => folder.name), ['Alpha', 'zoo']);
      expect(roots.map((folder) => folder.documentCount), [1, 1]);
      expect(children.map((folder) => folder.name), ['Sous-dossier']);
      expect(
        valueOf(await lib.repository.getFolder(alpha.id)).documentCount,
        1,
      );
      expect(
        valueOf(await lib.repository.folders(parentId: 'nowhere')),
        isEmpty,
      );
      expect(await lib.repository.getFolder('nowhere'), isNotFound);
    });

    test('renameFolder validates the new name', () async {
      final folder = valueOf(await lib.repository.createFolder('Brouillons'));
      await lib.repository.createFolder('Archives');

      final renamed = valueOf(
        await lib.repository.renameFolder(folder.id, 'BROUILLONS'),
      );

      expect(renamed.name, 'BROUILLONS');
      expect(renamed.updatedAt.isAfter(folder.updatedAt), isTrue);
      expect(
        await lib.repository.renameFolder(folder.id, 'archives'),
        isAlreadyExists,
      );
      expect(
        await lib.repository.renameFolder(folder.id, ' '),
        isValidationError('empty_name'),
      );
      expect(await lib.repository.renameFolder('nowhere', 'Nom'), isNotFound);
      expect(valueOf(await lib.repository.getFolder(folder.id)), renamed);
    });

    test(
      'deleteFolder removes the sub-tree and keeps every document',
      () async {
        final root = valueOf(await lib.repository.createFolder('Projet'));
        final child = valueOf(
          await lib.repository.createFolder('Plans', parentId: root.id),
        );
        final grandChild = valueOf(
          await lib.repository.createFolder('Anciens', parentId: child.id),
        );
        final other = valueOf(await lib.repository.createFolder('Autre'));
        final direct = await lib.addDocument('Devis', folderId: root.id);
        final nested = await lib.addDocument('Plan', folderId: grandChild.id);
        final trashed = await lib.addDocument('Vieux plan', folderId: child.id);
        await lib.repository.moveToTrash([trashed.id]);
        final elsewhere = await lib.addDocument(
          'Autre doc',
          folderId: other.id,
        );

        valueOf(await lib.repository.deleteFolder(root.id));

        expect(
          valueOf(await lib.repository.folders()).map((folder) => folder.id),
          [other.id],
        );
        expect(await lib.count('folders'), 1);
        expect(await lib.count('documents'), 4);
        for (final document in [direct, nested, trashed]) {
          final moved = valueOf(await lib.repository.getById(document.id));
          expect(moved.folderId, isNull, reason: document.name);
          expect(await lib.storage.exists(moved.filePath), isTrue);
        }
        expect(
          valueOf(await lib.repository.getById(trashed.id)).isInTrash,
          isTrue,
        );
        expect(
          valueOf(await lib.repository.getById(elsewhere.id)).folderId,
          other.id,
        );
        expect(await lib.repository.deleteFolder(root.id), isNotFound);
      },
    );
  });

  group('tags', () {
    test('setTags creates tags once and compares names without case', () async {
      final first = await lib.addDocument('Un');
      final second = await lib.addDocument('Deux');

      valueOf(
        await lib.repository.setTags(first.id, [
          ' Impôts ',
          'impôts',
          '',
          'Banque',
        ]),
      );
      valueOf(await lib.repository.setTags(second.id, ['BANQUE', 'Santé']));

      expect(valueOf(await lib.repository.allTags()).map((tag) => tag.name), [
        'Banque',
        'Impôts',
        'Santé',
      ]);
      expect(
        valueOf(await lib.repository.tagsOf(first.id)).map((tag) => tag.name),
        ['Banque', 'Impôts'],
      );
      expect(
        valueOf(await lib.repository.tagsOf(second.id)).map((tag) => tag.name),
        ['Banque', 'Santé'],
      );
      expect(await lib.count('tags'), 3);
    });

    test('setTags removes the tags no document uses any more', () async {
      final first = await lib.addDocument('Un');
      final second = await lib.addDocument('Deux');
      await lib.repository.setTags(first.id, ['Commun', 'Seul']);
      await lib.repository.setTags(second.id, ['Commun']);

      valueOf(await lib.repository.setTags(first.id, ['Nouveau']));

      expect(valueOf(await lib.repository.allTags()).map((tag) => tag.name), [
        'Commun',
        'Nouveau',
      ]);

      valueOf(await lib.repository.setTags(first.id, const []));
      valueOf(await lib.repository.setTags(second.id, const []));

      expect(valueOf(await lib.repository.allTags()), isEmpty);
      expect(valueOf(await lib.repository.tagsOf(first.id)), isEmpty);
    });

    test('fail with notFound for an unknown document', () async {
      expect(await lib.repository.tagsOf('unknown'), isNotFound);
      expect(await lib.repository.setTags('unknown', ['Tag']), isNotFound);
      expect(await lib.count('tags'), 0);
    });
  });
}
