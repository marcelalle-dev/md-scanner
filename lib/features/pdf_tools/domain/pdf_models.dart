import 'package:equatable/equatable.dart';

/// Reports progress of a long operation: [done] units out of [total].
typedef PdfProgressCallback = void Function(int done, int total);

/// Polled between units of work; returning true aborts the operation with a
/// `CancelledFailure` and removes everything it had produced so far.
typedef PdfCancellationCheck = bool Function();

/// Size of a page as displayed, in PDF points (1/72 inch).
class PdfPageSize extends Equatable {
  const PdfPageSize(this.width, this.height, {this.rotationDegrees = 0});

  /// Displayed width: the page rotation is already applied.
  final double width;

  /// Displayed height: the page rotation is already applied.
  final double height;

  /// Clockwise rotation stored in the page (0, 90, 180 or 270).
  final int rotationDegrees;

  bool get isLandscape => width > height;

  @override
  List<Object?> get props => [width, height, rotationDegrees];
}

class PdfInfo extends Equatable {
  const PdfInfo({
    required this.pageCount,
    required this.isEncrypted,
    required this.pageSizes,
    required this.fileSize,
  });

  final int pageCount;

  /// True when the file carries a security handler, including files that
  /// open without a password (owner-only protection).
  final bool isEncrypted;

  /// One entry per page, in document order.
  final List<PdfPageSize> pageSizes;

  /// Size of the file on disk, in bytes.
  final int fileSize;

  @override
  List<Object?> get props => [pageCount, isEncrypted, pageSizes, fileSize];
}

/// A PDF file written by the engine.
class PdfOutput extends Equatable {
  const PdfOutput({
    required this.path,
    required this.pageCount,
    required this.fileSize,
  });

  /// Absolute path of the written file.
  final String path;
  final int pageCount;
  final int fileSize;

  @override
  List<Object?> get props => [path, pageCount, fileSize];
}

enum PdfPaperSize {
  /// ISO A4, 595.28 x 841.89 points.
  a4,

  /// US Letter, 612 x 792 points.
  letter,

  /// The page takes the proportions of its image (no white bands). It is
  /// sized to the largest such rectangle that fits an A4 sheet turned like
  /// the image, so printing on A4 never crops.
  fitImage,
}

/// Page layout used when building a PDF from images.
class PdfPageSetup extends Equatable {
  const PdfPageSetup({
    this.pageSize = PdfPaperSize.a4,
    this.margin = 0,
    this.autoOrientation = true,
  });

  final PdfPaperSize pageSize;

  /// White border around the image, in points. Clamped to a third of the
  /// short side of the page.
  final double margin;

  /// Turns an A4/Letter page to landscape when its image is wider than tall.
  /// [PdfPaperSize.fitImage] always follows the image.
  final bool autoOrientation;

  @override
  List<Object?> get props => [pageSize, margin, autoOrientation];
}

enum PdfImageFormat {
  jpeg('jpg'),
  png('png');

  const PdfImageFormat(this.extension);

  /// File extension, without the dot.
  final String extension;
}

/// A page rasterized to an image file.
class RenderedPage extends Equatable {
  const RenderedPage({
    required this.pageIndex,
    required this.path,
    required this.width,
    required this.height,
  });

  /// 0-based index of the page in its document.
  final int pageIndex;

  /// Absolute path of the image file.
  final String path;

  /// Pixel dimensions of the image.
  final int width;
  final int height;

  @override
  List<Object?> get props => [pageIndex, path, width, height];
}

enum PdfCompressionLevel {
  /// Lossless: rebuilds the file structure, drops unused data. Images keep
  /// every pixel.
  low,

  /// Images above 150 dpi are downsampled and re-encoded (JPEG quality 75).
  balanced,

  /// Images above 100 dpi are downsampled and re-encoded (JPEG quality 50).
  high,
}

/// Outcome of a compression. Sizes are measured on disk, never estimated.
class PdfCompressionResult extends Equatable {
  const PdfCompressionResult({
    required this.originalSize,
    required this.compressedSize,
    required this.reduced,
  });

