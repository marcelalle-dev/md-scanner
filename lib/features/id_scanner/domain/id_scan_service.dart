import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/features/id_scanner/domain/id_parser.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';
import 'package:md_scanner/features/ocr/domain/text_recognition.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:uuid/uuid.dart';

/// One captured side of an identity document.
class IdSide {
  const IdSide({required this.path, required this.imported});

  /// Absolute path of the working copy (session storage).
  final String path;

  /// True for a gallery photo: its outline still has to be detected. The
  /// camera scanner already delivers a cropped image.
  final bool imported;
}

/// Workflow of the ID scanner. Working copies live in a session folder that
/// is deleted as soon as the screen closes: nothing about an identity
/// document is kept unless the user saves it.
class IdScanService {
  IdScanService({
    required this._storage,
    required this._images,
    required this._recognizer,
    required this._pdfEngine,
    required this._documents,
  });

  final FileStorage _storage;
  final ImageProcessor _images;
  final TextRecognitionService _recognizer;
  final PdfEngine _pdfEngine;
  final DocumentRepository _documents;

  /// Copies a captured image into the session folder [sessionId].
  Future<Result<IdSide>> addSide(
    String sessionId,
    String sourcePath, {
    required bool imported,
  }) => guard(() async {
    final relative = await _storage.importFile(
      sourcePath,
      StorageArea.sessions,
      group: sessionId,
    );
    return IdSide(path: _storage.absolutePath(relative), imported: imported);
  });

  /// Runs text recognition on every side and extracts what it can.
  Future<Result<IdFields>> analyze(List<IdSide> sides) => guard(() async {
    final texts = <String>[];
    for (final side in sides) {
      final page = await _recognizer.recognize(side.path);
      texts.add(_unwrap(page).text);
    }
    return IdParser.parse(texts.join('\n'));
  });

  /// Renders the sides with the ID-card processing and saves them as one PDF.
  Future<Result<DocumentEntity>> savePdf(
    String name,
    List<IdSide> sides,
  ) async {
    final group = const Uuid().v4();
    final created = <String>[];
    final result = await guard(() async {
      final pages = <String>[];
      for (final side in sides) {
        final quad = side.imported
            ? (await _images.detectDocument(
                side.path,
                mode: ScanMode.idCard,
              )).valueOrNull
            : null;
        final page = _storage.allocate(
          StorageArea.pages,
          extension: 'jpg',
          group: group,
        );
        created.add(page);
        await _storage.file(page).parent.create(recursive: true);
        _unwrap(
          await _images.render(
            ImageRenderRequest(
              sourcePath: side.path,
              outputPath: _storage.absolutePath(page),
              quad: quad,
              adjustments: ScanMode.idCard.preset.adjustments,
              mode: ScanMode.idCard,
            ),
          ),
        );
        pages.add(page);
      }
      final pdf = _storage.allocate(StorageArea.documents, extension: 'pdf');
      created.add(pdf);
      final output = _unwrap(
        await _pdfEngine.imagesToPdf(
          imagePaths: [for (final page in pages) _storage.absolutePath(page)],
          outputPath: _storage.absolutePath(pdf),
          setup: const PdfPageSetup(margin: 36),
        ),
      );
      return _unwrap(
        await _documents.register(
          NewDocument(
            name: sanitizeFileName(name),
            filePath: pdf,
            fileType: DocumentFileType.pdf,
            source: DocumentSource.idScan,
            pageCount: output.pageCount,
            pageImagePaths: pages,
          ),
        ),
      );
    });
    if (result.isFailure) {
      for (final path in created) {
        await _storage.delete(path);
      }
    }
    return result;
  }

  /// Deletes every working copy of the session.
  Future<void> discard(String sessionId) =>
      _storage.deleteGroup(StorageArea.sessions, sessionId);

  T _unwrap<T>(Result<T> result) => switch (result) {
    Success<T>(:final value) => value,
    Err<T>(:final failure) => throw FailureException(failure),
  };
}

final idScanServiceProvider = Provider<IdScanService>(
  (ref) => IdScanService(
    storage: ref.watch(fileStorageProvider),
    images: ref.watch(imageProcessorProvider),
    recognizer: ref.watch(textRecognitionServiceProvider),
    pdfEngine: ref.watch(pdfEngineProvider),
    documents: ref.watch(documentRepositoryProvider),
  ),
);
