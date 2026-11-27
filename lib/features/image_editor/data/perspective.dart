import 'dart:math' as math;
import 'dart:typed_data';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

/// Solves the projective map sending the four points of [from] to those of
/// [to] (each `[x0, y0, x1, y1, x2, y2, x3, y3]`).
///
/// Returns `[a, b, c, d, e, f, g, h]` such that
/// `X = (a x + b y + c) / (g x + h y + 1)` and
/// `Y = (d x + e y + f) / (g x + h y + 1)`, or null when the points are
/// degenerate (three of them aligned).
Float64List? solveHomography(Float64List from, Float64List to) {
  const cols = 9;
  final m = Float64List(8 * cols);
  for (var i = 0; i < 4; i++) {
    final x = from[2 * i];
    final y = from[2 * i + 1];
    final u = to[2 * i];
    final v = to[2 * i + 1];
    var r = 2 * i * cols;
    m[r] = x;
    m[r + 1] = y;
    m[r + 2] = 1;
    m[r + 6] = -u * x;
    m[r + 7] = -u * y;
    m[r + 8] = u;
    r += cols;
    m[r + 3] = x;
    m[r + 4] = y;
    m[r + 5] = 1;
    m[r + 6] = -v * x;
    m[r + 7] = -v * y;
    m[r + 8] = v;
  }
  // Gauss-Jordan elimination with partial pivoting.
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var row = col + 1; row < 8; row++) {
      if (m[row * cols + col].abs() > m[pivot * cols + col].abs()) pivot = row;
    }
    final lead = m[pivot * cols + col];
    if (lead.abs() < 1e-10) return null;
    if (pivot != col) {
      for (var k = 0; k < cols; k++) {
        final t = m[col * cols + k];
        m[col * cols + k] = m[pivot * cols + k];
        m[pivot * cols + k] = t;
      }
    }
    for (var k = col; k < cols; k++) {
      m[col * cols + k] /= lead;
    }
    for (var row = 0; row < 8; row++) {
      if (row == col) continue;
      final factor = m[row * cols + col];
      if (factor == 0) continue;
      for (var k = col; k < cols; k++) {
        m[row * cols + k] -= factor * m[col * cols + k];
      }
    }
  }
  final solution = Float64List(8);
  for (var i = 0; i < 8; i++) {
    final value = m[i * cols + 8];
    if (!value.isFinite) return null;
    solution[i] = value;
  }
  return solution;
}

/// Geometry of a rectification: which source points become the corners of
/// the output, and how large the output is.
final class WarpPlan {
  const WarpPlan(this.corners, this.width, this.height);

  /// Source positions, in source pixels, of the output's top-left,
  /// top-right, bottom-right and bottom-left corners (x, y pairs). Pixel
  /// (i, j) covers the square [i, i+1] x [j, j+1].
  final Float64List corners;
  final int width;
  final int height;
}

Float64List _cornersInPixels(int sourceWidth, int sourceHeight, Quad? quad) {
  final points = (quad ?? Quad.full).clamped().corners;
  final px = Float64List(8);
  for (var i = 0; i < 4; i++) {
    px[2 * i] = points[i].x * sourceWidth;
    px[2 * i + 1] = points[i].y * sourceHeight;
  }
  return px;
}

double _side(Float64List px, int a, int b) {
  final dx = px[2 * b] - px[2 * a];
  final dy = px[2 * b + 1] - px[2 * a + 1];
  return math.sqrt(dx * dx + dy * dy);
}

/// Length in source pixels of the longest side of [quad] (null = whole
/// image): the resolution actually available for the rectified page.
double pageLongEdge(int sourceWidth, int sourceHeight, Quad? quad) {
  final px = _cornersInPixels(sourceWidth, sourceHeight, quad);
  return math.max(
    math.max(_side(px, 0, 1), _side(px, 3, 2)),
    math.max(_side(px, 0, 3), _side(px, 1, 2)),
  );
}

