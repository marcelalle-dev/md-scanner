import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/data/image_embedding.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_io.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';

const (double, double) _a4 = (595.2756, 841.8898);
const (double, double) _letter = (612, 792);

/// Where an image sits on its page, in points (origin bottom-left).
class ImagePagePlacement {
  const ImagePagePlacement({
    required this.pageWidth,
    required this.pageHeight,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double pageWidth;
  final double pageHeight;
  final double x;
  final double y;
  final double width;
  final double height;
}

/// Lays an upright image of [pixelWidth] x [pixelHeight] out on a page:
/// scaled to fill the printable area without distortion, centred.
ImagePagePlacement layoutImagePage({
  required int pixelWidth,
  required int pixelHeight,
  required PdfPageSetup setup,
}) {
  final fit = setup.pageSize == PdfPaperSize.fitImage;
  final base = setup.pageSize == PdfPaperSize.letter ? _letter : _a4;
  final landscape = pixelWidth > pixelHeight && (fit || setup.autoOrientation);
  final (sheetWidth, sheetHeight) = landscape ? (base.$2, base.$1) : base;
  final requested = setup.margin.isFinite ? setup.margin : 0.0;
  final margin = requested
      .clamp(0.0, math.min(sheetWidth, sheetHeight) / 3)
      .toDouble();
  final scale = math.min(
    (sheetWidth - 2 * margin) / pixelWidth,
    (sheetHeight - 2 * margin) / pixelHeight,
  );
  final width = pixelWidth * scale;
  final height = pixelHeight * scale;
  if (fit) {
    return ImagePagePlacement(
      pageWidth: width + 2 * margin,
      pageHeight: height + 2 * margin,
      x: margin,
      y: margin,
      width: width,
      height: height,
    );
  }
  return ImagePagePlacement(
    pageWidth: sheetWidth,
    pageHeight: sheetHeight,
    x: (sheetWidth - width) / 2,
    y: (sheetHeight - height) / 2,
    width: width,
    height: height,
  );
}

/// Writes a PDF with one page per image straight to disk.
///
/// The file is produced sequentially: an image is read, written to the
/// output and released before the next one is opened, so memory use does
/// not grow with the number of pages.
class ImagePdfWriter {
  ImagePdfWriter(this._file);

  final RandomAccessFile _file;
  final List<int> _offsets = [0, 0, 0];
  final List<int> _pages = [];
  int _position = 0;

  static const int _catalog = 1;
  static const int _pageTree = 2;
  static const int _info = 3;

  /// Bytes written so far.
  int get length => _position;

  Future<void> writeHeader() =>
      _emit([...'%PDF-1.7\n'.codeUnits, 0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

  /// Appends a page showing [image] laid out by [setup].
  Future<void> addPage(EmbeddableImage image, PdfPageSetup setup) async {
    final place = layoutImagePage(
      pixelWidth: image.displayWidth,
      pixelHeight: image.displayHeight,
      setup: setup,
    );
    final imageNumber = await _begin();
    await _text(
      '<< /Type /XObject /Subtype /Image /Width ${image.width} '
      '/Height ${image.height} ${image.dictionary} '
      '/Length ${image.data.length} >>\nstream\n',
    );
    await _emit(image.data);
    await _text('\nendstream\nendobj\n');

    final content =
        'q\n${_n(place.width)} 0 0 ${_n(place.height)} '
        '${_n(place.x)} ${_n(place.y)} cm\n'
        '${image.orientationMatrix.join(' ')} cm\n/Im0 Do\nQ\n';
    final contentNumber = await _begin();
    await _text(
      '<< /Length ${content.length} >>\nstream\n$content\nendstream\nendobj\n',
    );

    final pageNumber = await _begin();
    await _text(
      '<< /Type /Page /Parent $_pageTree 0 R '
      '/MediaBox [0 0 ${_n(place.pageWidth)} ${_n(place.pageHeight)}] '
      '/Resources << /XObject << /Im0 $imageNumber 0 R >> >> '
      '/Contents $contentNumber 0 R >>\nendobj\n',
    );
    _pages.add(pageNumber);
  }

  /// Writes the page tree, the catalog, the cross-reference table and the
  /// trailer. Nothing can be added afterwards.
  Future<void> finish({required DateTime createdAt}) async {
    _offsets[_pageTree - 1] = _position;
    await _text(
      '$_pageTree 0 obj\n<< /Type /Pages /Count ${_pages.length} '
      '/Kids [${_pages.map((n) => '$n 0 R').join(' ')}] >>\nendobj\n',
    );
    _offsets[_catalog - 1] = _position;
    await _text(
      '$_catalog 0 obj\n<< /Type /Catalog /Pages $_pageTree 0 R >>\nendobj\n',
    );
    _offsets[_info - 1] = _position;
    await _text(
      '$_info 0 obj\n<< /Producer (MD SCANNER) '
      '/CreationDate (${_pdfDate(createdAt)}) >>\nendobj\n',
    );

    final xref = _position;
    final table = StringBuffer('xref\n0 ${_offsets.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in _offsets) {
      table.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    final random = math.Random.secure();
    final id = [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    table.write(
      'trailer\n<< /Size ${_offsets.length + 1} /Root $_catalog 0 R '
      '/Info $_info 0 R /ID [<$id> <$id>] >>\nstartxref\n$xref\n%%EOF\n',
    );
    await _text(table.toString());
    await _file.flush();
  }

  /// Starts the next indirect object and returns its number.
  Future<int> _begin() async {
    _offsets.add(_position);
    final number = _offsets.length;
    await _text('$number 0 obj\n');
    return number;
  }

  Future<void> _text(String text) => _emit(text.codeUnits);

  Future<void> _emit(List<int> bytes) async {
    await _file.writeFrom(bytes);
    _position += bytes.length;
  }

  static String _n(double value) {
    final text = value.toStringAsFixed(4);
    return text.contains('.')
        ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : text;
  }

  static String _pdfDate(DateTime time) {
    final utc = time.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'D:${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}${two(utc.hour)}${two(utc.minute)}'
        '${two(utc.second)}Z';
  }
}

/// Loads the image at [path] in the form that preserves it best: JPEG and
/// plain PNG files are embedded as they are, anything else is decoded in a
/// background isolate.
Future<EmbeddableImage> loadEmbeddableImage(String path) async {
  final direct = await _embedDirectly(path);
  if (direct != null) return direct;
  return valueOrThrow(await runInIsolate(decodeImageFileForEmbedding, path));
}

Future<EmbeddableImage?> _embedDirectly(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const FailureException(StorageFailure(StorageFailureKind.notFound));
  }
  final Uint8List bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw const FailureException(ImageFailure(ImageFailureKind.decodeFailed));
  }
  return jpegForEmbedding(bytes) ?? pngForEmbedding(bytes);
}

/// Builds the PDF of `imagesToPdf`. Throws `FailureException`; the partial
/// output is removed on any failure.
Future<PdfOutput> writeImagesPdf({
  required List<String> imagePaths,
  required String outputPath,
  required PdfPageSetup setup,
  required DateTime createdAt,
  PdfProgressCallback? onProgress,
  PdfCancellationCheck? isCancelled,
}) async {
  if (imagePaths.isEmpty) {
    throw const FailureException(PdfFailure(PdfFailureKind.emptyDocument));
  }
  final partial = File(partialPathOf(outputPath));
  await partial.parent.create(recursive: true);
  RandomAccessFile? handle;
  try {
    handle = await partial.open(mode: FileMode.write);
    final writer = ImagePdfWriter(handle);
    await writer.writeHeader();
    for (var i = 0; i < imagePaths.length; i++) {
      throwIfCancelled(isCancelled);
      await writer.addPage(await loadEmbeddableImage(imagePaths[i]), setup);
      onProgress?.call(i + 1, imagePaths.length);
    }
    throwIfCancelled(isCancelled);
    await writer.finish(createdAt: createdAt);
    await handle.close();
    handle = null;
    final size = await commitPartial(outputPath);
    return PdfOutput(
      path: outputPath,
      pageCount: imagePaths.length,
      fileSize: size,
    );
  } catch (_) {
    await handle?.close();
    await deleteQuietly(partial.path);
    rethrow;
  }
}
