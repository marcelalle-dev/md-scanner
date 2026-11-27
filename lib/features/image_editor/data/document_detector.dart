import 'dart:math' as math;
import 'dart:typed_data';

import 'package:md_scanner/features/image_editor/data/edge_snapping.dart';
import 'package:md_scanner/features/image_editor/data/outline_geometry.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

/// Detection runs on a reduced image whose long edge is within these bounds:
/// large enough to place corners within a fraction of a percent, small
/// enough to take a few tens of milliseconds. All pixel constants below
/// assume this scale.
const int detectionMinLongEdge = 400;
const int detectionMaxLongEdge = 640;

/// Images whose short side is below this carry too little structure to tell
/// a page outline from noise.
const int _minSide = 64;

const int _blurRadius = 2;
const int _erosion = 3;

/// Weakest Sobel response ("Sobel / 4" units) treated as an edge when
/// building closed contours: about 25 grey levels of contrast across the
/// blurred border of a page.
const int _minEdgeLevel = 10;

/// Weakest response that counts when measuring the support of a side.
const double _minSupportLevel = 8;

/// Search ranges, in pixels, of the two edge-snapping passes: the first
/// absorbs the bias of the region outline, the second measures support
/// tightly around the final position.
const int _coarseRange = 6;
const int _fineRange = 2;

const double _minPerimeterSupport = 0.6;
const double _minSideSupport = 0.35;
const double _minCornerAngle = 35;
const double _maxCornerAngle = 145;

/// Looks for the outline of a document in [gray] (a reduced, upright grey
/// image) and returns it in normalized coordinates, or null when nothing
/// qualifies.
///
/// Three independent readings of the scene each propose at most one region:
/// what is enclosed by strong edges, what is lighter than the rest, what is
/// darker than the rest. Each region is turned into a quad, snapped onto the
/// actual edges, then kept only if its geometry is plausible for [hints] and
/// its sides are supported by edges (see `ImageProcessor.detectDocument` for
/// the exact rule). The best survivor wins; without survivor the answer is
/// null: no fallback quad is ever invented.
Quad? detectDocumentQuad(Raster gray, ProcessingHints hints) {
  assert(gray.isGray);
  final w = gray.width;
  final h = gray.height;
  if (w < _minSide || h < _minSide) return null;
  final n = w * h;
  final blurred = boxBlur(gray.data, w, h, _blurRadius);

  final gx = Int16List(n);
  final gy = Int16List(n);
  final magnitude = Uint8List(n);
  final magnitudeHistogram = Int32List(256);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final nw = blurred[i - w - 1];
      final ne = blurred[i - w + 1];
      final sw = blurred[i + w - 1];
      final se = blurred[i + w + 1];
      final sx =
          (ne + 2 * blurred[i + 1] + se) - (nw + 2 * blurred[i - 1] + sw);
      final sy =
          (sw + 2 * blurred[i + w] + se) - (nw + 2 * blurred[i - w] + ne);
      gx[i] = sx;
      gy[i] = sy;
      var m = (sx.abs() + sy.abs()) >> 2;
      if (m > 255) m = 255;
      magnitude[i] = m;
      magnitudeHistogram[m]++;
    }
  }
  final edgeLevel = math.max(
    _minEdgeLevel,
    otsuThreshold(magnitudeHistogram, (w - 2) * (h - 2)),
  );
  final field = GradientField(
    w,
    h,
    gx,
    gy,
    math.max(_minSupportLevel, edgeLevel / 2),
  );

  // Walls 1: strong edges, thickened by one pixel to close small gaps.
  final edges = Uint8List(n);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (magnitude[i] >= edgeLevel) {
        edges[i] = 1;
        edges[i - 1] = 1;
        edges[i + 1] = 1;
        edges[i - w] = 1;
        edges[i + w] = 1;
      }
    }
  }
  // Walls 2 and 3: the light and the dark class of the scene.
  final grayHistogram = Int32List(256);
  for (var i = 0; i < n; i++) {
    grayHistogram[blurred[i]]++;
  }
  final split = otsuThreshold(grayHistogram, n);
  final light = Uint8List(n);
  final dark = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (blurred[i] > split) {
      light[i] = 1;
    } else {
      dark[i] = 1;
    }
  }

  // Erosion eats a border of the region: pre-filter with a lower bar, the
  // exact area test comes after snapping.
  final minPixels = (hints.minAreaFraction * n * 0.6).floor();
  _Candidate? best;
  for (final walls in [edges, light, dark]) {
    final outline = largestRegionCorners(
      walls,
      w,
      h,
      erosion: _erosion,
      minPixels: minPixels,
    );
    if (outline == null) continue;
    final candidate = _evaluate(outline, field, hints);
    if (candidate != null && (best == null || candidate.score > best.score)) {
      best = candidate;
    }
  }
  if (best == null) return null;

  // Pixel centres are at +0.5 in the continuous image.
  NormalizedPoint corner(int k) => NormalizedPoint(
    ((best!.corners[2 * k] + 0.5) / w).clamp(0.0, 1.0).toDouble(),
    ((best.corners[2 * k + 1] + 0.5) / h).clamp(0.0, 1.0).toDouble(),
  );
  final quad = Quad(
    topLeft: corner(0),
    topRight: corner(1),
    bottomRight: corner(2),
    bottomLeft: corner(3),
  );
  return quad.isConvex ? quad : null;
}

