import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/data/image_embedding.dart';
import 'package:md_scanner/features/pdf_tools/data/win_ansi.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' as pd;

/// What [stampPdfFile] draws over the pages.
sealed class StampJob {
  const StampJob();
}

final class WatermarkJob extends StampJob {
  const WatermarkJob(this.watermark);
  final PdfWatermark watermark;
}

final class PageNumbersJob extends StampJob {
  const PageNumbersJob(this.numbering);
  final PdfPageNumbering numbering;
}

final class TextsJob extends StampJob {
  const TextsJob(this.texts);
  final List<PdfTextStamp> texts;
}

final class ImagesJob extends StampJob {
  const ImagesJob(this.stamps);
  final List<PdfImageStamp> stamps;
}

/// Sendable arguments of [stampPdfFile].
class StampRequest {
  const StampRequest({
    required this.inputPath,
    required this.outputPath,
    required this.job,
  });

  final String inputPath;
  final String outputPath;
  final StampJob job;
}

// Helvetica metrics, in em.
const double _ascent = 0.718;
const double _descent = 0.207;
const double _lineHeight = 1.2;

const FailureException _invalidArgument = FailureException(
  ValidationFailure('pdf_invalid_argument'),
);
const FailureException _invalidRange = FailureException(
  PdfFailure(PdfFailureKind.invalidPageRange),
);