/// Plans the rectification of [quad] (null = whole image) out of a source of
/// [sourceWidth] x [sourceHeight] pixels.
///
/// The page size follows the longest of each pair of opposite sides, is
/// snapped to the standard proportions of [hints] when close to them, then
/// reduced to fit [maxLongEdge]; it is never enlarged. [quarterTurns]
/// clockwise turns are folded into the corner order, so rotating costs no
/// extra pass over the pixels.
WarpPlan planWarp({
  required int sourceWidth,
  required int sourceHeight,
  required Quad? quad,
  required int quarterTurns,
  required int maxLongEdge,
  ProcessingHints? hints,
}) {
  final px = _cornersInPixels(sourceWidth, sourceHeight, quad);
  var pageWidth = math.max(_side(px, 0, 1), _side(px, 3, 2));
  var pageHeight = math.max(_side(px, 0, 3), _side(px, 1, 2));
  if (hints != null && quad != null && pageWidth > 0 && pageHeight > 0) {
    final landscape = pageWidth >= pageHeight;
    final long = landscape ? pageWidth : pageHeight;
    final short = landscape ? pageHeight : pageWidth;
    final snappedShort = long / hints.resolveAspect(long / short);
    if (landscape) {
      pageHeight = snappedShort;
    } else {
      pageWidth = snappedShort;
    }
  }
  final long = math.max(pageWidth, pageHeight);
  final scale = long > maxLongEdge ? maxLongEdge / long : 1.0;
  var outWidth = math.max(1, (pageWidth * scale).round());
  var outHeight = math.max(1, (pageHeight * scale).round());
  // Rounding must never push the long edge above the limit.
  outWidth = math.min(outWidth, math.max(1, maxLongEdge));
  outHeight = math.min(outHeight, math.max(1, maxLongEdge));

  final turns = quarterTurns % 4;
  final corners = Float64List(8);
  for (var k = 0; k < 4; k++) {
    // After a clockwise quarter turn the page's bottom-left corner sits at
    // the top-left of the output, hence the shift of the corner order.
    final from = (k - turns + 4) % 4;
    corners[2 * k] = px[2 * from];
    corners[2 * k + 1] = px[2 * from + 1];
  }
  return turns.isOdd
      ? WarpPlan(corners, outHeight, outWidth)
      : WarpPlan(corners, outWidth, outHeight);
}

