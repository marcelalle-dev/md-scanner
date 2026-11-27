import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosPasswordException;
import 'package:pdf_document/pdf_document.dart' as pd;

// Page-level operations in pure Dart. One importer copies all the pages of a
// call, so a font or an image shared by several pages is written once
// (PDFium, driven page by page, would copy it again for every page).
//
// Every function is synchronous and CPU-bound: run it in a background
// isolate. Inputs must be unencrypted. `PdfFailure(corrupted)` means the
// parser could not process the file; the caller then falls back on PDFium.

/// One file to write: the pages at [pages] (0-based), in that order.
class PdfExtractTarget {
  const PdfExtractTarget(this.outputPath, this.pages);

  final String outputPath;
  final List<int> pages;
}

/// Sendable arguments of [extractPdfPagesToFiles].
class PdfExtractRequest {
  const PdfExtractRequest({
    required this.inputPath,
    required this.targets,
    this.progress,
  });

  final String inputPath;
  final List<PdfExtractTarget> targets;

  /// Receives the number of targets written so far, after each one.
  final SendPort? progress;
}

/// Writes each target as a new document holding only its pages and what
/// they reference: nothing of the other pages is carried over.
Result<void> extractPdfPagesToFiles(PdfExtractRequest request) =>
    _guarded('extract', () {
      final document = _open(File(request.inputPath).readAsBytesSync());
      for (var i = 0; i < request.targets.length; i++) {
        final target = request.targets[i];
        File(
          target.outputPath,
        ).writeAsBytesSync(document.extractPages(target.pages), flush: true);
        request.progress?.send(i + 1);
      }
    });

/// Sendable arguments of [reorderPdfFile].
class PdfReorderRequest {
  const PdfReorderRequest({
    required this.inputPath,
    required this.outputPath,
    required this.order,
  });

  final String inputPath;
  final String outputPath;

  /// Entry i is the current index of the page that ends up at position i.
  final List<int> order;
}

/// Rewrites the page tree in the requested order. Every page is kept, so
/// the rest of the document (bookmarks, form fields, metadata) is too.
Result<void> reorderPdfFile(PdfReorderRequest request) =>
    _guarded('reorder', () {
      final editor = pd.PdfEditor(
        _open(File(request.inputPath).readAsBytesSync()),
      )..reorderPages(request.order);
      File(request.outputPath).writeAsBytesSync(editor.save(), flush: true);
    });

/// Sendable arguments of [mergePdfFiles].
class PdfMergeRequest {
  const PdfMergeRequest({required this.inputPaths, required this.outputPath});

  final List<String> inputPaths;
  final String outputPath;
}

/// Appends the pages of every other input to the first one, which keeps its
/// metadata and bookmarks; bookmarks and form fields of the others follow
/// their pages.
Result<void> mergePdfFiles(PdfMergeRequest request) => _guarded('merge', () {
  final Uint8List first = File(request.inputPaths.first).readAsBytesSync();
  final editor = pd.PdfEditor(_open(first));
  for (final path in request.inputPaths.skip(1)) {
    editor.appendPagesFrom(_open(File(path).readAsBytesSync()));
  }
  File(
    request.outputPath,
  ).writeAsBytesSync(editor.hasChanges ? editor.save() : first, flush: true);
});

pd.PdfDocument _open(Uint8List bytes) {
  final document = pd.PdfDocument.open(bytes);
  if (document.cos.isEncrypted) {
    throw const FailureException(PdfFailure(PdfFailureKind.passwordRequired));
  }
  return document;
}

Result<void> _guarded(String operation, void Function() body) {
  try {
    body();
    return const Success(null);
  } on FailureException catch (error) {
    return Err(error.failure);
  } on CosPasswordException {
    return const Err(PdfFailure(PdfFailureKind.passwordRequired));
  } on FileSystemException catch (error) {
    return Err(failureFromError(error));
  } on Exception catch (error) {
    return Err(_unreadable(operation, error));
  } on Error catch (error) {
    return Err(_unreadable(operation, error));
  }
}

Failure _unreadable(String operation, Object error) => PdfFailure(
  PdfFailureKind.corrupted,
  debugMessage: '$operation.${error.runtimeType}',
);