final class _Candidate {
  const _Candidate(this.corners, this.score);

  final Float64List corners;

  /// Area weighted by edge support: among confident outlines the outermost
  /// one is the document, inner ones are tables or pictures printed on it.
  final double score;
}

_Candidate? _evaluate(
  Float64List outline,
  GradientField field,
  ProcessingHints hints,
) {
  final coarse = snapToEdges(outline, field, _coarseRange);
  if (coarse == null) return null;
  final fine = snapToEdges(coarse.corners, field, _fineRange);
  if (fine == null) return null;
  final c = fine.corners;
  final w = field.width;
  final h = field.height;

  // Corners must be in the frame; a hair outside is rounding, not a page
  // leaving the picture.
  final slack = 0.02 * math.max(w, h);
  for (var k = 0; k < 4; k++) {
    final x = c[2 * k];
    final y = c[2 * k + 1];
    if (x < -slack || y < -slack || x > w - 1 + slack || y > h - 1 + slack) {
      return null;
    }
  }

  final lengths = Float64List(4);
  var doubleArea = 0.0;
  for (var k = 0; k < 4; k++) {
    final ax = c[2 * k];
    final ay = c[2 * k + 1];
    final bx = c[2 * ((k + 1) % 4)];
    final by = c[2 * ((k + 1) % 4) + 1];
    final cx = c[2 * ((k + 2) % 4)];
    final cy = c[2 * ((k + 2) % 4) + 1];
    final ux = bx - ax;
    final uy = by - ay;
    final vx = cx - bx;
    final vy = cy - by;
    final cross = ux * vy - uy * vx;
    if (cross <= 0) return null; // not convex, or not clockwise
    final lu = math.sqrt(ux * ux + uy * uy);
    final lv = math.sqrt(vx * vx + vy * vy);
    if (lu < 1 || lv < 1) return null;
    final cosine = (-(ux * vx + uy * vy) / (lu * lv)).clamp(-1.0, 1.0);
    final angle = math.acos(cosine) * 180 / math.pi;
    if (angle < _minCornerAngle || angle > _maxCornerAngle) return null;
    lengths[k] = lu;
    doubleArea += ax * by - bx * ay;
  }
  final area = doubleArea.abs() / 2;
  if (area < hints.minAreaFraction * w * h) return null;

  final across = (lengths[0] + lengths[2]) / 2;
  final down = (lengths[1] + lengths[3]) / 2;
  final elongation = math.max(across, down) / math.min(across, down);
  if (elongation > hints.maxElongation) return null;

  var perimeter = 0.0;
  var supported = 0.0;
  for (var k = 0; k < 4; k++) {
    if (fine.support[k] < _minSideSupport) return null;
    perimeter += lengths[k];
    supported += lengths[k] * fine.support[k];
  }
  final support = supported / perimeter;
  if (support < _minPerimeterSupport) return null;
  return _Candidate(c, area * support);
}
