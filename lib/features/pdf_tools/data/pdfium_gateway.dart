import 'dart:io';
import 'dart:typed_data';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_io.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_open_classifier.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfium;

/// Access to PDFium through pdfrx_engine, which runs every native call on
/// its own background worker.
///
/// Owns the three things the operations share: lazy initialization, opening
/// a file with a precise failure, and the engine's temporary files.
class PdfiumGateway {
  PdfiumGateway({required this._initialize, required this._tempDirectory});

  final Future<void> Function() _initialize;
  final Directory Function() _tempDirectory;
  Future<void>? _ready;
  int _sequence = 0;

  /// Loads the native library once. A failed attempt is retried by the next
  /// call. Throws `PdfFailure(engineUnavailable)`.
  Future<void> ensureReady() async {
    final pending = _ready ??= Future<void>.sync(_initialize);
    try {
      await pending;
    } catch (error) {
      if (identical(_ready, pending)) _ready = null;
      throw FailureException(
        PdfFailure(
          PdfFailureKind.engineUnavailable,
          debugMessage: error.runtimeType.toString(),
        ),
      );
    }
  }

  /// Opens [path]. The caller disposes the document.
  ///
  /// Throws `StorageFailure(notFound)`, `PdfFailure(passwordRequired)`,
  /// `PdfFailure(wrongPassword)`, `PdfFailure(unsupported)` or
  /// `PdfFailure(corrupted)`.
  Future<pdfium.PdfDocument> open(String path, {String? password}) async {
    await ensureReady();
    if (!await File(path).exists()) {
      throw const FailureException(StorageFailure(StorageFailureKind.notFound));
    }
    try {
      return await pdfium.PdfDocument.openFile(
        path,
        passwordProvider: pdfium.createSimplePasswordProvider(password),
      );
    } on pdfium.PdfPasswordException {
      throw FailureException(
        await runInIsolate(classifyOpenFailure, (
          path: path,
          password: password,
        )),
      );
    } on pdfium.PdfException catch (error) {
      throw FailureException(switch (error.errorCode) {
        2 => const StorageFailure(StorageFailureKind.readError),
        5 => const PdfFailure(PdfFailureKind.unsupported),
        _ => const PdfFailure(PdfFailureKind.corrupted),
      });
    }
  }

  /// Opens [path] and makes sure it has at least one page.
  Future<pdfium.PdfDocument> openNonEmpty(
    String path, {
    String? password,
  }) async {
    final document = await open(path, password: password);
    if (document.pages.isEmpty) {
      await document.dispose();
      throw const FailureException(PdfFailure(PdfFailureKind.emptyDocument));
    }
    return document;
  }

  /// Serializes a new document made of [pages], which may come from several
  /// open documents. Page objects are imported as they are (no rendering);
  /// nothing else of the sources is carried over, so removed pages leave no
  /// trace in the result.
  Future<Uint8List> assemble(List<pdfium.PdfPage> pages) async {
    final document = await pdfium.PdfDocument.createNew(
      sourceName: 'mds:assembled:${_sequence++}',
    );
    try {
      document.pages = pages;
      return await document.encodePdf();
    } finally {
      await document.dispose();
    }
  }

  /// Full rewrite of [document] by PDFium, without its protection.
  Future<Uint8List> rewrite(pdfium.PdfDocument document) =>
      document.encodePdf(removeSecurity: document.isEncrypted);

  /// Reserves a unique path in the temporary area. The file is not created.
  Future<String> newTempPath(String extension) async {
    final directory = _tempDirectory();
    await directory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return p.join(directory.path, 'pdf_${stamp}_${_sequence++}.$extension');
  }

  /// Opens [path] and returns a file the pure-Dart tools can read: [path]
  /// itself, or a temporary unprotected copy when the file is encrypted.
  /// The caller must call [PlainSource.release].
  Future<PlainSource> plainSource(String path, {String? password}) async {
    final document = await openNonEmpty(path, password: password);
    String? copy;
    try {
      final pages = [
        for (final page in document.pages)
          (width: page.width, height: page.height),
      ];
      if (document.isEncrypted) {
        copy = await newTempPath('pdf');
        await File(copy).writeAsBytes(await rewrite(document), flush: true);
      }
      return PlainSource._(copy ?? path, pages, copy);
    } catch (_) {
      if (copy != null) await deleteQuietly(copy);
      rethrow;
    } finally {
      await document.dispose();
    }
  }

