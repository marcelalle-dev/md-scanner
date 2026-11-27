import 'dart:math' as math;
import 'dart:typed_data';

import 'package:md_scanner/features/image_editor/data/outline_geometry.dart';

/// Sobel gradients of the (blurred) detection image.
final class GradientField {
  GradientField(this.width, this.height, this.gx, this.gy, this.edgeStrength);

  final int width;
  final int height;

  /// Raw Sobel responses: eight times the grey slope per pixel.
  final Int16List gx;
  final Int16List gy;

  /// Smallest edge response, in "Sobel / 4" units, that counts as a real
  /// edge when measuring how well a side is supported.
  final double edgeStrength;

  /// Gradient along the direction `(nx, ny)` at a sub-pixel position, in
  /// "Sobel / 4" units (about twice the grey slope per pixel). Zero outside
  /// the area where the Sobel operator is defined.
  double along(double x, double y, double nx, double ny) {
    if (!(x >= 1 && y >= 1 && x < width - 2 && y < height - 2)) return 0;
    final x0 = x.floor();
    final y0 = y.floor();
    final tx = x - x0;
    final ty = y - y0;
    final i = y0 * width + x0;
    final w00 = (1 - tx) * (1 - ty);
    final w10 = tx * (1 - ty);
    final w01 = (1 - tx) * ty;
    final w11 = tx * ty;
    final sx =
        gx[i] * w00 +
        gx[i + 1] * w10 +
        gx[i + width] * w01 +
        gx[i + width + 1] * w11;
    final sy =
        gy[i] * w00 +
        gy[i + 1] * w10 +
        gy[i + width] * w01 +
        gy[i + width + 1] * w11;
    return (sx * nx + sy * ny) / 4;
  }
}

/// Result of [snapToEdges].
final class SnappedQuad {
  const SnappedQuad(this.corners, this.support);

  /// Clockwise from the top-left corner, `[x0, y0, ... x3, y3]`.
  final Float64List corners;

  /// For each side (top, right, bottom, left): share of its length lying on
  /// an edge that runs along it with a consistent light/dark direction.
  final Float64List support;
}

const int _samplesPerSide = 48;

/// Part of each side ignored next to its corners, where the two edges meet
/// and the gradient direction is undefined (rounded or dog-eared corners).
const double _cornerMargin = 0.08;

