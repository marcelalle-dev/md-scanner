import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/features/document_scanner/domain/document_capture.dart';
import 'package:md_scanner/features/document_scanner/presentation/scan_session_controller.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import '../../helpers/test_database.dart';

class _FakeCapture implements DocumentCapture {
  _FakeCapture(this.paths);

  List<String> paths;
  Result<List<String>>? forced;

  @override
  Future<Result<List<String>>> scanWithCamera({required int pageLimit}) async =>
      forced ?? Success(paths);

  @override
  Future<Result<List<String>>> pickFromGallery() async =>
      forced ?? Success(paths);
}

/// Writes a small file where a real processor would write the rendered page.
class _FakeImages implements ImageProcessor {
  Quad? detected = Quad.full;
  bool failRender = false;
  final List<ImageRenderRequest> renders = [];

  @override
  Future<Result<Quad?>> detectDocument(
    String path, {
    ScanMode mode = ScanMode.document,
  }) async => Success(detected);

  @override
  Future<Result<ProcessedImage>> render(ImageRenderRequest request) async {
    if (failRender) {
      return const Err(ImageFailure(ImageFailureKind.processingFailed));
    }
    renders.add(request);
    await File(request.outputPath).writeAsBytes([1, 2, 3]);
    return Success(
      ProcessedImage(
        path: request.outputPath,
        width: 10,
        height: 10,
        byteSize: 3,
        format: request.format,
      ),
    );
  }

  @override
  Future<Result<String>> thumbnail(
    String sourcePath,
    String outputPath, {
    int maxSize = 512,
  }) async {
    await File(outputPath).writeAsBytes([9]);
    return Success(outputPath);
  }

  @override
  Future<Result<ImageInfo>> inspect(String path) => throw UnimplementedError();

  @override
  Future<Result<Uint8List>> preview(ImagePreviewRequest request) =>
      throw UnimplementedError();
}

class _MockPdfEngine extends Mock implements PdfEngine {}

