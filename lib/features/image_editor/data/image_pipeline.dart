import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/image_editor/data/document_detector.dart';
import 'package:md_scanner/features/image_editor/data/filters.dart';
import 'package:md_scanner/features/image_editor/data/illumination.dart';
import 'package:md_scanner/features/image_editor/data/image_codec.dart';
import 'package:md_scanner/features/image_editor/data/perspective.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

// Everything in this file runs inside a worker isolate: synchronous I/O and
// long loops are fine here, and every entry point returns a `Result` (plain
// data) instead of throwing across the isolate boundary.

/// Long edge of the reduced copy of a source kept for previews.
const int previewBaseLongEdge = ImagePreviewRequest.largestMaxLongEdge;

const int _previewJpegQuality = 82;
const int _thumbnailJpegQuality = 80;
const int _minLongEdge = 16;
const int _maxLongEdge = 16384;

final class DetectJob {
  const DetectJob(this.path, this.mode, this.base);

  final String path;
  final ScanMode mode;

  /// Already decoded reduced copy of the source, when one is at hand.
  final Raster? base;
}

final class PreviewJob {
  const PreviewJob(this.base, this.request);

  final Raster base;
  final ImagePreviewRequest request;
}

final class ThumbnailJob {
  const ThumbnailJob(this.sourcePath, this.outputPath, this.maxSize);

  final String sourcePath;
  final String outputPath;
  final int maxSize;
}

Result<ImageInfo> runInspect(String path) => _capture(() {
  final bytes = _readSource(path);
  final header = readHeader(bytes);
  return ImageInfo(
    width: header.width,
    height: header.height,
    byteSize: bytes.length,
  );
});

Result<Quad?> runDetect(DetectJob job) => _capture(() {
  var source = job.base;
  if (source == null) {
    final bytes = _readSource(job.path);
    source = _decodeFor(bytes, readHeader(bytes), null, detectionMinLongEdge);
  }
  if (source.longEdge > detectionMaxLongEdge) {
    source = _fitWithin(
      source,
      (detectionMinLongEdge + detectionMaxLongEdge) ~/ 2,
    );
  }
  return detectDocumentQuad(luminanceOf(source), job.mode.preset.hints);
});

Result<ProcessedImage> runRender(ImageRenderRequest request) => _capture(() {
  final quad = _renderableQuad(request.quad);
  final adjustments = request.adjustments.normalized();
  final maxLongEdge = request.maxLongEdge
      .clamp(_minLongEdge, _maxLongEdge)
      .toInt();
  final bytes = _readSource(request.sourcePath);
  final source = _decodeFor(bytes, readHeader(bytes), quad, maxLongEdge);
  final page = _develop(
    source,
    quad,
    adjustments,
    request.mode.preset.hints,
    maxLongEdge,
  );
  final encoded = encodeRaster(
    page,
    request.format,
    jpegQuality: request.jpegQuality,
    twoTone: adjustments.filter == ScanFilter.blackAndWhite,
  );
  _writeAtomically(request.outputPath, encoded);
  return ProcessedImage(
    path: request.outputPath,
    width: page.width,
    height: page.height,
    byteSize: encoded.length,
    format: request.format,
  );
});

/// Decodes the upright source reduced to [previewBaseLongEdge].
Result<Raster> runLoadPreviewBase(String path) => _capture(() {
  final bytes = _readSource(path);
  final source = _decodeFor(
    bytes,
    readHeader(bytes),
    null,
    previewBaseLongEdge,
  );
  return _fitWithin(source, previewBaseLongEdge);
});

Result<Uint8List> runPreview(PreviewJob job) => _capture(() {
  final request = job.request;
  final page = _develop(
    job.base,
    _renderableQuad(request.quad),
    request.adjustments.normalized(),
    request.mode.preset.hints,
    request.maxLongEdge.clamp(_minLongEdge, previewBaseLongEdge).toInt(),
  );
  return encodeRaster(
    page,
    OutputFormat.jpg,
    jpegQuality: _previewJpegQuality,
    draft: true,
  );
});

Result<String> runThumbnail(ThumbnailJob job) => _capture(() {
  final maxSize = math.max(1, job.maxSize);
  final bytes = _readSource(job.sourcePath);
  final source = _decodeFor(bytes, readHeader(bytes), null, maxSize);
  final encoded = encodeRaster(
    _fitWithin(source, maxSize),
    OutputFormat.fromPath(job.outputPath),
    jpegQuality: _thumbnailJpegQuality,
    draft: true,
  );
  _writeAtomically(job.outputPath, encoded);
  return job.outputPath;
});

/// Rectifies [source] then applies the filter and the manual adjustments.
/// May modify [source] in place: callers hand over a buffer they own.
Raster _develop(
  Raster source,
  Quad? quad,
  ImageAdjustments adjustments,
  ProcessingHints hints,
  int maxLongEdge,
) {
  final plan = planWarp(
    sourceWidth: source.width,
    sourceHeight: source.height,
    quad: quad,
    quarterTurns: adjustments.quarterTurns,
    maxLongEdge: maxLongEdge,
    hints: hints,
  );
  return applyLook(warp(source, plan), adjustments, hints);
}

