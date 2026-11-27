import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/features/ocr/data/docx_builder.dart';
import 'package:md_scanner/features/ocr/domain/text_recognition.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Separator placed between the pages of a multi-page recognition.
const String kOcrPageBreak = '\f';

/// Runs text recognition on library documents, stores the (possibly
/// corrected) text and exports it.
class OcrService {
  OcrService({
    required this._recognizer,
    required this._pdfEngine,
    required this._storage,
    required this._texts,
    required this._documents,
    this._logger,
  });

  final TextRecognitionService _recognizer;
  final PdfEngine _pdfEngine;
  final FileStorage _storage;
  final OcrTextRepository _texts;
  final DocumentRepository _documents;
  final AppLogger? _logger;

  static bool supports(DocumentEntity document) =>
      document.fileType.isImage || document.fileType == DocumentFileType.pdf;

  /// Recognizes the text of an image or of every page of a PDF, one page at
  /// a time. Fails with `OcrFailure(noTextFound)` when nothing was read.
  Future<Result<String>> recognize(
    DocumentEntity document, {
    String? password,
    void Function(int done, int total)? onProgress,
  }) => guard(() async {
    final source = _storage.absolutePath(document.filePath);
    final pages = <String>[];
    if (document.fileType.isImage) {
      pages.add(_unwrap(await _recognizer.recognize(source)).text.trim());
      onProgress?.call(1, 1);
    } else if (document.fileType == DocumentFileType.pdf) {
      final workDirectory = Directory(
        p.join(_storage.directoryOf(StorageArea.temp).path, const Uuid().v4()),
      );
      await workDirectory.create(recursive: true);
      try {
        final rendered = _unwrap(
          await _pdfEngine.pdfToImages(
            path: source,
            outputDirectory: workDirectory.path,
            dpi: 200,
            password: password,
          ),
        );
        for (var i = 0; i < rendered.length; i++) {
          final page = _unwrap(await _recognizer.recognize(rendered[i].path));
          pages.add(page.text.trim());
          await File(rendered[i].path).delete();
          onProgress?.call(i + 1, rendered.length);
        }
      } finally {
        if (await workDirectory.exists()) {
          await workDirectory.delete(recursive: true);
        }
      }
    } else {
      throw const FailureException(
        OcrFailure(OcrFailureKind.recognitionFailed, debugMessage: 'file_type'),
      );
    }
    if (pages.every((page) => page.isEmpty)) {
      throw const FailureException(OcrFailure(OcrFailureKind.noTextFound));
    }
    _logger?.info('ocr.completed', {'pages': pages.length});
    return pages.join('\n$kOcrPageBreak\n');
  });

  Future<Result<String?>> savedText(String documentId) =>
      _texts.textOf(documentId);

  /// Replaces the text stored for the document, so the library search finds
  /// the document by its content.
  Future<Result<void>> saveText(String documentId, String text) async {
    final cleared = await _texts.deleteFor(documentId);
    if (cleared.isFailure) return cleared;
    return _texts.save(documentId: documentId, text: text, language: 'latin');
  }

  Future<Result<DocumentEntity>> exportTxt(String name, String text) => _export(
    name,
    DocumentFileType.txt,
    utf8.encode(text.replaceAll('\r\n', '\n').replaceAll(kOcrPageBreak, '')),
  );

  Future<Result<DocumentEntity>> exportDocx(String name, String text) =>
      _export(name, DocumentFileType.docx, buildDocx(text: text, title: name));

  Future<Result<DocumentEntity>> _export(
    String name,
    DocumentFileType type,
    List<int> bytes,
  ) async {
    final path = _storage.allocate(
      StorageArea.documents,
      extension: type.extension,
    );
    final result = await guard(() async {
      await _storage.file(path).writeAsBytes(bytes, flush: true);
      return _unwrap(
        await _documents.register(
          NewDocument(
            name: sanitizeFileName(name),
            filePath: path,
            fileType: type,
            source: DocumentSource.ocr,
          ),
        ),
      );
    });
    if (result.isFailure) await _storage.delete(path);
    return result;
  }

  T _unwrap<T>(Result<T> result) => switch (result) {
    Success<T>(:final value) => value,
    Err<T>(:final failure) => throw FailureException(failure),
  };
}

final ocrServiceProvider = Provider<OcrService>(
  (ref) => OcrService(
    recognizer: ref.watch(textRecognitionServiceProvider),
    pdfEngine: ref.watch(pdfEngineProvider),
    storage: ref.watch(fileStorageProvider),
    texts: ref.watch(ocrTextRepositoryProvider),
    documents: ref.watch(documentRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