void main() {
  late AppDatabase database;
  late FileStorage storage;
  late ProviderContainer container;
  late _FakeCapture capture;
  late _FakeImages images;
  late _MockPdfEngine pdf;
  late Directory inbox;

  Future<String> photo(String name) async {
    final file = File(p.join(inbox.path, name));
    await file.writeAsBytes([0xFF, 0xD8, 0xFF]);
    return file.path;
  }

  setUpAll(() => registerFallbackValue(const PdfPageSetup()));

  setUp(() async {
    database = await openTestDatabase();
    storage = await createTestStorage();
    inbox = await Directory.systemTemp.createTemp('md_scanner_inbox_');
    capture = _FakeCapture([await photo('a.jpg'), await photo('b.jpg')]);
    images = _FakeImages();
    pdf = _MockPdfEngine();
    when(
      () => pdf.imagesToPdf(
        imagePaths: any(named: 'imagePaths'),
        outputPath: any(named: 'outputPath'),
        setup: any(named: 'setup'),
        onProgress: any(named: 'onProgress'),
        isCancelled: any(named: 'isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final output = invocation.namedArguments[#outputPath] as String;
      final pages = invocation.namedArguments[#imagePaths] as List<String>;
      await File(output).writeAsBytes([37, 80, 68, 70]);
      return Success(
        PdfOutput(path: output, pageCount: pages.length, fileSize: 4),
      );
    });
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        fileStorageProvider.overrideWithValue(storage),
        documentRepositoryProvider.overrideWith(
          (ref) => ref.watch(sqliteDocumentRepositoryProvider),
        ),
        documentCaptureProvider.overrideWithValue(capture),
        imageProcessorProvider.overrideWithValue(images),
        pdfEngineProvider.overrideWithValue(pdf),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    await storage.root.delete(recursive: true);
    await inbox.delete(recursive: true);
  });

  ScanSessionController controller() =>
      container.read(scanSessionProvider.notifier);
  ScanSession session() => container.read(scanSessionProvider)!;

  test('camera pages of a standard document are kept as captured', () async {
    final added = await controller().addFromCamera(ScanMode.document);

    expect(added.valueOrNull, 2);
    expect(session().pages, hasLength(2));
    for (final page in session().pages) {
      expect(page.adjustments, ImageAdjustments.none);
      expect(page.quad, isNull);
      expect(page.cropAttempted, isFalse);
      expect(p.isWithin(storage.root.path, page.sourcePath), isTrue);
    }
  });

  test('the capture mode drives the default processing', () async {
    await controller().addFromCamera(ScanMode.receipt);

    expect(
      session().pages.first.adjustments,
      ScanMode.receipt.preset.adjustments,
    );
  });

  test('imported photos get the detected outline, or none', () async {
    await controller().addFromGallery(ScanMode.document);
    expect(session().pages.every((page) => page.quad == Quad.full), isTrue);
    expect(session().pages.every((page) => page.cropAttempted), isTrue);

    images.detected = null;
    await controller().addFromGallery(ScanMode.document);
    expect(session().pages, hasLength(4));
    expect(session().pages.last.quad, isNull);
  });

  test('a cancelled capture leaves no session behind', () async {
    capture.forced = const Err(CancelledFailure());

    final result = await controller().addFromCamera(ScanMode.document);

    expect(result.failureOrNull, isA<CancelledFailure>());
    expect(container.read(scanSessionProvider), isNull);
  });

  test('pages can be reordered, duplicated, edited and removed', () async {
    await controller().addFromCamera(ScanMode.document);
    final first = session().pages[0];
    final second = session().pages[1];

    controller().reorder(0, 1);
    expect(session().pages.map((page) => page.id), [second.id, first.id]);

    controller().duplicate(first.id);
    expect(session().pages, hasLength(3));
    expect(session().pages[2].sourcePath, first.sourcePath);
    expect(session().pages[2].id, isNot(first.id));

    controller().rotate(first.id);
    controller().setFilter(first.id, ScanFilter.blackAndWhite);
    final edited = session().pages[1];
    expect(edited.adjustments.quarterTurns, 1);
    expect(edited.adjustments.filter, ScanFilter.blackAndWhite);

    controller().remove(second.id);
    expect(session().pages.any((page) => page.id == second.id), isFalse);
  });

  test('exporting a PDF registers it and ends the session', () async {
    await controller().addFromCamera(ScanMode.document);
    final sessionId = session().id;
    final progress = <int>[];

    final result = await controller().exportPdf(
      'Facture: mars',
      onProgress: (done, total) => progress.add(done),
    );

    final document = result.valueOrNull!;
    expect(document.fileType, DocumentFileType.pdf);
    expect(document.source, DocumentSource.scan);
    expect(document.pageCount, 2);
    expect(document.name, 'Facture mars');
    expect(document.thumbnailPath, isNotNull);
    expect(await storage.exists(document.filePath), isTrue);
    expect(progress, [1, 2]);
    expect(images.renders, hasLength(2));

    final repository = container.read(documentRepositoryProvider);
    final pages = (await repository.pagesOf(document.id)).valueOrNull!;
    expect(pages, hasLength(2));
    expect(container.read(scanSessionProvider), isNull);
    expect(
      await Directory(
        p.join(storage.directoryOf(StorageArea.sessions).path, sessionId),
      ).exists(),
      isFalse,
    );
  });

  test('a failed export leaves no file and keeps the session', () async {
    await controller().addFromCamera(ScanMode.document);
    images.failRender = true;

    final result = await controller().exportPdf('Contrat');

    expect(result.failureOrNull, isA<ImageFailure>());
    expect(container.read(scanSessionProvider), isNotNull);
    expect(await storage.usedBytes(StorageArea.documents), 0);
    expect(await storage.usedBytes(StorageArea.pages), 0);
    final repository = container.read(documentRepositoryProvider);
    expect(
      (await repository.query(const DocumentQuery())).valueOrNull,
      isEmpty,
    );
  });

  test('exporting images creates one JPG document per page', () async {
    await controller().addFromCamera(ScanMode.document);

    final result = await controller().exportImages('Photos');

    expect(result.valueOrNull, 2);
    final repository = container.read(documentRepositoryProvider);
    final documents = (await repository.query(
      const DocumentQuery(
        sort: DocumentSort(DocumentSortField.name, ascending: true),
      ),
    )).valueOrNull!;
    expect(documents.map((d) => d.name), ['Photos 1', 'Photos 2']);
    expect(documents.every((d) => d.fileType == DocumentFileType.jpg), isTrue);
    expect(container.read(scanSessionProvider), isNull);
  });

  test('a manual crop replaces the detected outline and is rendered', () async {
    await controller().addFromGallery(ScanMode.document);
    final page = session().pages.first;
    const manual = Quad(
      topLeft: NormalizedPoint(0.1, 0.1),
      topRight: NormalizedPoint(0.9, 0.12),
      bottomRight: NormalizedPoint(0.88, 0.9),
      bottomLeft: NormalizedPoint(0.12, 0.92),
    );

    controller().setQuad(page.id, manual);
    expect(session().pages.first.quad, manual);
    expect(session().pages.first.cropAttempted, isFalse);

    await controller().exportPdf('Recadré');
    expect(images.renders.first.quad, manual);

    await controller().addFromGallery(ScanMode.document);
    controller().setQuad(session().pages.first.id, null);
    expect(session().pages.first.quad, isNull);
  });

  test('exporting without a session fails cleanly', () async {
    final result = await controller().exportPdf('Vide');

    expect(
      result.failureOrNull,
      const ScanFailure(ScanFailureKind.sessionNotFound),
    );
  });
}
