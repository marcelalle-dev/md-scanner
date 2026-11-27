import 'dart:io';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/features/pdf_tools/data/image_pdf_writer.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_compress_worker.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_encryptor.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_io.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_raster_ops.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_stamper.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_structure_ops.dart';
import 'package:md_scanner/features/pdf_tools/data/pdfium_gateway.dart';
import 'package:md_scanner/features/pdf_tools/domain/page_range.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';

/// [PdfEngine] built on three libraries, each used where it is strongest:
///
/// - PDFium (through pdfrx_engine) opens, renders and reorganizes pages: it
///   is the most tolerant reader of real-world files;
/// - pdf_document / pdf_cos (pure Dart, in a background isolate) draw over
///   pages, optimize the file and write the AES-256 protection;
/// - a small sequential writer builds image documents straight to disk.
///
/// Whatever a pure-Dart step writes is opened again with PDFium before it
/// is handed over, so a faulty output is never delivered.
class PdfEngineImpl implements PdfEngine {
  /// [initializePdfium] loads the native library: `pdfrxFlutterInitialize`
  /// in the app, `pdfrxInitialize` in host tests. [tempDirectory] receives
  /// short-lived working copies, all deleted before a call returns.
  PdfEngineImpl({
    required Future<void> Function() initializePdfium,
    required Directory Function() tempDirectory,
    this._logger,
    DateTime Function()? clock,
  }) : _gateway = PdfiumGateway(
         initialize: initializePdfium,
         tempDirectory: tempDirectory,
       ),
       _clock = clock ?? DateTime.now;

  final PdfiumGateway _gateway;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  PdfStructureOps get _structure => PdfStructureOps(_gateway);
  PdfRasterOps get _raster => PdfRasterOps(_gateway);

  /// Runs [body], converts what it throws into a failure and records the
  /// outcome. Only counts, durations and failure kinds reach the journal.
  Future<Result<T>> _run<T>(
    String operation,
    Future<T> Function() body, {
    int Function(T value)? pagesOf,
  }) async {
    final watch = Stopwatch()..start();
    final result = await guardPdf(body);
    switch (result) {
      case Success<T>(:final value):
        _logger?.info('pdf.$operation', {
          'duration': watch.elapsed,
          'pages': pagesOf?.call(value),
        });
      case Err<T>(:final failure):
        if (failure is! CancelledFailure) {
          _logger?.failure('pdf.$operation.failed', failure);
        }
    }
    return result;
  }

  @override
  Future<Result<void>> ensureInitialized() =>
      _run('initialize', _gateway.ensureReady);

  @override
  Future<Result<PdfInfo>> inspect(String path, {String? password}) =>
      _run('inspect', () async {
        final document = await _gateway.openNonEmpty(path, password: password);
        try {
          return PdfInfo(
            pageCount: document.pages.length,
            isEncrypted: document.isEncrypted,
            pageSizes: [
              for (final page in document.pages)
                PdfPageSize(
                  page.width,
                  page.height,
                  rotationDegrees: page.rotation.index * 90,
                ),
            ],
            fileSize: await File(path).length(),
          );
        } finally {
          await document.dispose();
        }
      }, pagesOf: (info) => info.pageCount);

