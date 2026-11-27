import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/features/pdf_tools/domain/page_range.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// A file chosen by the user as input of a tool.
class ToolInput {
  const ToolInput({required this.path, required this.name});

  final String path;

  /// Display name without extension, reused to name the result.
  final String name;
}

/// Parameters collected by the tool screen.
class ToolRequest {
  const ToolRequest({
    required this.tool,
    required this.inputs,
    required this.resultName,
    this.text = '',
    this.level = PdfCompressionLevel.balanced,
    this.quarterTurns = 1,
    this.inputPassword,
    this.pageNumber,
    this.verticalPosition = 2,
    this.signaturePath,
    this.signOnRight = true,
    this.placement,
  });

  final PdfTool tool;
  final List<ToolInput> inputs;

  /// Name given to the document(s) created in the library.
  final String resultName;

  /// Page ranges, password or watermark text, depending on the tool.
  final String text;
  final PdfCompressionLevel level;
  final int quarterTurns;

  /// Password of the input PDF when it is protected.
  final String? inputPassword;

  /// 1-based page targeted by the text and signature tools; null means the
  /// last page.
  final int? pageNumber;

  /// 0 top, 1 middle, 2 bottom (text tool).
  final int verticalPosition;

  /// PNG of the handwritten signature (signature tool).
  final String? signaturePath;
  final bool signOnRight;

  /// Position chosen on the page preview. When null, the text and signature
  /// tools fall back to their preset positions.
  final PdfNormalizedRect? placement;
}

class ToolOutcome {
  const ToolOutcome({required this.documents, this.compression});

  final List<DocumentEntity> documents;

  /// Set by the compress tool, including when nothing could be gained.
  final PdfCompressionResult? compression;
}

/// Runs a PDF tool on files and registers the results in the library.
class PdfToolRunner {
  PdfToolRunner(this._ref);

  final Ref _ref;

  FileStorage get _storage => _ref.read(fileStorageProvider);
  PdfEngine get _engine => _ref.read(pdfEngineProvider);

  Future<Result<ToolOutcome>> run(
    ToolRequest request, {
    PdfProgressCallback? onProgress,
  }) async {
    final created = <String>[];
    final result = await guard(() => _execute(request, created, onProgress));
    if (result.isFailure) {
      for (final path in created) {
        await _storage.delete(path);
      }
    }
    return result;
  }

