import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';

/// Container formats the engine reads.
enum SourceFormat { jpeg, png, gif, webp, bmp, tiff }

/// What the first bytes of a file say about it, pixels not decoded.
final class SourceHeader {
  const SourceHeader(this.format, this.width, this.height);

  final SourceFormat format;

  /// Size of the upright image (EXIF orientation applied for JPEG).
  final int width;
  final int height;
}

const _decodeFailed = FailureException(
  ImageFailure(ImageFailureKind.decodeFailed),
);
const _unsupported = FailureException(
  ImageFailure(ImageFailureKind.unsupportedFormat),
);
const _tooLarge = FailureException(ImageFailure(ImageFailureKind.tooLarge));

/// Identifies the container from its signature. File extensions are ignored:
/// gallery apps and messaging apps routinely mislabel files.
///
/// Throws `decodeFailed` for unknown data and `unsupportedFormat` for formats
/// that are recognized but cannot be decoded.
SourceFormat sniffFormat(Uint8List b) {
  if (_bytes(b, 0, const [0xFF, 0xD8, 0xFF])) return SourceFormat.jpeg;
  if (_bytes(b, 0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return SourceFormat.png;
  }
  if (_ascii(b, 0, 'GIF87a') || _ascii(b, 0, 'GIF89a')) return SourceFormat.gif;
  if (_ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP')) return SourceFormat.webp;
  if (_bytes(b, 0, const [0x49, 0x49, 0x2A, 0x00]) ||
      _bytes(b, 0, const [0x4D, 0x4D, 0x00, 0x2A])) {
    return SourceFormat.tiff;
  }
  if (_ascii(b, 0, 'BM') && b.length >= 26) return SourceFormat.bmp;
  throw _isKnownUnreadable(b) ? _unsupported : _decodeFailed;
}

bool _isKnownUnreadable(Uint8List b) {
  // ISO base media files: HEIC/HEIF, AVIF (and videos).
  if (_ascii(b, 4, 'ftyp')) return true;
  if (_ascii(b, 0, '%PDF') || _ascii(b, 0, '8BPS')) return true;
  // JPEG XL (bare codestream and container), JPEG 2000 (both forms).
  if (_bytes(b, 0, const [0xFF, 0x0A]) ||
      _bytes(b, 0, const [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20]) ||
      _bytes(b, 0, const [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20]) ||
      _bytes(b, 0, const [0xFF, 0x4F, 0xFF, 0x51])) {
    return true;
  }
  // BigTIFF, OpenEXR, ICO.
  if (_bytes(b, 0, const [0x49, 0x49, 0x2B, 0x00]) ||
      _bytes(b, 0, const [0x4D, 0x4D, 0x00, 0x2B]) ||
      _bytes(b, 0, const [0x76, 0x2F, 0x31, 0x01]) ||
      _bytes(b, 0, const [0x00, 0x00, 0x01, 0x00])) {
    return true;
  }
  // SVG and other XML documents, possibly after a BOM or blank characters.
  var start = _bytes(b, 0, const [0xEF, 0xBB, 0xBF]) ? 3 : 0;
  while (start < b.length && start < 64 && b[start] <= 0x20) {
    start++;
  }
  return _ascii(b, start, '<svg') || _ascii(b, start, '<?xml');
}

bool _bytes(Uint8List data, int offset, List<int> signature) {
  if (data.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (data[offset + i] != signature[i]) return false;
  }
  return true;
}

bool _ascii(Uint8List data, int offset, String signature) =>
    _bytes(data, offset, signature.codeUnits);

img.Decoder _decoderFor(SourceFormat format, {int jpegScale = 1}) =>
    switch (format) {
      SourceFormat.jpeg => img.JpegDecoder(scale: jpegScale),
      SourceFormat.png => img.PngDecoder(),
      SourceFormat.gif => img.GifDecoder(),
      SourceFormat.webp => img.WebPDecoder(),
      SourceFormat.bmp => img.BmpDecoder(),
      SourceFormat.tiff => img.TiffDecoder(),
    };

/// Reads format and upright size, and enforces the pixel limit before any
/// pixel buffer is allocated.
SourceHeader readHeader(Uint8List bytes) {
  if (bytes.isEmpty) throw _decodeFailed;
  final format = sniffFormat(bytes);
  final img.DecodeInfo? info;
  try {
    info = _decoderFor(format).startDecode(bytes);
  } catch (error) {
    throw _exceedsLibraryLimit(error) ? _tooLarge : _decodeFailed;
  }
  if (info == null || info.width <= 0 || info.height <= 0) throw _decodeFailed;
  var width = info.width;
  var height = info.height;
  // Compared as a division: a forged header may announce sizes whose product
  // overflows.
  if (width > ImageProcessor.maxSourcePixels ~/ height) throw _tooLarge;
  if (format == SourceFormat.jpeg && _jpegSwapsDimensions(bytes)) {
    final t = width;
    width = height;
    height = t;
  }
  return SourceHeader(format, width, height);
}

/// The library refuses on its own, with a generic exception, sizes above its
/// built-in ceiling (268 megapixels): that is "too large", not "corrupted".
/// The wording is the only way to tell; if it ever changes, such files are
/// reported as undecodable, which is still a refusal.
bool _exceedsLibraryLimit(Object error) =>
    error is img.ImageException && error.message.contains('exceed the maximum');

/// The JPEG decoder bakes the EXIF orientation into the pixels; orientations
/// 5 to 8 are the quarter turns, which exchange width and height.
bool _jpegSwapsDimensions(Uint8List bytes) {
  final exif = img.decodeJpgExif(bytes);
  if (exif == null || !exif.imageIfd.hasOrientation) return false;
  final orientation = exif.imageIfd.orientation ?? 1;
  return orientation >= 5 && orientation <= 8;
}

/// Largest JPEG decode reduction (1, 2, 4 or 8) that still yields at least
/// the wanted resolution, [ratio] being "available pixels / wanted pixels"
/// along the relevant edge.
///
/// A reduced decode skips most of the inverse transform work and averages
/// the pixels it drops, so it is both much faster and free of aliasing.
int jpegScaleFor(double ratio) {
  if (ratio >= 8) return 8;
  if (ratio >= 4) return 4;
  if (ratio >= 2) return 2;
  return 1;
}

/// Decodes [bytes] to upright 8-bit RGB. Transparent pixels are flattened on
/// white, like paper. Only the first frame of an animation is read.
Raster decodeRgb(Uint8List bytes, SourceHeader header, {int jpegScale = 1}) {
  final img.Image? image;
  try {
    image = _decoderFor(
      header.format,
      jpegScale: jpegScale,
    ).decode(bytes, frame: 0);
  } on OutOfMemoryError {
    throw _tooLarge;
  } catch (_) {
    throw _decodeFailed;
  }
  if (image == null || image.width <= 0 || image.height <= 0) {
    throw _decodeFailed;
  }
  return _toRgb(image);
}

Raster _toRgb(img.Image image) {
  final data = image.data;
  if (data is! img.ImageDataUint8 || image.hasPalette) {
    // Palettes, 1/2/4/16-bit and float samples: let the library expand them
    // once, then take the fast path below.
    return _toRgb(image.convert(format: img.Format.uint8, numChannels: 4));
  }
  final width = image.width;
  final height = image.height;
  final src = data.data;
  final pixels = width * height;
  switch (data.numChannels) {
    case 3:
      return Raster(width, height, 3, src);
    case 4:
      final out = Raster.rgb(width, height);
      final dst = out.data;
      for (var i = 0, s = 0, d = 0; i < pixels; i++, s += 4, d += 3) {
        final alpha = src[s + 3];
        if (alpha == 255) {
          dst[d] = src[s];
          dst[d + 1] = src[s + 1];
          dst[d + 2] = src[s + 2];
        } else {
          final white = 255 * (255 - alpha) + 128;
          dst[d] = _div255(src[s] * alpha + white);
          dst[d + 1] = _div255(src[s + 1] * alpha + white);
          dst[d + 2] = _div255(src[s + 2] * alpha + white);
        }
      }
      return out;
    case 1:
      return grayToRgb(Raster(width, height, 1, src));
    case 2:
      final out = Raster.rgb(width, height);
      final dst = out.data;
      for (var i = 0, s = 0, d = 0; i < pixels; i++, s += 2, d += 3) {
        final alpha = src[s + 1];
        final v = _div255(src[s] * alpha + 255 * (255 - alpha) + 128);
        dst[d] = v;
        dst[d + 1] = v;
        dst[d + 2] = v;
      }
      return out;
    default:
      throw _decodeFailed;
  }
}

/// Exact `round(x / 255)` for the 16-bit products of alpha blending.
int _div255(int value) => (value + (value >> 8)) >> 8;

/// Encodes [raster] as JPEG or PNG.
///
/// [draft] trades a little chroma detail for speed and size (previews and
/// thumbnails); final pages keep full-resolution chroma so that coloured
/// text and stamps stay crisp. [twoTone] tells the PNG encoder the pixels
/// are pure black and white, which compress best unfiltered.
Uint8List encodeRaster(
  Raster raster,
  OutputFormat format, {
  required int jpegQuality,
  bool draft = false,
  bool twoTone = false,
}) {
  switch (format) {
    case OutputFormat.jpg:
      // The JPEG encoder only has a fast path for 3-channel images.
      final rgb = raster.isGray ? grayToRgb(raster) : raster;
      return img.encodeJpg(
        _wrap(rgb),
        quality: jpegQuality.clamp(1, 100),
        chroma: draft ? img.JpegChroma.yuv420 : img.JpegChroma.yuv444,
      );
    case OutputFormat.png:
      return img.encodePng(
        _wrap(raster),
        filter: twoTone ? img.PngFilter.none : img.PngFilter.sub,
      );
  }
}

img.Image _wrap(Raster raster) => img.Image.fromBytes(
  width: raster.width,
  height: raster.height,
  bytes: raster.data.buffer,
  bytesOffset: raster.data.offsetInBytes,
  numChannels: raster.channels,
);
