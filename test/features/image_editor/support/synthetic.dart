import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';

/// Projective map from the unit square of a page, (u, v) in [0, 1], to image
/// pixels: `x = (a u + b v + c) / (g u + h v + 1)`, same for y with d, e, f.
///
/// Scenes are drawn through this explicit map and its closed-form inverse,
/// not through the engine's homography solver, so that the tests check the
/// engine against independent geometry.
class Projection {
  const Projection(
    this.a,
    this.b,
    this.c,
    this.d,
    this.e,
    this.f,
    this.g,
    this.h,
  );

  /// A tilted page covering about 43 % of a 1000 x 750 frame.
  static const Projection tilted = Projection(
    700,
    40,
    150,
    -40,
    640,
    70,
    0.10,
    0.14,
  );

  /// The same page scaled to another frame size.
  Projection scaled(double sx, double sy) =>
      Projection(a * sx, b * sx, c * sx, d * sy, e * sy, f * sy, g, h);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;
  final double g;
  final double h;

  math.Point<double> toImage(double u, double v) {
    final w = g * u + h * v + 1;
    return math.Point((a * u + b * v + c) / w, (d * u + e * v + f) / w);
  }

  /// Inverse through the adjugate of the 3x3 matrix.
  math.Point<double> toPage(double x, double y) {
    final i11 = e - f * h;
    final i12 = c * h - b;
    final i13 = b * f - c * e;
    final i21 = f * g - d;
    final i22 = a - c * g;
    final i23 = c * d - a * f;
    final i31 = d * h - e * g;
    final i32 = b * g - a * h;
    final i33 = a * e - b * d;
    final w = i31 * x + i32 * y + i33;
    return math.Point(
      (i11 * x + i12 * y + i13) / w,
      (i21 * x + i22 * y + i23) / w,
    );
  }

  /// Page corners in pixels: top-left, top-right, bottom-right, bottom-left.
  List<math.Point<double>> get corners => [
    toImage(0, 0),
    toImage(1, 0),
    toImage(1, 1),
    toImage(0, 1),
  ];

  Quad quadIn(int width, int height) => Quad.fromCorners([
    for (final p in corners) NormalizedPoint(p.x / width, p.y / height),
  ]);
}

typedef PagePainter = int Function(double u, double v);

const int paperColor = 0xECE9E2;
const int inkColor = 0x282830;
const int markerColor = 0xE01010;

/// Light paper with dark "text lines" that stay clear of the page border.
int stripedPage(double u, double v) {
  if (u > 0.1 && u < 0.9 && v > 0.08 && v < 0.92) {
    final line = (v - 0.08) / 0.07;
    if (line - line.floor() < 0.35) return inkColor;
  }
  return paperColor;
}

/// [stripedPage] plus a red square centred on (0.25, 0.7) of the page.
int markedPage(double u, double v) {
  if ((u - 0.25).abs() < 0.03 && (v - 0.7).abs() < 0.03) return markerColor;
  if ((u - 0.25).abs() < 0.06 && (v - 0.7).abs() < 0.06) return paperColor;
  return stripedPage(u, v);
}

/// Draws [page] through [projection] over a dark, textured table: per-pixel
/// noise plus a slow wood-like ripple.
Raster drawScene({
  required int width,
  required int height,
  required Projection projection,
  PagePainter page = stripedPage,
  int seed = 7,
  int noise = 18,
}) {
  final raster = Raster.rgb(width, height);
  final data = raster.data;
  final random = math.Random(seed);
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = projection.toPage(x + 0.5, y + 0.5);
      if (p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1) {
        final color = page(p.x, p.y);
        data[i] = (color >> 16) & 0xFF;
        data[i + 1] = (color >> 8) & 0xFF;
        data[i + 2] = color & 0xFF;
      } else {
        final ripple = (10 * math.sin(x * 0.045 + y * 0.012)).round();
        final grain = random.nextInt(2 * noise + 1) - noise + ripple;
        data[i] = (96 + grain).clamp(0, 255).toInt();
        data[i + 1] = (80 + grain).clamp(0, 255).toInt();
        data[i + 2] = (66 + grain).clamp(0, 255).toInt();
      }
      i += 3;
    }
  }
  return raster;
}