  @override
  Future<Result<PdfOutput>> imagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
    PdfPageSetup setup = const PdfPageSetup(),
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) => _run(
    'images_to_pdf',
    () => writeImagesPdf(
      imagePaths: imagePaths,
      outputPath: outputPath,
      setup: setup,
      createdAt: _clock(),
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
    pagesOf: _pages,
  );

  @override
  Future<Result<RenderedPage>> renderPage({
    required String path,
    required int pageIndex,
    required String outputPath,
    int? maxLongEdge,
    double? dpi,
    PdfImageFormat format = PdfImageFormat.jpeg,
    int jpegQuality = 90,
    String? password,
  }) => _run(
    'render_page',
    () => _raster.renderPage(
      path: path,
      pageIndex: pageIndex,
      outputPath: outputPath,
      maxLongEdge: maxLongEdge,
      dpi: dpi,
      format: format,
      jpegQuality: jpegQuality,
      password: password,
    ),
  );

  @override
  Future<Result<List<RenderedPage>>> pdfToImages({
    required String path,
    required String outputDirectory,
    PdfImageFormat format = PdfImageFormat.jpeg,
    double dpi = 150,
    List<int>? pages,
    int jpegQuality = 90,
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) => _run(
    'pdf_to_images',
    () => _raster.pdfToImages(
      path: path,
      outputDirectory: outputDirectory,
      format: format,
      dpi: dpi,
      pages: pages,
      jpegQuality: jpegQuality,
      password: password,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
    pagesOf: (rendered) => rendered.length,
  );

  @override
  Future<Result<PdfOutput>> merge({
    required List<String> inputPaths,
    required String outputPath,
    Map<String, String> passwords = const {},
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) => _run(
    'merge',
    () => _structure.merge(
      inputPaths: inputPaths,
      outputPath: outputPath,
      passwords: passwords,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
    pagesOf: _pages,
  );

  @override
  Future<Result<List<PdfOutput>>> split({
    required String path,
    required String outputDirectory,
    required List<PageRange> ranges,
    String fileNamePrefix = 'part',
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) => _run(
    'split',
    () => _structure.split(
      path: path,
      outputDirectory: outputDirectory,
      ranges: ranges,
      fileNamePrefix: fileNamePrefix,
      password: password,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
    pagesOf: (outputs) => outputs.fold(0, (sum, o) => sum + o.pageCount),
  );

  @override
  Future<Result<PdfOutput>> extractPages({
    required String path,
    required String outputPath,
    required List<int> pages,
    String? password,
  }) => _run(
    'extract_pages',
    () => _structure.extractPages(
      path: path,
      outputPath: outputPath,
      pages: pages,
      password: password,
    ),
    pagesOf: _pages,
  );

  @override
  Future<Result<PdfOutput>> deletePages({
    required String path,
    required String outputPath,
    required Set<int> pages,
    String? password,
  }) => _run(
    'delete_pages',
    () => _structure.deletePages(
      path: path,
      outputPath: outputPath,
      pages: pages,
      password: password,
    ),
    pagesOf: _pages,
  );

  @override
  Future<Result<PdfOutput>> reorderPages({
    required String path,
    required String outputPath,
    required List<int> order,
    String? password,
  }) => _run(
    'reorder_pages',
    () => _structure.reorderPages(
      path: path,
      outputPath: outputPath,
      order: order,
      password: password,
    ),
    pagesOf: _pages,
  );

  @override
  Future<Result<PdfOutput>> rotatePages({
    required String path,
    required String outputPath,
    required Map<int, int> quarterTurns,
    String? password,
  }) => _run(
    'rotate_pages',
    () => _structure.rotatePages(
      path: path,
      outputPath: outputPath,
      quarterTurns: quarterTurns,
      password: password,
    ),
    pagesOf: _pages,
  );

  @override
  Future<Result<PdfCompressionResult>> compress({
    required String path,
    required String outputPath,
    required PdfCompressionLevel level,
    String? password,
    PdfCancellationCheck? isCancelled,
  }) => _run(
    'compress',
    () => _gateway.withPlainSource(path, password, (source, pageCount) async {
      final originalSize = await File(path).length();
      final unchanged = PdfCompressionResult(
        originalSize: originalSize,
        compressedSize: originalSize,
        reduced: false,
      );
      final partial = partialPathOf(outputPath);
      await File(partial).parent.create(recursive: true);
      try {
        final outcome = valueOrThrow(
          await _gateway.withParserFallback(
            source,
            (input) => runCancellable(
              compressPdfFile,
              PdfCompressRequest(
                inputPath: input,
                outputPath: partial,
                level: level,
              ),
              isCancelled,
            ),
          ),
        );
        // The comparison that counts is against the user's file, and a
        // result PDFium cannot read back is no result at all.
        final keep =
            outcome.reduced &&
            outcome.compressedSize < originalSize &&
            await _gateway.pageCountOrNull(partial) == pageCount;
        if (!keep) {
          await deleteQuietly(partial);
          return unchanged;
        }
        final size = await commitPartial(outputPath);
        return PdfCompressionResult(
          originalSize: originalSize,
          compressedSize: size,
          reduced: true,
        );
      } catch (_) {
        await deleteQuietly(partial);
        rethrow;
      }
    }),
  );

  @override
  Future<Result<PdfOutput>> addWatermark({
    required String path,
    required String outputPath,
    required PdfWatermark watermark,
    String? password,
  }) =>
      _stamp('watermark', path, outputPath, password, WatermarkJob(watermark));

  @override
  Future<Result<PdfOutput>> addPageNumbers({
    required String path,
    required String outputPath,
    PdfPageNumbering numbering = const PdfPageNumbering(),
    String? password,
  }) => _stamp(
    'page_numbers',
    path,
    outputPath,
    password,
    PageNumbersJob(numbering),
  );

  @override
  Future<Result<PdfOutput>> addText({
    required String path,
    required String outputPath,
    required List<PdfTextStamp> texts,
    String? password,
  }) => _stamp('text', path, outputPath, password, TextsJob(texts));

  @override
  Future<Result<PdfOutput>> stampImage({
    required String path,
    required String outputPath,
    required List<PdfImageStamp> stamps,
    String? password,
  }) => _stamp('stamp_image', path, outputPath, password, ImagesJob(stamps));

  Future<Result<PdfOutput>> _stamp(
    String operation,
    String path,
    String outputPath,
    String? password,
    StampJob job,
  ) => _run(
    operation,
    () => _gateway.withPlainSource(path, password, (source, pageCount) async {
      final partial = partialPathOf(outputPath);
      await File(partial).parent.create(recursive: true);
      try {
        valueOrThrow(
          await _gateway.withParserFallback(
            source,
            (input) => runInIsolate(
              stampPdfFile,
              StampRequest(inputPath: input, outputPath: partial, job: job),
            ),
          ),
        );
        if (await _gateway.pageCountOrNull(partial) != pageCount) {
          throw const FailureException(
            PdfFailure(
              PdfFailureKind.operationFailed,
              debugMessage: 'stamp.verification',
            ),
          );
        }
        final size = await commitPartial(outputPath);
        return PdfOutput(
          path: outputPath,
          pageCount: pageCount,
          fileSize: size,
        );
      } catch (_) {
        await deleteQuietly(partial);
        rethrow;
      }
    }),
    pagesOf: _pages,
  );

  @override
  Future<Result<PdfOutput>> protect({
    required String path,
    required String outputPath,
    required String userPassword,
    String? ownerPassword,
    String? currentPassword,
  }) => _run('protect', () {
    final owner = ownerPassword ?? userPassword;
    final invalid =
        validatePdfPassword(userPassword) ?? validatePdfPassword(owner);
    if (invalid != null) throw FailureException(invalid);
    return _gateway.withPlainSource(path, currentPassword, (
      source,
      pageCount,
    ) async {
      final partial = partialPathOf(outputPath);
      await File(partial).parent.create(recursive: true);
      try {
        valueOrThrow(
          await _gateway.withParserFallback(
            source,
            (input) => runInIsolate(
              encryptPdfFile,
              PdfEncryptRequest(
                inputPath: input,
                outputPath: partial,
                userPassword: userPassword,
                ownerPassword: owner,
              ),
            ),
          ),
        );
        // A protected file its own passwords cannot open would lock the
        // user out of the document: check both with PDFium first.
        for (final password in {userPassword, owner}) {
          final readable = await _gateway.pageCountOrNull(
            partial,
            password: password,
          );
          if (readable != pageCount) {
            throw const FailureException(
              PdfFailure(
                PdfFailureKind.operationFailed,
                debugMessage: 'protect.verification',
              ),
            );
          }
        }
        final size = await commitPartial(outputPath);
        return PdfOutput(
          path: outputPath,
          pageCount: pageCount,
          fileSize: size,
        );
      } catch (_) {
        await deleteQuietly(partial);
        rethrow;
      }
    });
  }, pagesOf: _pages);

  @override
  Future<Result<PdfOutput>> unlock({
    required String path,
    required String outputPath,
    required String password,
  }) => _run(
    'unlock',
    () => _structure.unlock(
      path: path,
      outputPath: outputPath,
      password: password,
    ),
    pagesOf: _pages,
  );

  static int _pages(PdfOutput output) => output.pageCount;
}
