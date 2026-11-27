import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

/// Image engine of the scanner: finds the page in a capture, straightens it,
/// applies the look chosen by the user and writes the result.
///
/// Accepted sources: JPEG, PNG, WebP, GIF (first frame), BMP and TIFF, up to
/// [maxSourcePixels]. Quads and sizes always refer to the upright image, EXIF
/// orientation applied (JPEG only: other formats are taken as stored).
///
/// Nothing throws. Failures are:
/// - `ImageFailure(decodeFailed)`: not an image, truncated or corrupted;
/// - `ImageFailure(unsupportedFormat)`: a recognized format that cannot be
///   read (HEIC/HEIF, AVIF, JPEG XL, JPEG 2000, PSD, SVG, PDF);
/// - `ImageFailure(tooLarge)`: more than [maxSourcePixels] or a file above
///   [maxSourceBytes];
/// - `StorageFailure`: `notFound` / `readError` for the source,
///   `insufficientSpace` / `writeError` for the output;
/// - `ValidationFailure(invalidQuadCode)`: the quad cannot be rectified;
/// - `ImageFailure(processingFailed)`: anything else.
///
/// A failed call leaves no file behind and never alters an existing output.
abstract interface class ImageProcessor {
  /// Largest accepted source, in pixels (64 megapixels).
  static const int maxSourcePixels = 64000000;

  /// Largest accepted source file (200 MB): beyond it the file is refused
  /// before being read into memory.
  static const int maxSourceBytes = 200 * 1024 * 1024;

  /// `ValidationFailure.code` returned when a quad is crossed, mirrored,
  /// flat or smaller than `Quad.minRenderableArea` (see `Quad.isRenderable`).
  static const String invalidQuadCode = 'image_editor.invalid_quad';

  /// Reads the size of the upright image and of its file without decoding
  /// the pixels.
  Future<Result<ImageInfo>> inspect(String path);

  /// Looks for the outline of a document in the image at [path].
  ///
  /// Succeeds with null when no outline is trustworthy: callers then start
  /// from [Quad.full] and let the user place the corners. A quad is only
  /// returned when all of the following hold, so it is never a guess:
  /// - it comes from a real region of the image (enclosed by edges, or
  ///   clearly lighter or darker than its surroundings), not from a default;
  /// - it is convex, every corner angle is between 35 and 145 degrees, and
  ///   its corners are inside the frame;
  /// - it covers at least `hints.minAreaFraction` of the frame and is not
  ///   more elongated than `hints.maxElongation` for [mode];
  /// - its sides lie on actual edges: at least 60 % of the perimeter, and at
  ///   least 35 % of each side, sits on a contrast edge running along that
  ///   side with a consistent light/dark direction.
  ///
  /// A page that fills the whole frame or leaves it on one side therefore
  /// yields null (its border is not visible), as does a blurred, noisy or
  /// low-contrast scene.
  Future<Result<Quad?>> detectDocument(
    String path, {
    ScanMode mode = ScanMode.document,
  });

  /// Produces the final file of a page: perspective correction of
  /// `request.quad`, rotation, filter, adjustments, then encoding to
  /// `request.outputPath`.
  ///
  /// The output size follows the edge lengths of the quad in the source
  /// (snapped to the standard proportions of the mode when it has some),
  /// reduced to fit `request.maxLongEdge`, never enlarged.
  Future<Result<ProcessedImage>> render(ImageRenderRequest request);

  /// Same pipeline as [render] on a reduced copy of the source, returned as
  /// JPEG bytes for immediate display. The reduced copy of the last source
  /// is kept in memory, so successive previews of one page (dragging a
  /// corner, trying filters) skip decoding and stay fast.
  ///
  /// Filters scale with the image, so a preview looks like the final render.
  Future<Result<Uint8List>> preview(ImagePreviewRequest request);

  /// Writes a small copy of [sourcePath] whose sides are at most [maxSize]
  /// pixels, as PNG when [outputPath] ends with `.png`, as JPEG otherwise.
  /// Returns [outputPath].
  Future<Result<String>> thumbnail(
    String sourcePath,
    String outputPath, {
    int maxSize = 512,
  });
}

/// Overridden in `bootstrap()` with `IsolateImageProcessor` (data layer), and
/// in tests with a fake.
final imageProcessorProvider = Provider<ImageProcessor>(
  (ref) => throw StateError('imageProcessorProvider must be overridden'),
);
