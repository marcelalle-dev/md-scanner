import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_io.dart';
import 'package:md_scanner/features/pdf_tools/data/pdfium_gateway.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfium;

/// Largest image a page is rendered to. A4 at 300 dpi is 8.7 megapixels;
/// beyond this budget the bitmap and its encoder no longer fit a phone.
const int kMaxRenderPixels = 24000000;

const double kDefaultRenderDpi = 150;

/// Pixel size of a page of [pageWidth] x [pageHeight] points rendered at
/// [dpi], reduced to respect [maxLongEdge] and [kMaxRenderPixels].
({int width, int height}) rasterSizeFor(
  double pageWidth,
  double pageHeight, {
  double? dpi,
  int? maxLongEdge,
}) {
  var scale = (dpi ?? kDefaultRenderDpi) / 72;
  final longEdge = math.max(pageWidth, pageHeight);
  if (maxLongEdge != null && longEdge * scale > maxLongEdge) {
    scale = maxLongEdge / longEdge;
  }
  final pixels = pageWidth * scale * pageHeight * scale;
  if (pixels > kMaxRenderPixels) {
    scale *= math.sqrt(kMaxRenderPixels / pixels);
  }
  return (
    width: math.max(1, (pageWidth * scale).round()),
    height: math.max(1, (pageHeight * scale).round()),
  );
}

/// Sendable arguments of [encodeRasterToFile].
class RasterEncodeRequest {
  const RasterEncodeRequest({
    required this.pixels,
    required this.width,
    required this.height,
    required this.format,
    required this.jpegQuality,
    required this.outputPath,
  });

  /// BGRA8888 pixels, as PDFium produces them.
  final TransferableTypedData pixels;
  final int width;
  final int height;
  final PdfImageFormat format;
  final int jpegQuality;
  final String outputPath;
}

/// Encodes an opaque BGRA bitmap and writes it to `outputPath`.
/// Synchronous and CPU-bound: run it in a background isolate.
void encodeRasterToFile(RasterEncodeRequest request) {
  final bgra = request.pixels.materialize().asUint8List();
  final rgb = Uint8List(request.width * request.height * 3);
  for (var source = 0, target = 0; target < rgb.length; source += 4) {
    rgb[target++] = bgra[source + 2];
    rgb[target++] = bgra[source + 1];
    rgb[target++] = bgra[source];
  }
  final image = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  final encoded = switch (request.format) {
    PdfImageFormat.jpeg => img.encodeJpg(image, quality: request.jpegQuality),
    PdfImageFormat.png => img.encodePng(image),
  };
  File(request.outputPath).writeAsBytesSync(encoded, flush: true);
}

/// Rasterization: PDFium renders one page at a time, a background isolate
/// encodes it. Methods throw `FailureException`.
class PdfRasterOps {
  const PdfRasterOps(this._gateway);

  final PdfiumGateway _gateway;

  Future<RenderedPage> renderPage({
    required String path,
    required int pageIndex,
    required String outputPath,
    int? maxLongEdge,
    double? dpi,
    required PdfImageFormat format,
    required int jpegQuality,
    String? password,
  }) async {
    _validate(dpi: dpi, maxLongEdge: maxLongEdge);
    final document = await _gateway.openNonEmpty(path, password: password);
    try {
      if (pageIndex < 0 || pageIndex >= document.pages.length) {
        throw const FailureException(
          PdfFailure(PdfFailureKind.invalidPageRange),
        );
      }
      return await _render(
        document.pages[pageIndex],
        pageIndex: pageIndex,
        outputPath: outputPath,
        dpi: dpi,
        maxLongEdge: maxLongEdge,
        format: format,
        jpegQuality: jpegQuality,
      );
    } finally {
      await document.dispose();
    }
  }

  Future<List<RenderedPage>> pdfToImages({
    required String path,
    required String outputDirectory,
    required PdfImageFormat format,
    required double dpi,
    List<int>? pages,
    required int jpegQuality,
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) async {
    _validate(dpi: dpi);
    final document = await _gateway.openNonEmpty(path, password: password);
    final rendered = <RenderedPage>[];
    try {
      final pageCount = document.pages.length;
      final indexes = pages ?? [for (var i = 0; i < pageCount; i++) i];
      if (indexes.isEmpty || indexes.any((i) => i < 0 || i >= pageCount)) {
        throw const FailureException(
          PdfFailure(PdfFailureKind.invalidPageRange),
        );
      }
      await Directory(outputDirectory).create(recursive: true);
      for (var done = 0; done < indexes.length; done++) {
        throwIfCancelled(isCancelled);
        final index = indexes[done];
        final number = (index + 1).toString().padLeft(4, '0');
        rendered.add(
          await _render(
            document.pages[index],
            pageIndex: index,
            outputPath: p.join(
              outputDirectory,
              'page_$number.${format.extension}',
            ),
            dpi: dpi,
            format: format,
            jpegQuality: jpegQuality,
          ),
        );
        onProgress?.call(done + 1, indexes.length);
      }
      return rendered;
    } catch (_) {
      for (final page in rendered) {
        await deleteQuietly(page.path);
      }
      rethrow;
    } finally {
      await document.dispose();
    }
  }

  Future<RenderedPage> _render(
    pdfium.PdfPage page, {
    required int pageIndex,
    required String outputPath,
    double? dpi,
    int? maxLongEdge,
    required PdfImageFormat format,
    required int jpegQuality,
  }) async {
    final size = rasterSizeFor(
      page.width,
      page.height,
      dpi: dpi,
      maxLongEdge: maxLongEdge,
    );
    final bitmap = await page.render(
      width: size.width,
      height: size.height,
      fullWidth: size.width.toDouble(),
      fullHeight: size.height.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (bitmap == null) {
      throw const FailureException(
        PdfFailure(PdfFailureKind.operationFailed, debugMessage: 'render'),
      );
    }
    final TransferableTypedData pixels;
    try {
      // Copied out of native memory so the bitmap can be released before
      // the (slow) encoding starts.
      pixels = TransferableTypedData.fromList([bitmap.pixels]);
    } finally {
      bitmap.dispose();
    }
    final partial = partialPathOf(outputPath);
    try {
      await File(partial).parent.create(recursive: true);
      await runInIsolate(
        encodeRasterToFile,
        RasterEncodeRequest(
          pixels: pixels,
          width: size.width,
          height: size.height,
          format: format,
          jpegQuality: jpegQuality.clamp(1, 100),
          outputPath: partial,
        ),
      );
      await commitPartial(outputPath);
    } catch (_) {
      await deleteQuietly(partial);
      rethrow;
    }
    return RenderedPage(
      pageIndex: pageIndex,
      path: outputPath,
      width: size.width,
      height: size.height,
    );
  }

  static void _validate({double? dpi, int? maxLongEdge}) {
    final badDpi = dpi != null && (!dpi.isFinite || dpi < 1 || dpi > 2400);
    final badEdge = maxLongEdge != null && maxLongEdge < 1;
    if (badDpi || badEdge) {
      throw const FailureException(ValidationFailure('pdf_invalid_argument'));
    }
  }
}