/// Moves each side of a clockwise quad onto the strongest edge found within
/// [range] pixels along its normal, then recomputes the corners as the
/// intersections of the fitted sides.
///
/// For every sample along a side the gradient is projected on the side's
/// normal: an edge crossing the side contributes nothing, only an edge that
/// runs along it does. Samples whose light/dark direction disagrees with the
/// majority of their side are discarded, which is what makes random texture
/// score low. A side with too few supported samples keeps its position.
///
/// Returns null when the quad is degenerate.
SnappedQuad? snapToEdges(Float64List quad, GradientField field, int range) {
  final lines = Float64List(16);
  final support = Float64List(4);
  final xs = Float64List(_samplesPerSide);
  final ys = Float64List(_samplesPerSide);
  final signs = Int8List(_samplesPerSide);

  for (var k = 0; k < 4; k++) {
    final ax = quad[2 * k];
    final ay = quad[2 * k + 1];
    final bx = quad[2 * ((k + 1) % 4)];
    final by = quad[2 * ((k + 1) % 4) + 1];
    final length = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    if (length < 8) return null;
    final ux = (bx - ax) / length;
    final uy = (by - ay) / length;
    final nx = uy;
    final ny = -ux;

    var count = 0;
    var positives = 0;
    for (var i = 0; i < _samplesPerSide; i++) {
      final t =
          _cornerMargin + (1 - 2 * _cornerMargin) * (i + 0.5) / _samplesPerSide;
      final px = ax + (bx - ax) * t;
      final py = ay + (by - ay) * t;
      var bestOffset = 0;
      var best = 0.0;
      var bestSigned = 0.0;
      for (var o = -range; o <= range; o++) {
        final v = field.along(px + o * nx, py + o * ny, nx, ny);
        if (v.abs() > best) {
          best = v.abs();
          bestSigned = v;
          bestOffset = o;
        }
      }
      if (best < field.edgeStrength) continue;
      // Parabolic interpolation of the ridge position between samples.
      final before = field
          .along(px + (bestOffset - 1) * nx, py + (bestOffset - 1) * ny, nx, ny)
          .abs();
      final after = field
          .along(px + (bestOffset + 1) * nx, py + (bestOffset + 1) * ny, nx, ny)
          .abs();
      final curvature = before - 2 * best + after;
      final delta = curvature < 0
          ? (0.5 * (before - after) / curvature).clamp(-0.5, 0.5).toDouble()
          : 0.0;
      final offset = bestOffset + delta;
      xs[count] = px + offset * nx;
      ys[count] = py + offset * ny;
      signs[count] = bestSigned > 0 ? 1 : -1;
      if (bestSigned > 0) positives++;
      count++;
    }

    final majority = positives * 2 >= count ? 1 : -1;
    var kept = 0;
    for (var i = 0; i < count; i++) {
      if (signs[i] != majority) continue;
      xs[kept] = xs[i];
      ys[kept] = ys[i];
      kept++;
    }
    support[k] = kept / _samplesPerSide;

    final fitted = kept >= _samplesPerSide * 0.4
        ? _fitLine(xs, ys, kept)
        : null;
    if (fitted == null) {
      lines[4 * k] = ax;
      lines[4 * k + 1] = ay;
      lines[4 * k + 2] = ux;
      lines[4 * k + 3] = uy;
    } else {
      lines.setRange(4 * k, 4 * k + 4, fitted);
    }
  }

  final corners = Float64List(8);
  final maxMove = 4.0 * range + 4;
  for (var k = 0; k < 4; k++) {
    final p = (k + 3) % 4;
    final corner = intersectLines(
      lines[4 * p],
      lines[4 * p + 1],
      lines[4 * p + 2],
      lines[4 * p + 3],
      lines[4 * k],
      lines[4 * k + 1],
      lines[4 * k + 2],
      lines[4 * k + 3],
    );
    if (corner == null) return null;
    final dx = corner.x - quad[2 * k];
    final dy = corner.y - quad[2 * k + 1];
    // A corner flying away means two nearly parallel fitted sides: keep the
    // starting corner rather than trusting an ill-conditioned intersection.
    final moved = dx * dx + dy * dy <= maxMove * maxMove;
    corners[2 * k] = moved ? corner.x : quad[2 * k];
    corners[2 * k + 1] = moved ? corner.y : quad[2 * k + 1];
  }
  return SnappedQuad(corners, support);
}

/// Total least squares line through the first [count] points, refitted once
/// without the points further than 1.5 px from the first fit. Returns
/// `[x, y, dx, dy]` (a point and a unit direction).
Float64List? _fitLine(Float64List xs, Float64List ys, int count) {
  Float64List? fit(bool Function(int index) use) {
    var n = 0;
    var mx = 0.0;
    var my = 0.0;
    for (var i = 0; i < count; i++) {
      if (!use(i)) continue;
      mx += xs[i];
      my += ys[i];
      n++;
    }
    if (n < 6) return null;
    mx /= n;
    my /= n;
    var sxx = 0.0;
    var sxy = 0.0;
    var syy = 0.0;
    for (var i = 0; i < count; i++) {
      if (!use(i)) continue;
      final dx = xs[i] - mx;
      final dy = ys[i] - my;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    final theta = 0.5 * math.atan2(2 * sxy, sxx - syy);
    return Float64List.fromList([mx, my, math.cos(theta), math.sin(theta)]);
  }

  final first = fit((_) => true);
  if (first == null) return null;
  bool isInlier(int i) {
    final distance =
        (xs[i] - first[0]) * -first[3] + (ys[i] - first[1]) * first[2];
    return distance.abs() <= 1.5;
  }

  var inliers = 0;
  for (var i = 0; i < count; i++) {
    if (isInlier(i)) inliers++;
  }
  if (inliers < count * 0.6) return first;
  return fit(isInlier) ?? first;
}
