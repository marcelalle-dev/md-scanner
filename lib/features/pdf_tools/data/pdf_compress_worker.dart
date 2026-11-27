import 'dart:io';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosPasswordException;
import 'package:pdf_document/pdf_document.dart' as pd;

/// Sendable arguments of [compressPdfFile].
class PdfCompressRequest {
  const PdfCompressRequest({
    required this.inputPath,
    required this.outputPath,
    required this.level,
  });

  final String inputPath;
  final String outputPath;
  final PdfCompressionLevel level;
}

/// Optimizer settings of each level.
///
/// Every level rebuilds the file (unreachable objects dropped, objects packed
/// in compressed streams, duplicate resources merged). The lossy levels also
/// downsample colour and gray images above the target resolution and
/// re-encode them. Font subsetting and resource pruning stay off: they
/// rewrite content the engine cannot verify afterwards.
pd.PdfCompressionOptions compressionOptionsFor(PdfCompressionLevel level) {
  final (double? dpi, int quality) = switch (level) {
    PdfCompressionLevel.low => (null, 85),
    PdfCompressionLevel.balanced => (150.0, 75),
    PdfCompressionLevel.high => (100.0, 50),
  };
  return pd.PdfCompressionOptions(
    removeUnusedResources: false,
    subsetFonts: false,
    targetDpi: dpi,
    jpegQuality: quality,
    allowInvalidateSignatures: true,
  );
}

/// Optimizes the unencrypted PDF at `inputPath`. A smaller file is written
/// to `outputPath`; otherwise nothing is written and the result reports
/// `reduced == false`. Sizes are those of the input given here.
/// Synchronous and CPU-bound: run it in a background isolate.
///
/// `PdfFailure(corrupted)` means the pure-Dart parser could not process the
/// file; the caller may retry on a copy rewritten by PDFium.
Result<PdfCompressionResult> compressPdfFile(PdfCompressRequest request) {
  try {
    final bytes = File(request.inputPath).readAsBytesSync();
    final document = pd.PdfDocument.open(bytes);
    if (document.cos.isEncrypted) {
      return const Err(PdfFailure(PdfFailureKind.passwordRequired));
    }
    final optimized = pd.PdfCompressor.optimize(
      document,
      options: compressionOptionsFor(request.level),
    );
    if (optimized.bytes.length >= bytes.length) {
      return Success(
        PdfCompressionResult(
          originalSize: bytes.length,
          compressedSize: bytes.length,
          reduced: false,
        ),
      );
    }
    File(request.outputPath).writeAsBytesSync(optimized.bytes, flush: true);
    return Success(
      PdfCompressionResult(
        originalSize: bytes.length,
        compressedSize: optimized.bytes.length,
        reduced: true,
      ),
    );
  } on CosPasswordException {
    return const Err(PdfFailure(PdfFailureKind.passwordRequired));
  } on FileSystemException catch (error) {
    return Err(failureFromError(error));
  } on Exception catch (error) {
    return Err(_unreadable(error));
  } on Error catch (error) {
    return Err(_unreadable(error));
  }
}

Failure _unreadable(Object error) => PdfFailure(
  PdfFailureKind.corrupted,
  debugMessage: 'compress.${error.runtimeType}',
);
