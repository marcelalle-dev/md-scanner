import 'package:equatable/equatable.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

/// File format of a rendered page.
enum OutputFormat {
  jpg('jpg', 'image/jpeg'),
  png('png', 'image/png');

  const OutputFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;

  /// PNG for black and white pages (lossless, and smaller than a JPEG full
  /// of ringing around every stroke), JPEG for everything else.
  static OutputFormat recommendedFor(ScanFilter filter) =>
      filter == ScanFilter.blackAndWhite ? png : jpg;

  /// Format implied by a file name, [jpg] when the extension is unknown.
  static OutputFormat fromPath(String path) =>
      path.toLowerCase().endsWith('.png') ? png : jpg;
}

/// Facts about an image file, read without decoding its pixels.
///
/// Name clash: files that also import Flutter's painting library must write
/// `import 'package:flutter/material.dart' hide ImageInfo;`.
class ImageInfo extends Equatable {
  const ImageInfo({
    required this.width,
    required this.height,
    required this.byteSize,
  });

  /// Size in pixels of the upright image, EXIF orientation applied.
  final int width;
  final int height;

  /// Size of the file on disk.
  final int byteSize;

  int get pixelCount => width * height;

  double get aspectRatio => height == 0 ? 0 : width / height;

  bool get isLandscape => width > height;

  @override
  List<Object?> get props => [width, height, byteSize];
}

/// A page written to disk by `ImageProcessor.render`.
class ProcessedImage extends Equatable {
  const ProcessedImage({
    required this.path,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.format,
  });

  /// Absolute path of the encoded file (the request's `outputPath`).
  final String path;
  final int width;
  final int height;
  final int byteSize;
  final OutputFormat format;

  @override
  List<Object?> get props => [path, width, height, byteSize, format];
}

/// Everything needed to produce the final file of one page.
class ImageRenderRequest extends Equatable {
  const ImageRenderRequest({
    required this.sourcePath,
    required this.outputPath,
    this.quad,
    this.adjustments = ImageAdjustments.none,
    this.mode = ScanMode.document,
    this.format = OutputFormat.jpg,
    this.jpegQuality = defaultJpegQuality,
    this.maxLongEdge = defaultMaxLongEdge,
  });

  static const int defaultJpegQuality = 88;

  /// About 220 dpi on an A4 page: sharp for reading, printing and OCR while
  /// keeping a page well under a megabyte.
  static const int defaultMaxLongEdge = 2600;

  /// Absolute path of the captured or imported image. Never modified.
  final String sourcePath;

  /// Absolute path of the file to create. Replaced atomically when it
  /// already exists; may be equal to [sourcePath].
  final String outputPath;

  /// Document outline to rectify, null to keep the whole image.
  final Quad? quad;

  final ImageAdjustments adjustments;

  /// Capture mode of the page: selects the filter strength and, for cards,
  /// the standard proportions of the output.
  final ScanMode mode;

  final OutputFormat format;

  /// 1 to 100, only used for [OutputFormat.jpg].
  final int jpegQuality;

  /// Upper bound of the longest side of the output, in pixels. The output is
  /// never enlarged beyond the resolution of the source.
  final int maxLongEdge;

  ImageRenderRequest copyWith({
    String? sourcePath,
    String? outputPath,
    Quad? Function()? quad,
    ImageAdjustments? adjustments,
    ScanMode? mode,
    OutputFormat? format,
    int? jpegQuality,
    int? maxLongEdge,
  }) => ImageRenderRequest(
    sourcePath: sourcePath ?? this.sourcePath,
    outputPath: outputPath ?? this.outputPath,
    quad: quad != null ? quad() : this.quad,
    adjustments: adjustments ?? this.adjustments,
    mode: mode ?? this.mode,
    format: format ?? this.format,
    jpegQuality: jpegQuality ?? this.jpegQuality,
    maxLongEdge: maxLongEdge ?? this.maxLongEdge,
  );

  @override
  List<Object?> get props => [
    sourcePath,
    outputPath,
    quad,
    adjustments,
    mode,
    format,
    jpegQuality,
    maxLongEdge,
  ];
}

/// What the editor needs to show a page while the user is tuning it.
class ImagePreviewRequest extends Equatable {
  const ImagePreviewRequest({
    required this.sourcePath,
    this.quad,
    this.adjustments = ImageAdjustments.none,
    this.mode = ScanMode.document,
    this.maxLongEdge = defaultMaxLongEdge,
  });

  static const int defaultMaxLongEdge = 1280;

  /// Previews are built from a reduced copy of the source: asking for more
  /// than this is silently capped. Use `ImageProcessor.render` for more.
  static const int largestMaxLongEdge = 1600;

  final String sourcePath;

  /// Document outline to rectify, null to keep the whole image.
  final Quad? quad;

  final ImageAdjustments adjustments;

  final ScanMode mode;

  /// Upper bound of the longest side of the preview, in pixels.
  final int maxLongEdge;

  ImagePreviewRequest copyWith({
    String? sourcePath,
    Quad? Function()? quad,
    ImageAdjustments? adjustments,
    ScanMode? mode,
    int? maxLongEdge,
  }) => ImagePreviewRequest(
    sourcePath: sourcePath ?? this.sourcePath,
    quad: quad != null ? quad() : this.quad,
    adjustments: adjustments ?? this.adjustments,
    mode: mode ?? this.mode,
    maxLongEdge: maxLongEdge ?? this.maxLongEdge,
  );

  @override
  List<Object?> get props => [sourcePath, quad, adjustments, mode, maxLongEdge];
}