/// A page filling the whole frame (no background), painted by [page].
Raster drawFlatPage(int width, int height, {PagePainter page = stripedPage}) {
  final raster = Raster.rgb(width, height);
  final data = raster.data;
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = page((x + 0.5) / width, (y + 0.5) / height);
      data[i] = (color >> 16) & 0xFF;
      data[i + 1] = (color >> 8) & 0xFF;
      data[i + 2] = color & 0xFF;
      i += 3;
    }
  }
  return raster;
}

/// Uniformly distributed grey noise between [low] and [high].
Raster drawNoise(
  int width,
  int height, {
  int low = 0,
  int high = 255,
  int seed = 3,
}) {
  final raster = Raster.rgb(width, height);
  final random = math.Random(seed);
  for (var i = 0; i < raster.data.length; i += 3) {
    final v = low + random.nextInt(high - low + 1);
    raster.data[i] = v;
    raster.data[i + 1] = v;
    raster.data[i + 2] = v;
  }
  return raster;
}

/// Multiplies every pixel by a smooth illumination falling from [bright] on
/// the left edge to [dark] on the right edge: a soft shadow.
void castShadow(Raster rgb, {double bright = 1.0, double dark = 0.45}) {
  final data = rgb.data;
  var i = 0;
  for (var y = 0; y < rgb.height; y++) {
    for (var x = 0; x < rgb.width; x++) {
      final t = x / (rgb.width - 1);
      // Smoothstep: no visible edge anywhere.
      final s = t * t * (3 - 2 * t);
      final gain = bright + (dark - bright) * s;
      data[i] = (data[i] * gain).round();
      data[i + 1] = (data[i + 1] * gain).round();
      data[i + 2] = (data[i + 2] * gain).round();
      i += 3;
    }
  }
}

img.Image _toImage(Raster raster) => img.Image.fromBytes(
  width: raster.width,
  height: raster.height,
  bytes: raster.data.buffer,
  bytesOffset: raster.data.offsetInBytes,
  numChannels: raster.channels,
);

Uint8List jpegOf(Raster raster, {int quality = 92, int? exifOrientation}) {
  final image = _toImage(raster);
  if (exifOrientation != null) {
    image.exif.imageIfd.orientation = exifOrientation;
  }
  return img.encodeJpg(image, quality: quality);
}

Uint8List pngOf(Raster raster) => img.encodePng(_toImage(raster), level: 1);

/// Decoded pixels of an encoded result, for assertions.
class Decoded {
  Decoded(this.image);

  factory Decoded.bytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) throw StateError('test output is not a decodable image');
    return Decoded(image);
  }

  final img.Image image;

  int get width => image.width;
  int get height => image.height;
  int get channels => image.numChannels;

  /// Red, green and blue of a pixel (grey images repeat their level).
  List<int> rgb(int x, int y) {
    final p = image.getPixel(x, y);
    if (image.numChannels < 3) {
      final v = p.r.toInt();
      return [v, v, v];
    }
    return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
  }

  double luma(int x, int y) {
    final c = rgb(x, y);
    return (c[0] * 77 + c[1] * 150 + c[2] * 29) / 256;
  }

  /// Mean luma of the rectangle given in fractions of the image.
  double meanLuma([
    double x0 = 0,
    double y0 = 0,
    double x1 = 1,
    double y1 = 1,
  ]) {
    var sum = 0.0;
    var count = 0;
    for (var y = (y0 * height).floor(); y < (y1 * height).ceil(); y++) {
      for (var x = (x0 * width).floor(); x < (x1 * width).ceil(); x++) {
        sum += luma(x, y);
        count++;
      }
    }
    return sum / count;
  }

  /// Centroid, in pixels, of the pixels that are clearly red.
  math.Point<double>? redCentroid() {
    var sx = 0.0;
    var sy = 0.0;
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = rgb(x, y);
        if (c[0] > 150 && c[1] < 90 && c[2] < 90) {
          sx += x + 0.5;
          sy += y + 0.5;
          count++;
        }
      }
    }
    return count == 0 ? null : math.Point(sx / count, sy / count);
  }
}
