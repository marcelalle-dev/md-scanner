import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';

/// Largest image decoded in memory when a file cannot be embedded as it is.
const int kMaxDecodedImagePixels = 64000000;

/// An image ready to be written as a PDF image XObject.
class EmbeddableImage {
  const EmbeddableImage({
    required this.width,
    required this.height,
    required this.dictionary,
    required this.data,
    this.orientation = 1,
  });

  /// Stored pixel dimensions.
  final int width;
  final int height;

  /// Entries of the image dictionary after /Width and /Height, in PDF syntax.
  final String dictionary;

  /// Stream payload, already encoded as [dictionary] declares.
  final Uint8List data;

  /// EXIF orientation (1 to 8) to apply when drawing the stored pixels.
  final int orientation;

  int get displayWidth => orientation >= 5 ? height : width;
  int get displayHeight => orientation >= 5 ? width : height;

  /// Matrix that maps the stored unit square onto the upright unit square.
  List<int> get orientationMatrix => switch (orientation) {
    2 => const [-1, 0, 0, 1, 1, 0],
    3 => const [-1, 0, 0, -1, 1, 1],
    4 => const [1, 0, 0, -1, 0, 1],
    5 => const [0, -1, -1, 0, 1, 1],
    6 => const [0, -1, 1, 0, 0, 1],
    7 => const [0, 1, 1, 0, 0, 0],
    8 => const [0, 1, -1, 0, 1, 0],
    _ => const [1, 0, 0, 1, 0, 0],
  };
}

bool looksLikeJpeg(Uint8List bytes) =>
    bytes.length > 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;

const List<int> _pngSignature = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

bool looksLikePng(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}

/// Wraps a JPEG file for embedding without recompression (DCTDecode), or
/// returns null when it is not a baseline/progressive 8-bit JPEG that every
/// PDF reader decodes.
///
/// PDF readers ignore EXIF: a rotated photo is reported through
/// [EmbeddableImage.orientation] and its EXIF tag is reset in [bytes], so
/// tools that honour the tag do not rotate the picture a second time.
EmbeddableImage? jpegForEmbedding(Uint8List bytes) {
  if (!looksLikeJpeg(bytes)) return null;
  int? width;
  int? height;
  int? components;
  var orientation = 1;
  var adobe = false;
  var p = 2;
  while (p + 4 <= bytes.length) {
    if (bytes[p] != 0xFF) return null;
    final marker = bytes[p + 1];
    if (marker == 0xFF) {
      p++;
      continue;
    }
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      p += 2;
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) break;
    final length = (bytes[p + 2] << 8) | bytes[p + 3];
    final start = p + 4;
    final end = p + 2 + length;
    if (length < 2 || end > bytes.length) return null;
    if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
      if (end - start < 6 || bytes[start] != 8) return null;
      height = (bytes[start + 1] << 8) | bytes[start + 2];
      width = (bytes[start + 3] << 8) | bytes[start + 4];
      components = bytes[start + 5];
    } else if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      // Lossless, hierarchical or arithmetic-coded JPEG.
      return null;
    } else if (marker == 0xE1) {
      final found = _exifOrientation(bytes, start, end);
      if (found != null) {
        orientation = found.value;
        bytes[found.offset] = found.littleEndian ? 1 : 0;
        bytes[found.offset + 1] = found.littleEndian ? 0 : 1;
      }
    } else if (marker == 0xEE) {
      adobe =
          end - start >= 5 &&
          String.fromCharCodes(bytes, start, start + 5) == 'Adobe';
    }
    p = end;
  }
  if (width == null || height == null || width == 0 || height == 0) return null;
  final colorSpace = switch (components) {
    1 => '/DeviceGray',
    3 => '/DeviceRGB',
    // Adobe writes CMYK JPEGs with inverted samples.
    4 => adobe ? '/DeviceCMYK /Decode [1 0 1 0 1 0 1 0]' : '/DeviceCMYK',
    _ => null,
  };
  if (colorSpace == null) return null;
  return EmbeddableImage(
    width: width,
    height: height,
    dictionary:
        '/ColorSpace $colorSpace /BitsPerComponent 8 /Filter /DCTDecode',
    data: bytes,
    orientation: orientation,
  );
}

({int value, int offset, bool littleEndian})? _exifOrientation(
  Uint8List b,
  int start,
  int end,
) {
  if (end - start < 14 ||
      String.fromCharCodes(b, start, start + 4) != 'Exif' ||
      b[start + 4] != 0 ||
      b[start + 5] != 0) {
    return null;
  }
  final tiff = start + 6;
  final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49;
  final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D;
  if (!little && !big) return null;
  int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
  int u32(int o) => little
      ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
      : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  if (u16(tiff + 2) != 42) return null;
  final directory = tiff + u32(tiff + 4);
  if (directory < tiff || directory + 2 > end) return null;
  final count = u16(directory);
  for (var i = 0; i < count; i++) {
    final entry = directory + 2 + i * 12;
    if (entry + 12 > end) return null;
    if (u16(entry) != 0x0112) continue;
    // A single SHORT, stored inline in the entry.
    if (u16(entry + 2) != 3 || u32(entry + 4) != 1) return null;
    final value = u16(entry + 8);
    if (value < 1 || value > 8) return null;
    return (value: value, offset: entry + 8, littleEndian: little);
  }
  return null;
}