/// Draws [StampRequest.job] over the unencrypted PDF at `inputPath` and
/// writes the result to `outputPath`. The new content is appended to the
/// file as an incremental update: nothing of the original is re-encoded.
/// Synchronous and CPU-bound: run it in a background isolate.
///
/// `PdfFailure(corrupted)` means the pure-Dart parser could not process the
/// file; the caller may retry on a copy rewritten by PDFium.
Result<void> stampPdfFile(StampRequest request) {
  try {
    final bytes = File(request.inputPath).readAsBytesSync();
    final document = pd.PdfDocument.open(bytes);
    if (document.cos.isEncrypted) {
      return const Err(PdfFailure(PdfFailureKind.passwordRequired));
    }
    final editor = pd.PdfEditor(document);
    final plan = _plan(request.job, document);
    for (final entry in plan.entries) {
      editor.stampPage(entry.key, (stamp) {
        final frame = _Frame.of(stamp.page);
        final m = frame.matrix;
        stamp.content.concatMatrix(m[0], m[1], m[2], m[3], m[4], m[5]);
        for (final draw in entry.value) {
          draw(stamp, frame);
        }
      });
    }
    File(request.outputPath).writeAsBytesSync(editor.save(), flush: true);
    return const Success(null);
  } on FailureException catch (error) {
    return Err(error.failure);
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
  debugMessage: 'stamp.${error.runtimeType}',
);

typedef _Draw = void Function(pd.PdfStamp stamp, _Frame frame);

/// The displayed page as a drawing surface: origin at its bottom-left
/// corner whatever the /Rotate entry and the crop box of the page are.
class _Frame {
  const _Frame(this.matrix, this.width, this.height);

  factory _Frame.of(pd.PdfPage page) {
    final box = page.cropBox;
    return switch (page.rotation) {
      90 => _Frame([0, 1, -1, 0, box.right, box.bottom], box.height, box.width),
      180 => _Frame([-1, 0, 0, -1, box.right, box.top], box.width, box.height),
      270 => _Frame([0, -1, 1, 0, box.left, box.top], box.height, box.width),
      _ => _Frame([1, 0, 0, 1, box.left, box.bottom], box.width, box.height),
    };
  }

  /// Maps frame coordinates to the page's user space.
  final List<double> matrix;
  final double width;
  final double height;
}

/// Validates the job and returns the drawings to run, per page index.
Map<int, List<_Draw>> _plan(StampJob job, pd.PdfDocument document) {
  final pageCount = document.pageCount;
  final plan = <int, List<_Draw>>{};
  void add(int pageIndex, _Draw draw) {
    if (pageIndex < 0 || pageIndex >= pageCount) throw _invalidRange;
    plan.putIfAbsent(pageIndex, () => []).add(draw);
  }

  Iterable<int> targets(Set<int>? pages) {
    if (pages == null) return Iterable<int>.generate(pageCount);
    if (pages.isEmpty) throw _invalidRange;
    return pages;
  }

  switch (job) {
    case WatermarkJob(:final watermark):
      final text = _encode(watermark.text.replaceAll(RegExp(r'\s+'), ' '));
      _requireSize(watermark.fontSize);
      if (!watermark.opacity.isFinite || !watermark.angleDegrees.isFinite) {
        throw _invalidArgument;
      }
      for (final index in targets(watermark.pages)) {
        add(index, (stamp, frame) {
          _drawWatermark(stamp, frame, watermark, text, document.cos);
        });
      }
    case PageNumbersJob(:final numbering):
      _requireSize(numbering.fontSize);
      if (!numbering.margin.isFinite || numbering.margin < 0) {
        throw _invalidArgument;
      }
      final last = numbering.startNumber + pageCount - 1;
      for (final index in targets(numbering.pages)) {
        final text = _encode(
          numbering.format
              .replaceAll('{page}', '${numbering.startNumber + index}')
              .replaceAll('{total}', '$last'),
        );
        add(index, (stamp, frame) {
          _drawPageNumber(stamp, frame, numbering, text);
        });
      }
    case TextsJob(:final texts):
      if (texts.isEmpty) throw _invalidArgument;
      for (final item in texts) {
        _requireSize(item.fontSize);
        _requireFraction(item.x);
        _requireFraction(item.y);
        final lines = [
          for (final line in item.text.split('\n')) _encode(line, empty: true),
        ];
        if (lines.every((line) => line.trim().isEmpty)) {
          throw const FailureException(ValidationFailure('pdf_text_empty'));
        }
        add(item.pageIndex, (stamp, frame) {
          final size = item.fontSize;
          final top = frame.height * (1 - item.y);
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].isEmpty) continue;
            stamp.text(
              lines[i],
              x: frame.width * item.x,
              y: top - size * (_ascent + i * _lineHeight),
              size: size,
              color: item.color & 0xFFFFFF,
            );
          }
        });
      }
    case ImagesJob(:final stamps):
      if (stamps.isEmpty) throw _invalidArgument;
      final images = <String, pd.PdfEmbeddableImage>{};
      for (final item in stamps) {
        if (!item.rect.isValid) throw _invalidArgument;
        final image = images[item.imagePath] ??= _loadImage(item.imagePath);
        add(item.pageIndex, (stamp, frame) {
          final rect = item.rect;
          stamp.image(
            image,
            x: frame.width * rect.left,
            y: frame.height * (1 - rect.top - rect.height),
            width: frame.width * rect.width,
            height: frame.height * rect.height,
          );
        });
      }
  }
  return plan;
}

void _requireSize(double fontSize) {
  if (!fontSize.isFinite || fontSize <= 0 || fontSize > 2000) {
    throw _invalidArgument;
  }
}

void _requireFraction(double value) {
  if (!value.isFinite || value < 0 || value > 1) throw _invalidArgument;
}

String _encode(String text, {bool empty = false}) {
  final encoded = encodeWinAnsi(text);
  if (encoded == null) {
    throw const FailureException(
      ValidationFailure('pdf_text_unsupported_characters'),
    );
  }
  if (!empty && encoded.trim().isEmpty) {
    throw const FailureException(ValidationFailure('pdf_text_empty'));
  }
  return encoded;
}