  /// Runs [action] on the [plainSource] of [path] and releases it when
  /// [action] completes, whatever the outcome.
  Future<T> withPlainSourcePages<T>(
    String path,
    String? password,
    Future<T> Function(String sourcePath, List<PageDims> pages) action,
  ) async {
    final source = await plainSource(path, password: password);
    try {
      return await action(source.path, source.pages);
    } finally {
      await source.release();
    }
  }

  /// [withPlainSourcePages] for callers that only need the page count.
  Future<T> withPlainSource<T>(
    String path,
    String? password,
    Future<T> Function(String sourcePath, int pageCount) action,
  ) => withPlainSourcePages(
    path,
    password,
    (source, pages) => action(source, pages.length),
  );

  /// Runs [worker] on [sourcePath]; when the pure-Dart parser rejects a file
  /// PDFium reads (the worker answers `PdfFailure(corrupted)`), runs it once
  /// more on a copy rewritten by PDFium, whose output is always well-formed.
  /// A second refusal is reported as `PdfFailure(operationFailed)`: the file
  /// itself opens fine.
  Future<Result<T>> withParserFallback<T>(
    String sourcePath,
    Future<Result<T>> Function(String sourcePath) worker,
  ) async {
    final first = await worker(sourcePath);
    if (!_parserGaveUp(first)) return first;
    final normalized = await newTempPath('pdf');
    try {
      final document = await open(sourcePath);
      try {
        await File(
          normalized,
        ).writeAsBytes(await rewrite(document), flush: true);
      } finally {
        await document.dispose();
      }
      final second = await worker(normalized);
      if (!_parserGaveUp(second)) return second;
      return Err(
        PdfFailure(
          PdfFailureKind.operationFailed,
          debugMessage: second.failureOrNull?.debugMessage,
        ),
      );
    } finally {
      await deleteQuietly(normalized);
    }
  }

  static bool _parserGaveUp(Result<Object?> result) {
    final failure = result.failureOrNull;
    return failure is PdfFailure && failure.kind == PdfFailureKind.corrupted;
  }

  /// Page count of [path] as PDFium reads it, or null when it cannot be
  /// opened with [password]. Used to check an output before handing it over.
  Future<int?> pageCountOrNull(String path, {String? password}) async {
    try {
      final document = await open(path, password: password);
      try {
        return document.pages.length;
      } finally {
        await document.dispose();
      }
    } on FailureException {
      return null;
    } on pdfium.PdfException {
      return null;
    }
  }

  /// True when PDFium reads [path] as exactly the pages [expected], in
  /// order (sizes compared within half a point). This is how an output
  /// written by the pure-Dart tools is checked before it is handed over.
  Future<bool> pagesMatch(String path, List<PageDims> expected) async {
    try {
      final document = await open(path);
      try {
        final pages = document.pages;
        if (pages.length != expected.length) return false;
        for (var i = 0; i < expected.length; i++) {
          if ((pages[i].width - expected[i].width).abs() > 0.5 ||
              (pages[i].height - expected[i].height).abs() > 0.5) {
            return false;
          }
        }
        return true;
      } finally {
        await document.dispose();
      }
    } on FailureException {
      return false;
    } on pdfium.PdfException {
      return false;
    }
  }
}

/// Displayed size of a page, in points.
typedef PageDims = ({double width, double height});

/// A file readable without a password, with the pages PDFium sees in it.
class PlainSource {
  const PlainSource._(this.path, this.pages, this._temporaryCopy);

  final String path;
  final List<PageDims> pages;
  final String? _temporaryCopy;

  /// Deletes the temporary copy, if one was made.
  Future<void> release() async {
    final copy = _temporaryCopy;
    if (copy != null) await deleteQuietly(copy);
  }
}
