import 'dart:io';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_io.dart';
import 'package:md_scanner/features/pdf_tools/data/pdfium_gateway.dart';
import 'package:md_scanner/features/pdf_tools/domain/page_range.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfium;

const FailureException _invalidRange = FailureException(
  PdfFailure(PdfFailureKind.invalidPageRange),
);

const FailureException _emptyDocument = FailureException(
  PdfFailure(PdfFailureKind.emptyDocument),
);

/// Page-level operations done by PDFium: page objects are copied or moved
/// as they are, never rendered. Methods throw `FailureException`.
class PdfStructureOps {
  const PdfStructureOps(this._gateway);

  final PdfiumGateway _gateway;

  Future<PdfOutput> merge({
    required List<String> inputPaths,
    required String outputPath,
    required Map<String, String> passwords,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) async {
    if (inputPaths.isEmpty) throw _emptyDocument;
    final sources = <pdfium.PdfDocument>[];
    try {
      final pages = <pdfium.PdfPage>[];
      final steps = inputPaths.length + 1;
      for (var i = 0; i < inputPaths.length; i++) {
        throwIfCancelled(isCancelled);
        final source = await _gateway.open(
          inputPaths[i],
          password: passwords[inputPaths[i]],
        );
        sources.add(source);
        pages.addAll(source.pages);
        onProgress?.call(i + 1, steps);
      }
      if (pages.isEmpty) throw _emptyDocument;
      throwIfCancelled(isCancelled);
      final bytes = await _gateway.assemble(pages);
      throwIfCancelled(isCancelled);
      await writeAtomically(outputPath, bytes);
      onProgress?.call(steps, steps);
      return PdfOutput(
        path: outputPath,
        pageCount: pages.length,
        fileSize: bytes.length,
      );
    } finally {
      for (final source in sources) {
        await source.dispose();
      }
    }
  }

  Future<List<PdfOutput>> split({
    required String path,
    required String outputDirectory,
    required List<PageRange> ranges,
    required String fileNamePrefix,
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) async {
    final document = await _gateway.openNonEmpty(path, password: password);
    final written = <PdfOutput>[];
    try {
      final pageCount = document.pages.length;
      if (ranges.isEmpty || ranges.any((r) => !r.isValidFor(pageCount))) {
        throw _invalidRange;
      }
      final prefix = _safeFileName(fileNamePrefix);
      await Directory(outputDirectory).create(recursive: true);
      for (var i = 0; i < ranges.length; i++) {
        throwIfCancelled(isCancelled);
        final pages = [
          for (final index in ranges[i].indexes(pageCount))
            document.pages[index],
        ];
        final bytes = await _gateway.assemble(pages);
        final number = (i + 1).toString().padLeft(3, '0');
        final target = p.join(outputDirectory, '${prefix}_$number.pdf');
        await writeAtomically(target, bytes);
        written.add(
          PdfOutput(
            path: target,
            pageCount: pages.length,
            fileSize: bytes.length,
          ),
        );
        onProgress?.call(i + 1, ranges.length);
      }
      return written;
    } catch (_) {
      for (final output in written) {
        await deleteQuietly(output.path);
      }
      rethrow;
    } finally {
      await document.dispose();
    }
  }

  Future<PdfOutput> extractPages({
    required String path,
    required String outputPath,
    required List<int> pages,
    String? password,
  }) async {
    final document = await _gateway.openNonEmpty(path, password: password);
    try {
      final pageCount = document.pages.length;
      if (pages.isEmpty || pages.any((i) => i < 0 || i >= pageCount)) {
        throw _invalidRange;
      }
      final bytes = await _gateway.assemble([
        for (final index in pages) document.pages[index],
      ]);
      await writeAtomically(outputPath, bytes);
      return PdfOutput(
        path: outputPath,
        pageCount: pages.length,
        fileSize: bytes.length,
      );
    } finally {
      await document.dispose();
    }
  }

  Future<PdfOutput> deletePages({
    required String path,
    required String outputPath,
    required Set<int> pages,
    String? password,
  }) async {
    final document = await _gateway.openNonEmpty(path, password: password);
    try {
      final pageCount = document.pages.length;
      if (pages.isEmpty || pages.any((i) => i < 0 || i >= pageCount)) {
        throw _invalidRange;
      }
      final kept = [
        for (var i = 0; i < pageCount; i++)
          if (!pages.contains(i)) document.pages[i],
      ];
      if (kept.isEmpty) throw _emptyDocument;
      // A new document is assembled rather than editing this one in place:
      // an in-place save keeps the objects of the removed pages in the file.
      final bytes = await _gateway.assemble(kept);
      await writeAtomically(outputPath, bytes);
      return PdfOutput(
        path: outputPath,
        pageCount: kept.length,
        fileSize: bytes.length,
      );
    } finally {
      await document.dispose();
    }
  }

  Future<PdfOutput> reorderPages({
    required String path,
    required String outputPath,
    required List<int> order,
    String? password,
  }) async {
    final document = await _gateway.openNonEmpty(path, password: password);
    try {
      final pageCount = document.pages.length;
      final isPermutation =
          order.length == pageCount &&
          order.toSet().length == pageCount &&
          order.every((i) => i >= 0 && i < pageCount);
      if (!isPermutation) throw _invalidRange;
      // A new document is assembled: PDFium does not persist an in-place
      // permutation of the page list when the document is saved.
      final bytes = await _gateway.assemble([
        for (final index in order) document.pages[index],
      ]);
      await writeAtomically(outputPath, bytes);
      return PdfOutput(
        path: outputPath,
        pageCount: pageCount,
        fileSize: bytes.length,
      );
    } finally {
      await document.dispose();
    }
  }

  Future<PdfOutput> rotatePages({
    required String path,
    required String outputPath,
    required Map<int, int> quarterTurns,
    String? password,
  }) async {
    final document = await _gateway.openNonEmpty(path, password: password);
    try {
      final pageCount = document.pages.length;
      if (quarterTurns.isEmpty ||
          quarterTurns.keys.any((i) => i < 0 || i >= pageCount)) {
        throw _invalidRange;
      }
      final original = document.pages;
      document.pages = [
        for (var i = 0; i < pageCount; i++)
          original[i].rotatedBy(
            pdfium.PdfPageRotation.values[((quarterTurns[i] ?? 0) % 4 + 4) % 4],
          ),
      ];
      final bytes = await _gateway.rewrite(document);
      await writeAtomically(outputPath, bytes);
      return PdfOutput(
        path: outputPath,
        pageCount: pageCount,
        fileSize: bytes.length,
      );
    } finally {
      await document.dispose();
    }
  }

  /// Writes an unprotected copy of a document opened with [password].
  Future<PdfOutput> unlock({
    required String path,
    required String outputPath,
    required String password,
  }) async {
    final document = await _gateway.openNonEmpty(path, password: password);
    try {
      final pageCount = document.pages.length;
      if (!document.isEncrypted) {
        // Nothing to remove: the result is the file itself.
        final partial = partialPathOf(outputPath);
        try {
          await File(partial).parent.create(recursive: true);
          await File(path).copy(partial);
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
      }
      final bytes = await _gateway.rewrite(document);
      await writeAtomically(outputPath, bytes);
      return PdfOutput(
        path: outputPath,
        pageCount: pageCount,
        fileSize: bytes.length,
      );
    } finally {
      await document.dispose();
    }
  }
}

/// Keeps a prefix usable as a file name on every file system.
String _safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty ? 'part' : cleaned;
}