  Future<ToolOutcome> _execute(
    ToolRequest request,
    List<String> created,
    PdfProgressCallback? onProgress,
  ) async {
    final input = request.inputs.first.path;
    final password = request.inputPassword;

    String newPdf() {
      final path = _storage.allocate(StorageArea.documents, extension: 'pdf');
      created.add(path);
      return path;
    }

    Future<ToolOutcome> registerPdf(String relative, int pageCount) async {
      final document = await _register(
        request.resultName,
        relative,
        DocumentFileType.pdf,
        pageCount,
      );
      return ToolOutcome(documents: [document]);
    }

    switch (request.tool) {
      case PdfTool.imagesToPdf:
        final path = newPdf();
        final output = _unwrap(
          await _engine.imagesToPdf(
            imagePaths: [for (final item in request.inputs) item.path],
            outputPath: _storage.absolutePath(path),
            onProgress: onProgress,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.merge:
        final path = newPdf();
        final output = _unwrap(
          await _engine.merge(
            inputPaths: [for (final item in request.inputs) item.path],
            outputPath: _storage.absolutePath(path),
            onProgress: onProgress,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.extract:
        final info = _unwrap(await _engine.inspect(input, password: password));
        final ranges = _unwrap(
          parsePageRanges(request.text, pageCount: info.pageCount),
        );
        final path = newPdf();
        final output = _unwrap(
          await _engine.extractPages(
            path: input,
            outputPath: _storage.absolutePath(path),
            pages: _indexes(ranges, info.pageCount),
            password: password,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.compress:
        final path = newPdf();
        final compression = _unwrap(
          await _engine.compress(
            path: input,
            outputPath: _storage.absolutePath(path),
            level: request.level,
            password: password,
          ),
        );
        if (!compression.reduced) {
          await _storage.delete(path);
          created.remove(path);
          return ToolOutcome(documents: const [], compression: compression);
        }
        final info = _unwrap(
          await _engine.inspect(_storage.absolutePath(path)),
        );
        final document = await _register(
          request.resultName,
          path,
          DocumentFileType.pdf,
          info.pageCount,
        );
        return ToolOutcome(documents: [document], compression: compression);
      case PdfTool.rotate:
        final info = _unwrap(await _engine.inspect(input, password: password));
        final path = newPdf();
        final output = _unwrap(
          await _engine.rotatePages(
            path: input,
            outputPath: _storage.absolutePath(path),
            quarterTurns: {
              for (var i = 0; i < info.pageCount; i++) i: request.quarterTurns,
            },
            password: password,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.protect:
        final path = newPdf();
        final output = _unwrap(
          await _engine.protect(
            path: input,
            outputPath: _storage.absolutePath(path),
            userPassword: request.text,
            currentPassword: password,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.unlock:
        final path = newPdf();
        final output = _unwrap(
          await _engine.unlock(
            path: input,
            outputPath: _storage.absolutePath(path),
            password: request.text,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.watermark:
        final path = newPdf();
        final output = _unwrap(
          await _engine.addWatermark(
            path: input,
            outputPath: _storage.absolutePath(path),
            watermark: PdfWatermark(text: request.text),
            password: password,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.pageNumbers:
        final path = newPdf();
        final output = _unwrap(
          await _engine.addPageNumbers(
            path: input,
            outputPath: _storage.absolutePath(path),
            password: password,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.addText:
        final info = _unwrap(await _engine.inspect(input, password: password));
        final path = newPdf();
        final output = _unwrap(
          await _engine.addText(
            path: input,
            outputPath: _storage.absolutePath(path),
            texts: [
              PdfTextStamp(
                pageIndex: _pageIndex(request.pageNumber, info.pageCount),
                text: request.text,
                x: request.placement?.left ?? 0.1,
                y:
                    request.placement?.top ??
                    const [0.08, 0.5, 0.9][request.verticalPosition.clamp(
                      0,
                      2,
                    )],
              ),
            ],
            password: password,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.sign:
        final info = _unwrap(await _engine.inspect(input, password: password));
        final path = newPdf();
        final output = _unwrap(
          await _engine.stampImage(
            path: input,
            outputPath: _storage.absolutePath(path),
            stamps: [
              PdfImageStamp(
                pageIndex: _pageIndex(request.pageNumber, info.pageCount),
                imagePath: request.signaturePath!,
                rect:
                    request.placement ??
                    PdfNormalizedRect(
                      left: request.signOnRight ? 0.55 : 0.08,
                      top: 0.82,
                      width: 0.37,
                      height: 0.12,
                    ),
              ),
            ],
            password: password,
          ),
        );
        return registerPdf(path, output.pageCount);
      case PdfTool.pdfToImages:
        return _pdfToImages(request, created, onProgress);
    }
  }

  Future<ToolOutcome> _pdfToImages(
    ToolRequest request,
    List<String> created,
    PdfProgressCallback? onProgress,
  ) async {
    final workDirectory = Directory(
      p.join(_storage.directoryOf(StorageArea.temp).path, const Uuid().v4()),
    );
    await workDirectory.create(recursive: true);
    try {
      final pages = _unwrap(
        await _engine.pdfToImages(
          path: request.inputs.first.path,
          outputDirectory: workDirectory.path,
          password: request.inputPassword,
          onProgress: onProgress,
        ),
      );
      final documents = <DocumentEntity>[];
      for (final page in pages) {
        final relative = await _storage.importFile(
          page.path,
          StorageArea.documents,
          extension: 'jpg',
        );
        created.add(relative);
        documents.add(
          await _register(
            '${request.resultName} ${page.pageIndex + 1}',
            relative,
            DocumentFileType.jpg,
            1,
          ),
        );
      }
      return ToolOutcome(documents: documents);
    } finally {
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  /// Converts a 1-based page number to an index; null targets the last page.
  int _pageIndex(int? pageNumber, int pageCount) {
    final number = pageNumber ?? pageCount;
    if (number < 1 || number > pageCount) {
      throw const FailureException(PdfFailure(PdfFailureKind.invalidPageRange));
    }
    return number - 1;
  }

  List<int> _indexes(List<PageRange> ranges, int pageCount) {
    final seen = <int>{};
    return [
      for (final range in ranges)
        for (final index in range.indexes(pageCount))
          if (seen.add(index)) index,
    ];
  }

  Future<DocumentEntity> _register(
    String name,
    String relativePath,
    DocumentFileType type,
    int pageCount,
  ) async => _unwrap(
    await _ref
        .read(documentRepositoryProvider)
        .register(
          NewDocument(
            name: sanitizeFileName(name),
            filePath: relativePath,
            fileType: type,
            source: DocumentSource.pdfTool,
            pageCount: pageCount,
          ),
        ),
  );

  T _unwrap<T>(Result<T> result) => switch (result) {
    Success<T>(:final value) => value,
    Err<T>(:final failure) => throw FailureException(failure),
  };
}

final pdfToolRunnerProvider = Provider<PdfToolRunner>(PdfToolRunner.new);

/// True when [failure] means the input PDF needs (another) password.
bool needsPassword(Failure failure) =>
    failure is PdfFailure &&
    (failure.kind == PdfFailureKind.passwordRequired ||
        failure.kind == PdfFailureKind.wrongPassword);