/// Resamples the quadrilateral described by [plan] into an upright
/// rectangle: true perspective correction (homography) with bilinear
/// sampling in 8-bit fixed point.
///
/// Throws a [FailureException] when the corners are degenerate.
Raster warp(Raster source, WarpPlan plan) {
  assert(source.channels == 3);
  final outWidth = plan.width;
  final outHeight = plan.height;
  if (_isIdentity(source, plan)) return source;

  var src = source;
  var corners = plan.corners;
  if (src.width < 2 || src.height < 2) {
    // The sampler reads a 2x2 neighbourhood: give one-pixel-thin sources a
    // second row/column instead of special-casing the inner loop.
    final padded = _padToTwo(src);
    final sx = padded.width / src.width;
    final sy = padded.height / src.height;
    corners = Float64List(8);
    for (var i = 0; i < 4; i++) {
      corners[2 * i] = plan.corners[2 * i] * sx;
      corners[2 * i + 1] = plan.corners[2 * i + 1] * sy;
    }
    src = padded;
  }

  final w = outWidth.toDouble();
  final h = outHeight.toDouble();
  final hm = solveHomography(
    Float64List.fromList([0, 0, w, 0, w, h, 0, h]),
    corners,
  );
  if (hm == null) {
    throw const FailureException(
      ImageFailure(
        ImageFailureKind.processingFailed,
        debugMessage: 'degenerate_quad',
      ),
    );
  }
  final a = hm[0];
  final b = hm[1];
  final c = hm[2];
  final d = hm[3];
  final e = hm[4];
  final f = hm[5];
  final g = hm[6];
  final hh = hm[7];

  final s = src.data;
  final sw = src.width;
  final stride = sw * 3;
  // Positions are 24.8 fixed point. Stopping one unit short of the last
  // pixel keeps the "+1" neighbours inside the buffer.
  final maxX = ((sw - 1) * 256 - 1).toDouble();
  final maxY = ((src.height - 1) * 256 - 1).toDouble();
  final out = Raster.rgb(outWidth, outHeight);
  final o = out.data;
  var di = 0;
  for (var y = 0; y < outHeight; y++) {
    // Output pixel centres are at +0.5; source pixel centres too, hence the
    // -128 (half a pixel in fixed point) below.
    final v = y + 0.5;
    var nx = a * 0.5 + b * v + c;
    var ny = d * 0.5 + e * v + f;
    var dn = g * 0.5 + hh * v + 1.0;
    for (var x = 0; x < outWidth; x++) {
      final inv = 256.0 / dn;
      var fx = nx * inv - 128.0;
      var fy = ny * inv - 128.0;
      nx += a;
      ny += d;
      dn += g;
      // Written so that NaN (degenerate denominator) also lands on 0.
      if (!(fx >= 0.0)) {
        fx = 0.0;
      } else if (fx > maxX) {
        fx = maxX;
      }
      if (!(fy >= 0.0)) {
        fy = 0.0;
      } else if (fy > maxY) {
        fy = maxY;
      }
      final ix = fx.toInt();
      final iy = fy.toInt();
      final tx = ix & 255;
      final ty = iy & 255;
      final i00 = (iy >> 8) * stride + (ix >> 8) * 3;
      final i01 = i00 + stride;
      final w00 = (256 - tx) * (256 - ty);
      final w10 = tx * (256 - ty);
      final w01 = (256 - tx) * ty;
      final w11 = tx * ty;
      o[di] =
          (s[i00] * w00 +
              s[i00 + 3] * w10 +
              s[i01] * w01 +
              s[i01 + 3] * w11 +
              32768) >>
          16;
      o[di + 1] =
          (s[i00 + 1] * w00 +
              s[i00 + 4] * w10 +
              s[i01 + 1] * w01 +
              s[i01 + 4] * w11 +
              32768) >>
          16;
      o[di + 2] =
          (s[i00 + 2] * w00 +
              s[i00 + 5] * w10 +
              s[i01 + 2] * w01 +
              s[i01 + 5] * w11 +
              32768) >>
          16;
      di += 3;
    }
  }
  return out;
}

/// Resizes the whole of [source] to [width] x [height].
Raster resize(Raster source, int width, int height) {
  final w = source.width.toDouble();
  final h = source.height.toDouble();
  return warp(
    source,
    WarpPlan(Float64List.fromList([0, 0, w, 0, w, h, 0, h]), width, height),
  );
}

bool _isIdentity(Raster source, WarpPlan plan) {
  if (plan.width != source.width || plan.height != source.height) return false;
  final w = source.width.toDouble();
  final h = source.height.toDouble();
  final c = plan.corners;
  return c[0] == 0 &&
      c[1] == 0 &&
      c[2] == w &&
      c[3] == 0 &&
      c[4] == w &&
      c[5] == h &&
      c[6] == 0 &&
      c[7] == h;
}

Raster _padToTwo(Raster src) {
  final width = math.max(2, src.width);
  final height = math.max(2, src.height);
  final out = Raster.rgb(width, height);
  for (var y = 0; y < height; y++) {
    final sy = math.min(y, src.height - 1);
    for (var x = 0; x < width; x++) {
      final sx = math.min(x, src.width - 1);
      final si = (sy * src.width + sx) * 3;
      final di = (y * width + x) * 3;
      out.data[di] = src.data[si];
      out.data[di + 1] = src.data[si + 1];
      out.data[di + 2] = src.data[si + 2];
    }
  }
  return out;
}