  final int originalSize;

  /// Size of the file written at the output path, or [originalSize] when
  /// [reduced] is false.
  final int compressedSize;

  /// False when no smaller file could be produced: nothing was written.
  final bool reduced;

  /// Bytes saved; 0 when [reduced] is false.
  int get savedBytes => originalSize - compressedSize;

  @override
  List<Object?> get props => [originalSize, compressedSize, reduced];
}

/// Diagonal text drawn across pages.
///
/// Text is set in Helvetica: characters outside Windows-1252 (Latin
/// languages, punctuation, the euro sign) are rejected with
/// `ValidationFailure('pdf_text_unsupported_characters')`.
class PdfWatermark extends Equatable {
  const PdfWatermark({
    required this.text,
    this.opacity = 0.25,
    this.angleDegrees = 45,
    this.fontSize = 48,
    this.color = 0x808080,
    this.pages,
  });

  final String text;

  /// 0 (invisible) to 1 (opaque).
  final double opacity;

  /// Counter-clockwise angle of the baseline, as seen on the displayed page.
  final double angleDegrees;

  /// In points.
  final double fontSize;

  /// `0xRRGGBB`.
  final int color;

  /// 0-based indexes of the pages to mark; null marks every page.
  final Set<int>? pages;

  @override
  List<Object?> get props => [
    text,
    opacity,
    angleDegrees,
    fontSize,
    color,
    pages,
  ];
}

enum PdfPageNumberPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Page numbers stamped on every page (or on [pages]).
class PdfPageNumbering extends Equatable {
  const PdfPageNumbering({
    this.position = PdfPageNumberPosition.bottomCenter,
    this.format = '{page} / {total}',
    this.startNumber = 1,
    this.fontSize = 10,
    this.margin = 24,
    this.color = 0x000000,
    this.pages,
  });

  final PdfPageNumberPosition position;

  /// Template: `{page}` is the number of the page, `{total}` the number of
  /// the last numbered page. With the default [startNumber] they are the
  /// page position and the page count.
  final String format;

  /// Number given to the first page of the document.
  final int startNumber;

  /// In points.
  final double fontSize;

  /// Distance to the page edges, in points.
  final double margin;

  /// `0xRRGGBB`.
  final int color;

  /// 0-based indexes of the pages to number; null numbers every page.
  final Set<int>? pages;

  @override
  List<Object?> get props => [
    position,
    format,
    startNumber,
    fontSize,
    margin,
    color,
    pages,
  ];
}

/// A single line of text placed on a page.
class PdfTextStamp extends Equatable {
  const PdfTextStamp({
    required this.pageIndex,
    required this.text,
    required this.x,
    required this.y,
    this.fontSize = 14,
    this.color = 0x000000,
  });

  /// 0-based page index.
  final int pageIndex;
  final String text;

  /// Top-left corner of the text, as fractions (0..1) of the displayed page
  /// width and height, measured from its top-left corner.
  final double x;
  final double y;

  /// In points.
  final double fontSize;

  /// `0xRRGGBB`.
  final int color;

  @override
  List<Object?> get props => [pageIndex, text, x, y, fontSize, color];
}

/// Rectangle expressed as fractions (0..1) of the displayed page, origin at
/// the top-left corner.
class PdfNormalizedRect extends Equatable {
  const PdfNormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0 &&
      left >= 0 &&
      top >= 0 &&
      left + width <= 1.000001 &&
      top + height <= 1.000001;

  @override
  List<Object?> get props => [left, top, width, height];
}

/// An image (PNG with transparency, or JPEG) drawn over a page, typically a
/// handwritten signature. The image is stretched to [rect].
class PdfImageStamp extends Equatable {
  const PdfImageStamp({
    required this.pageIndex,
    required this.imagePath,
    required this.rect,
  });

  /// 0-based page index.
  final int pageIndex;

  /// Absolute path of the PNG or JPEG file.
  final String imagePath;
  final PdfNormalizedRect rect;

  @override
  List<Object?> get props => [pageIndex, imagePath, rect];
}