void _drawWatermark(
  pd.PdfStamp stamp,
  _Frame frame,
  PdfWatermark watermark,
  String text,
  CosDocument cos,
) {
  final radians = watermark.angleDegrees * math.pi / 180;
  final cosA = math.cos(radians);
  final sinA = math.sin(radians);
  var size = watermark.fontSize;
  var width = stamp.measureText(text, size: size, bold: true);
  // The text is shrunk when it would run off the page along its direction.
  final room =
      0.9 *
      math.min(
        cosA.abs() < 1e-6 ? double.infinity : frame.width / cosA.abs(),
        sinA.abs() < 1e-6 ? double.infinity : frame.height / sinA.abs(),
      );
  if (width > room) {
    size *= room / width;
    width = room;
  }
  final half = width / 2;
  final rise = size * 0.35;
  stamp.content.extGState(
    _opacityState(stamp, cos, watermark.opacity.clamp(0.0, 1.0).toDouble()),
  );
  stamp.text(
    text,
    x: frame.width / 2 - (half * cosA - rise * sinA),
    y: frame.height / 2 - (half * sinA + rise * cosA),
    size: size,
    color: watermark.color & 0xFFFFFF,
    bold: true,
    angleDegrees: watermark.angleDegrees,
  );
}

/// Registers a constant-opacity graphics state in the page resources and
/// returns its name.
String _opacityState(pd.PdfStamp stamp, CosDocument cos, double opacity) {
  // stampPage gave the page a /Resources dictionary of its own before
  // calling back, so adding to it cannot leak into other pages.
  final resources = cos.resolve(stamp.page.dict['Resources']);
  if (resources is! CosDictionary) {
    throw StateError('page without resources');
  }
  final existing = cos.resolve(resources['ExtGState']);
  final states = CosDictionary({
    if (existing is CosDictionary) ...existing.entries,
  });
  var index = 1;
  while (states.containsKey('MdsGs$index')) {
    index++;
  }
  states['MdsGs$index'] = CosDictionary({
    'Type': const CosName('ExtGState'),
    'ca': CosReal(opacity),
    'CA': CosReal(opacity),
  });
  resources['ExtGState'] = states;
  return 'MdsGs$index';
}

void _drawPageNumber(
  pd.PdfStamp stamp,
  _Frame frame,
  PdfPageNumbering numbering,
  String text,
) {
  final size = numbering.fontSize;
  final margin = numbering.margin;
  final width = stamp.measureText(text, size: size);
  final x = switch (numbering.position) {
    PdfPageNumberPosition.topLeft || PdfPageNumberPosition.bottomLeft => margin,
    PdfPageNumberPosition.topCenter ||
    PdfPageNumberPosition.bottomCenter => (frame.width - width) / 2,
    PdfPageNumberPosition.topRight ||
    PdfPageNumberPosition.bottomRight => frame.width - margin - width,
  };
  final y = switch (numbering.position) {
    PdfPageNumberPosition.topLeft ||
    PdfPageNumberPosition.topCenter ||
    PdfPageNumberPosition.topRight => frame.height - margin - size * _ascent,
    _ => margin + size * _descent,
  };
  stamp.text(text, x: x, y: y, size: size, color: numbering.color & 0xFFFFFF);
}

/// Reads a stamp image. PNG keeps its transparency (soft mask); JPEG is
/// embedded as it is unless it needs decoding (EXIF rotation, CMYK).
pd.PdfEmbeddableImage _loadImage(String path) {
  final Uint8List bytes;
  try {
    bytes = File(path).readAsBytesSync();
  } on PathNotFoundException {
    throw const FailureException(StorageFailure(StorageFailureKind.notFound));
  }
  final rotated =
      looksLikeJpeg(bytes) &&
      (jpegForEmbedding(Uint8List.fromList(bytes))?.orientation ?? 1) != 1;
  if (!rotated && (looksLikeJpeg(bytes) || looksLikePng(bytes))) {
    try {
      return pd.PdfEmbeddableImage.decode(bytes);
    } on Object {
      // Fall through to the generic decoder below.
    }
  }
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FailureException(
        ImageFailure(ImageFailureKind.unsupportedFormat),
      );
    }
    return pd.PdfEmbeddableImage.png(
      img.encodePng(decoded.convert(format: img.Format.uint8, numChannels: 4)),
    );
  } on FailureException {
    rethrow;
  } on Object {
    throw const FailureException(ImageFailure(ImageFailureKind.decodeFailed));
  }
}