/// Wraps an opaque gray or RGB PNG for embedding without recompression: its
/// IDAT data is exactly what FlateDecode with the PNG predictor expects.
/// Returns null for PNGs that need decoding (palette, alpha, interlacing).
EmbeddableImage? pngForEmbedding(Uint8List bytes) {
  if (!looksLikePng(bytes)) return null;
  int u32(int o) =>
      (bytes[o] << 24) |
      (bytes[o + 1] << 16) |
      (bytes[o + 2] << 8) |
      bytes[o + 3];
  int? width;
  int? height;
  var depth = 0;
  var colorType = -1;
  final data = BytesBuilder(copy: false);
  var p = _pngSignature.length;
  var ended = false;
  while (!ended && p + 12 <= bytes.length) {
    final length = u32(p);
    final type = String.fromCharCodes(bytes, p + 4, p + 8);
    final start = p + 8;
    final end = start + length;
    if (end + 4 > bytes.length) return null;
    switch (type) {
      case 'IHDR':
        if (length != 13) return null;
        width = u32(start);
        height = u32(start + 4);
        depth = bytes[start + 8];
        colorType = bytes[start + 9];
        final plain =
            bytes[start + 10] == 0 &&
            bytes[start + 11] == 0 &&
            bytes[start + 12] == 0;
        if (!plain) return null;
      case 'tRNS':
        return null;
      case 'IDAT':
        data.add(Uint8List.sublistView(bytes, start, end));
      case 'IEND':
        ended = true;
    }
    p = end + 4;
  }
  final supported = switch (colorType) {
    0 => const [1, 2, 4, 8, 16].contains(depth),
    2 => depth == 8 || depth == 16,
    _ => false,
  };
  if (!supported ||
      width == null ||
      height == null ||
      width < 1 ||
      height < 1 ||
      data.isEmpty) {
    return null;
  }
  final colors = colorType == 0 ? 1 : 3;
  final colorSpace = colors == 1 ? '/DeviceGray' : '/DeviceRGB';
  return EmbeddableImage(
    width: width,
    height: height,
    dictionary:
        '/ColorSpace $colorSpace /BitsPerComponent $depth '
        '/Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors $colors '
        '/BitsPerComponent $depth /Columns $width >>',
    data: data.takeBytes(),
  );
}

/// Decodes any image the `image` package understands and re-encodes it for
/// a PDF page: PNG pixels stay lossless (Flate), other formats become JPEG
/// (quality 90). Transparency is flattened on white, as on paper.
/// Synchronous and CPU-bound: run it in a background isolate.
Result<EmbeddableImage> decodeImageFileForEmbedding(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (decoder == null || info == null) {
      return const Err(ImageFailure(ImageFailureKind.unsupportedFormat));
    }
    if (info.width * info.height > kMaxDecodedImagePixels) {
      return const Err(ImageFailure(ImageFailureKind.tooLarge));
    }
    final decoded = decoder.decode(bytes);
    if (decoded == null || decoded.width < 1 || decoded.height < 1) {
      return const Err(ImageFailure(ImageFailureKind.decodeFailed));
    }
    final rgba = decoded
        .convert(format: img.Format.uint8, numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    final pixelCount = decoded.width * decoded.height;
    final rgb = Uint8List(pixelCount * 3);
    var gray = true;
    for (var source = 0, target = 0; target < rgb.length; source += 4) {
      final alpha = rgba[source + 3];
      final white = 255 * (255 - alpha) + 127;
      final r = (rgba[source] * alpha + white) ~/ 255;
      final g = (rgba[source + 1] * alpha + white) ~/ 255;
      final b = (rgba[source + 2] * alpha + white) ~/ 255;
      if (r != g || g != b) gray = false;
      rgb[target++] = r;
      rgb[target++] = g;
      rgb[target++] = b;
    }
    if (decoder is! img.PngDecoder) {
      final flattened = img.Image.fromBytes(
        width: decoded.width,
        height: decoded.height,
        bytes: rgb.buffer,
        numChannels: 3,
      );
      return Success(
        EmbeddableImage(
          width: decoded.width,
          height: decoded.height,
          dictionary:
              '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode',
          data: img.encodeJpg(flattened, quality: 90),
        ),
      );
    }
    var samples = rgb;
    if (gray) {
      samples = Uint8List(pixelCount);
      for (var i = 0; i < pixelCount; i++) {
        samples[i] = rgb[i * 3];
      }
    }
    final colorSpace = gray ? '/DeviceGray' : '/DeviceRGB';
    return Success(
      EmbeddableImage(
        width: decoded.width,
        height: decoded.height,
        dictionary:
            '/ColorSpace $colorSpace /BitsPerComponent 8 /Filter /FlateDecode',
        data: Uint8List.fromList(zlib.encode(samples)),
      ),
    );
  } on PathNotFoundException {
    return const Err(StorageFailure(StorageFailureKind.notFound));
  } on FileSystemException {
    return const Err(StorageFailure(StorageFailureKind.readError));
  } on Exception catch (error) {
    return Err(
      ImageFailure(
        ImageFailureKind.decodeFailed,
        debugMessage: error.runtimeType.toString(),
      ),
    );
  } on Error catch (error) {
    return Err(
      ImageFailure(
        ImageFailureKind.decodeFailed,
        debugMessage: error.runtimeType.toString(),
      ),
    );
  }
}