/// Applies `adjustments.filter` with the strength of [hints], then the
/// brightness, contrast and saturation sliders. Works in place on [rgb] and
/// returns the result, which is single-channel for monochrome filters.
///
/// Black and white is the exception to the order: sliders act before the
/// threshold (afterwards there are only two tones left to adjust) and
/// brightness also biases the threshold itself.
Raster applyLook(
  Raster rgb,
  ImageAdjustments adjustments,
  ProcessingHints hints,
) {
  final strength = hints.filterStrength;
  final Raster page;
  switch (adjustments.filter) {
    case ScanFilter.blackAndWhite:
      final gray = luminanceOf(rgb);
      applyAdjustments(
        gray,
        brightness: adjustments.brightness,
        contrast: adjustments.contrast,
        saturation: 0,
      );
      return adaptiveThreshold(
        gray,
        strength: strength,
        bias: adjustments.brightness,
      );
    case ScanFilter.grayscale:
      page = grayscale(rgb);
    case ScanFilter.original:
      page = rgb;
    case ScanFilter.enhanced:
      enhanceColor(rgb, strength);
      page = rgb;
    case ScanFilter.readability:
      whitenPaper(rgb, strength);
      page = rgb;
    case ScanFilter.noShadow:
      evenIllumination(rgb, strength);
      page = rgb;
  }
  applyAdjustments(
    page,
    brightness: adjustments.brightness,
    contrast: adjustments.contrast,
    saturation: adjustments.saturation,
  );
  return page;
}

/// Null for "whole image" (including an explicit [Quad.full], so that an
/// uncropped picture is never squeezed into standard card proportions).
Quad? _renderableQuad(Quad? quad) {
  if (quad == null) return null;
  final clamped = quad.clamped();
  if (clamped == Quad.full) return null;
  if (!clamped.isRenderable) {
    throw const FailureException(
      ValidationFailure(ImageProcessor.invalidQuadCode),
    );
  }
  return clamped;
}

/// Decodes just enough pixels to produce a page whose long edge is
/// [targetLongEdge]: reduced JPEG decode when possible, box halving for what
/// remains, so the final resampling never reduces by more than 2.
Raster _decodeFor(
  Uint8List bytes,
  SourceHeader header,
  Quad? quad,
  int targetLongEdge,
) {
  final available = pageLongEdge(header.width, header.height, quad);
  final wanted = math.max(1.0, math.min(targetLongEdge.toDouble(), available));
  final decoded = decodeRgb(
    bytes,
    header,
    jpegScale: header.format == SourceFormat.jpeg
        ? jpegScaleFor(available / wanted)
        : 1,
  );
  return reduceForRatio(
    decoded,
    pageLongEdge(decoded.width, decoded.height, quad) / wanted,
  );
}

/// Shrinks [raster] so that its long edge is at most [maxLongEdge]. Never
/// enlarges.
Raster _fitWithin(Raster raster, int maxLongEdge) {
  if (raster.longEdge <= maxLongEdge) return raster;
  final reduced = reduceForRatio(raster, raster.longEdge / maxLongEdge);
  if (reduced.longEdge <= maxLongEdge) return reduced;
  final scale = maxLongEdge / reduced.longEdge;
  return resize(
    reduced,
    math.max(1, math.min(maxLongEdge, (reduced.width * scale).round())),
    math.max(1, math.min(maxLongEdge, (reduced.height * scale).round())),
  );
}

Uint8List _readSource(String path) {
  final file = File(path);
  try {
    if (!file.existsSync()) {
      throw const FailureException(StorageFailure(StorageFailureKind.notFound));
    }
    final length = file.lengthSync();
    if (length > ImageProcessor.maxSourceBytes) {
      throw const FailureException(ImageFailure(ImageFailureKind.tooLarge));
    }
    return file.readAsBytesSync();
  } on FileSystemException catch (error) {
    throw FailureException(
      StorageFailure(
        StorageFailureKind.readError,
        debugMessage: 'FileSystemException(os=${error.osError?.errorCode})',
      ),
    );
  }
}

var _tempCounter = 0;

/// Writes [bytes] next to [outputPath] then renames: readers see either the
/// previous file or the complete new one, and a failure leaves nothing.
void _writeAtomically(String outputPath, Uint8List bytes) {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final temp = File('$outputPath.$pid-$stamp-${_tempCounter++}.part');
  try {
    File(outputPath).parent.createSync(recursive: true);
    temp.writeAsBytesSync(bytes, flush: true);
    temp.renameSync(outputPath);
  } on FileSystemException catch (error) {
    _deleteQuietly(temp);
    final failure = failureFromError(error);
    throw FailureException(
      failure is StorageFailure &&
              failure.kind == StorageFailureKind.insufficientSpace
          ? failure
          : StorageFailure(
              StorageFailureKind.writeError,
              debugMessage:
                  'FileSystemException(os=${error.osError?.errorCode})',
            ),
    );
  } catch (_) {
    _deleteQuietly(temp);
    rethrow;
  }
}

void _deleteQuietly(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // The write already failed and is being reported; a second error while
    // cleaning up would only hide the first one.
  }
}

Result<T> _capture<T>(T Function() body) {
  try {
    return Success<T>(body());
  } on FailureException catch (error) {
    return Err<T>(error.failure);
  } catch (error) {
    // Only the type: messages may embed paths.
    return Err<T>(
      ImageFailure(
        ImageFailureKind.processingFailed,
        debugMessage: error.runtimeType.toString(),
      ),
    );
  }
}
