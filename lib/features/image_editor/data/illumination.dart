import 'dart:math' as math;
import 'dart:typed_data';

import 'package:md_scanner/features/image_editor/data/raster.dart';

/// Coarse estimate of what the page would look like without anything
/// printed on it: one value per cell (and per plane) of a grid laid over the
/// image.
///
/// Each cell holds the brightest of its 4x4 sub-tile averages. Averaging
/// first makes the estimate immune to isolated hot pixels; taking the
/// brightest sub-tile then ignores text, which never covers a whole cell.
/// A 3x3 dilation lets paper win over cells entirely covered by ink (thick
/// headings, logos) and two box blurs remove the grid structure.
final class BackgroundMap {
  BackgroundMap._(this.cols, this.rows, this.cell, this.planes);

  /// Estimates the background of [rgb]: one luma plane, or one plane per
  /// channel when [perChannel] is true (which also captures the tint of the
  /// paper and of the light).
  factory BackgroundMap.estimate(Raster rgb, {required bool perChannel}) {
    assert(rgb.channels == 3);
    final w = rgb.width;
    final h = rgb.height;
    final data = rgb.data;
    // Grid proportional to the image so that previews and full-size renders
    // normalize the same way.
    final tile = math.max(1, (math.max(w, h) / 160).round());
    final tileCols = (w + tile - 1) ~/ tile;
    final tileRows = (h + tile - 1) ~/ tile;
    final cols = (tileCols + 3) ~/ 4;
    final rows = (tileRows + 3) ~/ 4;
    final planeCount = perChannel ? 3 : 1;
    final planes = List.generate(planeCount, (_) => Float32List(cols * rows));
    final sums = Int32List(tileCols * 3);

    for (var ty = 0; ty < tileRows; ty++) {
      sums.fillRange(0, sums.length, 0);
      final y0 = ty * tile;
      final y1 = math.min(h, y0 + tile);
      for (var y = y0; y < y1; y++) {
        var i = y * w * 3;
        for (var tx = 0; tx < tileCols; tx++) {
          final x1 = math.min(w, (tx + 1) * tile);
          var sr = 0;
          var sg = 0;
          var sb = 0;
          for (var x = tx * tile; x < x1; x++) {
            sr += data[i];
            sg += data[i + 1];
            sb += data[i + 2];
            i += 3;
          }
          sums[tx * 3] += sr;
          sums[tx * 3 + 1] += sg;
          sums[tx * 3 + 2] += sb;
        }
      }
      final cellRow = (ty ~/ 4) * cols;
      for (var tx = 0; tx < tileCols; tx++) {
        final count = (math.min(w, (tx + 1) * tile) - tx * tile) * (y1 - y0);
        final r = sums[tx * 3] / count;
        final g = sums[tx * 3 + 1] / count;
        final b = sums[tx * 3 + 2] / count;
        final cell = cellRow + tx ~/ 4;
        if (perChannel) {
          if (r > planes[0][cell]) planes[0][cell] = r;
          if (g > planes[1][cell]) planes[1][cell] = g;
          if (b > planes[2][cell]) planes[2][cell] = b;
        } else {
          final l = (r * 77 + g * 150 + b * 29) / 256;
          if (l > planes[0][cell]) planes[0][cell] = l;
        }
      }
    }
    for (var p = 0; p < planeCount; p++) {
      var plane = _window3(planes[p], cols, rows, maximum: true);
      plane = _window3(plane, cols, rows, maximum: false);
      planes[p] = _window3(plane, cols, rows, maximum: false);
    }
    return BackgroundMap._(cols, rows, tile * 4, planes);
  }

  final int cols;
  final int rows;

  /// Side of a cell, in pixels.
  final int cell;

  /// One [Float32List] of `cols * rows` levels (0..255) per plane.
  final List<Float32List> planes;

  /// Level of the well-lit paper on plane [p]: the upper quartile of the
  /// map, robust to both shadows (lower) and glare (higher).
  double reference(int p) {
    final sorted = Float32List.fromList(planes[p])..sort();
    return sorted[(sorted.length * 3) ~/ 4];
  }

  /// Per-cell multipliers, in 22.10 fixed point, that bring the background
  /// of plane [p] to [target]. The background is floored at [floorFraction]
  /// of [reference]: anything darker is treated as content (a photo, a dark
  /// banner), not as paper in the shade, and is not blown up to white.
  Int32List gains(
    int p, {
    required double target,
    required double floorFraction,
  }) {
    final plane = planes[p];
    final floor = math.max(16.0, reference(p) * floorFraction);
    final out = Int32List(plane.length);
    for (var i = 0; i < plane.length; i++) {
      final gain = target / math.max(plane[i], floor);
      out[i] = (math.min(gain, _maxGain) * 1024).round();
    }
    return out;
  }

