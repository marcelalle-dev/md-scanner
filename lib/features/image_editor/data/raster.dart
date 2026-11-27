import 'dart:math' as math;
import 'dart:typed_data';

/// 8-bit pixels in a plain [Uint8List]: interleaved RGB when [channels] is 3,
/// grey levels when it is 1.
///
/// Every pixel loop of the engine works on this instead of `package:image`
/// accessors: direct typed-data indexing is an order of magnitude faster.
final class Raster {
  Raster(this.width, this.height, this.channels, this.data)
    : assert(width > 0 && height > 0),
      assert(channels == 1 || channels == 3),
      assert(data.length == width * height * channels);

  factory Raster.rgb(int width, int height) =>
      Raster(width, height, 3, Uint8List(width * height * 3));

  factory Raster.gray(int width, int height) =>
      Raster(width, height, 1, Uint8List(width * height));

  final int width;
  final int height;
  final int channels;
  final Uint8List data;

  bool get isGray => channels == 1;

  int get longEdge => math.max(width, height);

  int get shortEdge => math.min(width, height);
}

/// Rec. 601 luma of [rgb] as a single-channel raster.
Raster luminanceOf(Raster rgb) {
  assert(rgb.channels == 3);
  final src = rgb.data;
  final out = Raster.gray(rgb.width, rgb.height);
  final dst = out.data;
  for (var i = 0, j = 0; i < dst.length; i++, j += 3) {
    dst[i] = (src[j] * 77 + src[j + 1] * 150 + src[j + 2] * 29) >> 8;
  }
  return out;
}

/// Grey levels replicated on three channels (what the JPEG encoder expects).
Raster grayToRgb(Raster gray) {
  assert(gray.channels == 1);
  final src = gray.data;
  final out = Raster.rgb(gray.width, gray.height);
  final dst = out.data;
  for (var i = 0, j = 0; i < src.length; i++, j += 3) {
    final v = src[i];
    dst[j] = v;
    dst[j + 1] = v;
    dst[j + 2] = v;
  }
  return out;
}

/// Halves both dimensions by averaging 2x2 blocks (rounding sizes up, the
/// last row/column is repeated when a dimension is odd).
Raster halve(Raster rgb) {
  assert(rgb.channels == 3);
  final sw = rgb.width;
  final sh = rgb.height;
  final dw = (sw + 1) >> 1;
  final dh = (sh + 1) >> 1;
  final src = rgb.data;
  final out = Raster.rgb(dw, dh);
  final dst = out.data;
  final stride = sw * 3;
  var di = 0;
  for (var y = 0; y < dh; y++) {
    final top = (y * 2) * stride;
    final bottom = math.min(y * 2 + 1, sh - 1) * stride;
    for (var x = 0; x < dw; x++) {
      final left = (x * 2) * 3;
      final right = math.min(x * 2 + 1, sw - 1) * 3;
      for (var c = 0; c < 3; c++) {
        dst[di++] =
            (src[top + left + c] +
                src[top + right + c] +
                src[bottom + left + c] +
                src[bottom + right + c] +
                2) >>
            2;
      }
    }
  }
  return out;
}

/// Halves [rgb] as long as it stays at least twice as large as needed, where
/// [ratio] is "available pixels / wanted pixels" along the relevant edge.
///
/// Bilinear sampling only reads 2x2 source pixels: reducing by more than 2 in
/// one go would skip pixels and alias fine print. Box-halving first keeps
/// every source pixel in the result.
Raster reduceForRatio(Raster rgb, double ratio) {
  var current = rgb;
  var remaining = ratio;
  while (remaining >= 2 && current.width > 1 && current.height > 1) {
    current = halve(current);
    remaining /= 2;
  }
  return current;
}
