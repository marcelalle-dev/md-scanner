import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';

import '../support/library_harness.dart';

void main() {
  late LibraryHarness lib;
  late ProviderContainer container;
  final busy = <bool Function()>[];

  setUp(() async {
    lib = await LibraryHarness.create();
    container = ProviderContainer(
      overrides: [
        documentRepositoryProvider.overrideWithValue(lib.repository),
        ocrTextRepositoryProvider.overrideWithValue(lib.ocr),
        fileStorageProvider.overrideWithValue(lib.storage),
      ],
    );
  });
  tearDown(() async {
    busy.clear();
    container.dispose();
    await lib.dispose();
  });

  /// Keeps [provider] alive like a screen would and returns its values.
  List<AsyncValue<T>> watch<T>(ProviderListenable<AsyncValue<T>> provider) {
    final states = <AsyncValue<T>>[];
    final subscription = container.listen<AsyncValue<T>>(
      provider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    busy.add(() => states.last.isLoading);
    addTearDown(subscription.close);
    return states;
  }

  /// Lets the change event reach the providers, then waits for every reload
  /// (some read the disk, which takes real time).
  Future<void> settle() async {
    await pumpEventQueue();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (busy.any((isBusy) => isBusy()) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await pumpEventQueue();
  }

  test('documentListProvider reloads after each repository change', () async {
    const query = DocumentQuery(
      sort: DocumentSort(DocumentSortField.name, ascending: true),
    );
    final states = watch(documentListProvider(query));
    await settle();
    expect(states.last.value, isEmpty);

    final first = await lib.addDocument('Bail');
    await settle();
    expect(states.last.value!.map((document) => document.name), ['Bail']);

    await lib.addDocument('Assurance');
    await lib.repository.moveToTrash([first.id]);
    await settle();
    expect(states.last.value!.map((document) => document.name), ['Assurance']);
    expect(states.last.isLoading, isFalse);
  });

  test('each query keeps its own list', () async {
    final trash = watch(
      documentListProvider(const DocumentQuery(inTrash: true)),
    );
    final live = watch(documentListProvider(const DocumentQuery()));
    final document = await lib.addDocument('Note');
    await lib.repository.moveToTrash([document.id]);
    await settle();

    expect(trash.last.value, hasLength(1));
    expect(live.last.value, isEmpty);
  });

  test('a search list reloads when OCR text is saved', () async {
    final document = await lib.addDocument('Scan 1');
    final states = watch(
      documentListProvider(const DocumentQuery(search: 'ordonnance')),
    );
    await settle();
    expect(states.last.value, isEmpty);

    await lib.ocr.save(documentId: document.id, text: 'Ordonnance médicale');
    await settle();

    expect(states.last.value!.single.id, document.id);
  });

  test(
    'documentByIdProvider follows the document and reports its loss',
    () async {
      final document = await lib.addDocument('Devis');
      final states = watch(documentByIdProvider(document.id));
      await settle();
      expect(states.last.value, document);

      await lib.repository.setFavorite(document.id, favorite: true);
      await settle();
      expect(states.last.value!.isFavorite, isTrue);

      await lib.repository.deletePermanently([document.id]);
      await settle();

      final state = states.last;
      expect(state.hasError, isTrue);
      expect(state.isLoading, isFalse, reason: 'a failure is not retried');
      expect(state.error, isA<FailureException>());
      expect(
        failureOf(state.error!),
        const StorageFailure(StorageFailureKind.notFound),
      );
    },
  );

  test('folderListProvider is keyed by parent and reloads', () async {
    final roots = watch(folderListProvider(null));
    await settle();
    expect(roots.last.value, isEmpty);

    final parent = valueOf(await lib.repository.createFolder('Maison'));
    final children = watch(folderListProvider(parent.id));
    await lib.repository.createFolder('Travaux', parentId: parent.id);
    await lib.addDocument('Bail', folderId: parent.id);
    await settle();

    expect(roots.last.value!.single.name, 'Maison');
    expect(roots.last.value!.single.documentCount, 1);
    expect(children.last.value!.single.name, 'Travaux');
  });

  test('tag providers reload when tags change', () async {
    final document = await lib.addDocument('Facture');
    final all = watch(allTagsProvider);
    final own = watch(documentTagsProvider(document.id));
    await settle();
    expect(all.last.value, isEmpty);
    expect(own.last.value, isEmpty);

    await lib.repository.setTags(document.id, ['Banque', 'Impôts']);
    await settle();

    expect(all.last.value!.map((tag) => tag.name), ['Banque', 'Impôts']);
    expect(own.last.value!.map((tag) => tag.name), ['Banque', 'Impôts']);

    final unknown = watch(documentTagsProvider('unknown'));
    await settle();
    expect(
      failureOf(unknown.last.error!),
      const StorageFailure(StorageFailureKind.notFound),
    );
  });

  test(
    'storageUsageProvider measures the areas and the document sets',
    () async {
      await lib.addDocument('Vivant', size: 100, thumbnail: true);
      final trashed = await lib.addDocument('Jeté', size: 30);
      await lib.repository.moveToTrash([trashed.id]);
      await lib.moveToVault(await lib.addDocument('Coffre', size: 10));
      await lib.writeFile(StorageArea.temp, size: 7);
      await lib.writeFile(StorageArea.exports, size: 9);
      final states = watch(storageUsageProvider);
      await settle();

      final usage = states.last.value!;
      expect(usage.library, const DocumentTotals(count: 1, bytes: 100));
      expect(usage.trash, const DocumentTotals(count: 1, bytes: 30));
      expect(usage.vault, const DocumentTotals(count: 1, bytes: 40));
      expect(usage.bytesOf(StorageArea.documents), 130);
      expect(usage.bytesOf(StorageArea.thumbnails), 5);
      expect(usage.bytesOf(StorageArea.vault), 40);
      expect(usage.reclaimableBytes, 16);
      expect(usage.totalBytes, 130 + 5 + 40 + 16);

      await lib.repository.emptyTrash();
      await settle();
      expect(
        states.last.value!.trash,
        const DocumentTotals(count: 0, bytes: 0),
      );
      expect(states.last.value!.bytesOf(StorageArea.documents), 100);
    },
  );

  test('libraryRepositoryOverrides binds the contracts to SQLite', () async {
    final scoped = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(lib.database),
        fileStorageProvider.overrideWithValue(lib.storage),
        ...libraryRepositoryOverrides,
      ],
    );
    addTearDown(scoped.dispose);
    final states = <AsyncValue<List<DocumentEntity>>>[];
    final subscription = scoped.listen(
      documentListProvider(const DocumentQuery(search: 'facture')),
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final repository = scoped.read(documentRepositoryProvider);
    expect(repository, same(scoped.read(sqliteDocumentRepositoryProvider)));
    final path = await lib.writeFile(StorageArea.documents);
    final document = valueOf(
      await repository.register(
        NewDocument(
          name: 'Scan',
          filePath: path,
          fileType: DocumentFileType.pdf,
          source: DocumentSource.scan,
        ),
      ),
    );
    await scoped
        .read(ocrTextRepositoryProvider)
        .save(documentId: document.id, text: 'Facture acquittée');
    await settle();

    expect(states.last.value!.single.id, document.id);
  });
}