  /// Multiplies every pixel of [rgb] by the bilinearly interpolated gain of
  /// its position, clamps, then maps the result through [curve].
  ///
  /// [gainPlanes] holds one plane (same gain for the three channels, hue
  /// preserved) or three (one per channel).
  void apply(Raster rgb, List<Int32List> gainPlanes, Uint8List curve) {
    final w = rgb.width;
    final h = rgb.height;
    final data = rgb.data;
    final shared = gainPlanes.length == 1;
    // Horizontal interpolation tables: left cell and 8-bit weight of the
    // right cell for every column.
    final cellOf = Int32List(w);
    final weightOf = Int32List(w);
    for (var x = 0; x < w; x++) {
      final pos = ((x + 0.5) / cell - 0.5).clamp(0.0, cols - 1.0);
      final c0 = math.min(pos.floor(), math.max(0, cols - 2));
      cellOf[x] = c0;
      weightOf[x] = cols < 2 ? 0 : ((pos - c0) * 256).round();
    }
    // Gains of the current row, vertically interpolated, one extra entry so
    // that "cell + 1" is always readable.
    final rowGains = List.generate(
      gainPlanes.length,
      (_) => Int32List(cols + 1),
    );
    var i = 0;
    for (var y = 0; y < h; y++) {
      final pos = ((y + 0.5) / cell - 0.5).clamp(0.0, rows - 1.0);
      final r0 = math.min(pos.floor(), math.max(0, rows - 2));
      final r1 = math.min(r0 + 1, rows - 1);
      final wy = ((pos - r0) * 256).round();
      for (var p = 0; p < gainPlanes.length; p++) {
        final source = gainPlanes[p];
        final target = rowGains[p];
        for (var c = 0; c < cols; c++) {
          final a = source[r0 * cols + c];
          final b = source[r1 * cols + c];
          target[c] = a + (((b - a) * wy) >> 8);
        }
        target[cols] = target[cols - 1];
      }
      final g0 = rowGains[0];
      final g1 = shared ? g0 : rowGains[1];
      final g2 = shared ? g0 : rowGains[2];
      for (var x = 0; x < w; x++) {
        final c = cellOf[x];
        final wx = weightOf[x];
        final ga = g0[c] + (((g0[c + 1] - g0[c]) * wx) >> 8);
        var r = (data[i] * ga) >> 10;
        final int gb;
        final int gc;
        if (shared) {
          gb = ga;
          gc = ga;
        } else {
          gb = g1[c] + (((g1[c + 1] - g1[c]) * wx) >> 8);
          gc = g2[c] + (((g2[c + 1] - g2[c]) * wx) >> 8);
        }
        var g = (data[i + 1] * gb) >> 10;
        var b = (data[i + 2] * gc) >> 10;
        if (r > 255) r = 255;
        if (g > 255) g = 255;
        if (b > 255) b = 255;
        data[i] = curve[r];
        data[i + 1] = curve[g];
        data[i + 2] = curve[b];
        i += 3;
      }
    }
  }

  /// Amplifying a very dark area more than this only reveals sensor noise.
  static const double _maxGain = 4;

  static Float32List _window3(
    Float32List src,
    int cols,
    int rows, {
    required bool maximum,
  }) {
    final out = Float32List(src.length);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        var acc = 0.0;
        var count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= rows) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= cols) continue;
            final v = src[yy * cols + xx];
            if (maximum) {
              if (v > acc) acc = v;
            } else {
              acc += v;
            }
            count++;
          }
        }
        out[y * cols + x] = maximum ? acc : acc / count;
      }
    }
    return out;
  }
}

/// "White point then gamma" curve applied to background-normalized pixels,
/// where 255 means "as bright as the paper".
///
/// Everything at or above [whitePoint] (0..1) becomes pure white, which
/// erases paper grain and residual shading; the rest is darkened by
/// [gamma] (>= 1), which thickens and blackens the ink.
Uint8List paperCurve({required double whitePoint, required double gamma}) {
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    final x = math.min(1.0, v / 255 / whitePoint);
    lut[v] = (math.pow(x, gamma) * 255).round().clamp(0, 255).toInt();
  }
  return lut;
}

/// Readability filter, in place: the background of each channel is brought
/// to white (paper tint and lighting cast included), then [paperCurve]
/// whitens what is almost paper and darkens the ink. Colours survive: a red
/// stamp stays red, only cleaner.
///
/// [strength] (0..1) lowers the white point and raises the gamma.
void whitenPaper(Raster rgb, double strength) {
  final map = BackgroundMap.estimate(rgb, perChannel: true);
  final floorFraction = 0.6 - 0.2 * strength;
  final gains = [
    for (var p = 0; p < 3; p++)
      map.gains(p, target: 255, floorFraction: floorFraction),
  ];
  final curve = paperCurve(
    whitePoint: 0.93 - 0.10 * strength,
    gamma: 1.2 + 0.8 * strength,
  );
  map.apply(rgb, gains, curve);
}

/// No-shadow filter, in place: divides the image by its luma background so
/// that the paper has the same brightness everywhere. One gain for the
/// three channels: hues and the natural tint of the paper are untouched.
///
/// [strength] (0..1) raises the level the paper is brought to, from "as
/// bright as its best-lit part" (0) to nearly white (1), and above 0.5 adds
/// a mild [paperCurve] (whiteboards: white board, bold strokes).
void evenIllumination(Raster rgb, double strength) {
  final map = BackgroundMap.estimate(rgb, perChannel: false);
  final reference = map.reference(0);
  final target = reference + math.max(0.0, 250 - reference) * strength;
  final gains = [
    map.gains(0, target: target, floorFraction: 0.6 - 0.2 * strength),
  ];
  final extra = math.max(0.0, 2 * strength - 1);
  final curve = paperCurve(
    whitePoint: 1 - 0.08 * extra,
    gamma: 1 + 0.35 * extra,
  );
  map.apply(rgb, gains, curve);
}
