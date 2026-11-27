import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/shared/models/document_entity.dart';

import '../support/library_harness.dart';

void main() {
  late LibraryHarness lib;
  late DocumentEntity document;

  setUp(() async {
    lib = await LibraryHarness.create();
    document = await lib.addDocument('Scan');
  });
  tearDown(() => lib.dispose());

  Future<List<Map<String, Object?>>> rows() =>
      lib.db.query('ocr_results', orderBy: 'page_index ASC');

  test('textOf is null until a text is saved', () async {
    expect(valueOf(await lib.ocr.textOf(document.id)), isNull);
    expect(valueOf(await lib.ocr.textOf('unknown')), isNull);
  });

  test('saves a document-level text with its language', () async {
    valueOf(
      await lib.ocr.save(
        documentId: document.id,
        text: 'Bonjour le monde',
        language: 'fr',
      ),
    );

    expect(valueOf(await lib.ocr.textOf(document.id)), 'Bonjour le monde');
    final saved = (await rows()).single;
    expect(saved['language'], 'fr');
    expect(saved['page_index'], isNull);
    expect(saved['created_at'], saved['updated_at']);
  });

  test('updates a text in place and keeps its creation date', () async {
    await lib.ocr.save(documentId: document.id, text: 'premier jet');
    final before = (await rows()).single;

    valueOf(await lib.ocr.save(documentId: document.id, text: 'corrigé'));

    final after = (await rows()).single;
    expect(after['id'], before['id']);
    expect(after['extracted_text'], 'corrigé');
    expect(after['created_at'], before['created_at']);
    expect(
      after['updated_at']! as int,
      greaterThan(before['updated_at']! as int),
    );
  });

  test('concatenates page texts in page order', () async {
    await lib.ocr.save(documentId: document.id, text: 'trois', pageIndex: 2);
    await lib.ocr.save(documentId: document.id, text: 'un', pageIndex: 0);
    await lib.ocr.save(documentId: document.id, text: 'deux', pageIndex: 1);
    await lib.ocr.save(documentId: document.id, text: 'DEUX', pageIndex: 1);

    expect(valueOf(await lib.ocr.textOf(document.id)), 'un\n\nDEUX\n\ntrois');
    expect(await rows(), hasLength(3));
  });

  test('keeps one representation: document-level or per page', () async {
    await lib.ocr.save(documentId: document.id, text: 'page', pageIndex: 0);
    await lib.ocr.save(documentId: document.id, text: 'tout le document');
    expect(valueOf(await lib.ocr.textOf(document.id)), 'tout le document');
    expect(await rows(), hasLength(1));

    await lib.ocr.save(documentId: document.id, text: 'page 4', pageIndex: 3);
    expect(valueOf(await lib.ocr.textOf(document.id)), 'page 4');
    expect((await rows()).single['page_index'], 3);
  });

  test('a blank text removes the entry', () async {
    await lib.ocr.save(documentId: document.id, text: 'un', pageIndex: 0);
    await lib.ocr.save(documentId: document.id, text: 'deux', pageIndex: 1);

    valueOf(
      await lib.ocr.save(documentId: document.id, text: '  \n', pageIndex: 0),
    );

    expect(valueOf(await lib.ocr.textOf(document.id)), 'deux');
  });

  test('rejects an unknown document and a negative page', () async {
    expect(
      await lib.ocr.save(documentId: 'unknown', text: 'texte'),
      isNotFound,
    );
    expect(
      await lib.ocr.save(documentId: document.id, text: 'texte', pageIndex: -1),
      isValidationError('invalid_page_index'),
    );
    expect(await rows(), isEmpty);
  });

  test('deleteFor removes the text and is idempotent', () async {
    final other = await lib.addDocument('Autre');
    await lib.ocr.save(documentId: document.id, text: 'un', pageIndex: 0);
    await lib.ocr.save(documentId: document.id, text: 'deux', pageIndex: 1);
    await lib.ocr.save(documentId: other.id, text: 'autre');

    valueOf(await lib.ocr.deleteFor(document.id));
    valueOf(await lib.ocr.deleteFor(document.id));
    valueOf(await lib.ocr.deleteFor('unknown'));

    expect(valueOf(await lib.ocr.textOf(document.id)), isNull);
    expect(valueOf(await lib.ocr.textOf(other.id)), 'autre');
  });

  test('tells the library after a change, not after a failure', () async {
    var changes = 0;
    final subscription = lib.repository.changes.listen((_) => changes++);
    addTearDown(subscription.cancel);

    await lib.ocr.save(documentId: 'unknown', text: 'texte');
    await lib.ocr.textOf(document.id);
    await pumpEventQueue();
    expect(changes, 0);

    await lib.ocr.save(documentId: document.id, text: 'texte');
    await lib.ocr.deleteFor(document.id);
    await pumpEventQueue();
    expect(changes, 2);
  });

  test('the text disappears with its document', () async {
    await lib.ocr.save(documentId: document.id, text: 'texte');

    await lib.repository.deletePermanently([document.id]);

    expect(await rows(), isEmpty);
  });
}
