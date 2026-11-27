import 'dart:math' as math;
import 'dart:typed_data';

/// Separable box blur of a grey plane, edges replicated.
Uint8List boxBlur(Uint8List src, int width, int height, int radius) {
  final tmp = Uint8List(src.length);
  final out = Uint8List(src.length);
  final window = 2 * radius + 1;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var acc = 0;
    for (var k = -radius; k <= radius; k++) {
      acc += src[row + k.clamp(0, width - 1)];
    }
    for (var x = 0; x < width; x++) {
      tmp[row + x] = acc ~/ window;
      acc +=
          src[row + math.min(x + radius + 1, width - 1)] -
          src[row + math.max(x - radius, 0)];
    }
  }
  for (var x = 0; x < width; x++) {
    var acc = 0;
    for (var k = -radius; k <= radius; k++) {
      acc += tmp[k.clamp(0, height - 1) * width + x];
    }
    for (var y = 0; y < height; y++) {
      out[y * width + x] = acc ~/ window;
      acc +=
          tmp[math.min(y + radius + 1, height - 1) * width + x] -
          tmp[math.max(y - radius, 0) * width + x];
    }
  }
  return out;
}

/// Otsu's threshold: the level that best splits [histogram] in two classes.
/// Values `<=` the result belong to the low class.
int otsuThreshold(Int32List histogram, int total) {
  var sum = 0;
  for (var i = 0; i < histogram.length; i++) {
    sum += i * histogram[i];
  }
  var sumLow = 0;
  var countLow = 0;
  var best = 0;
  var bestVariance = -1.0;
  for (var t = 0; t < histogram.length; t++) {
    countLow += histogram[t];
    if (countLow == 0) continue;
    final countHigh = total - countLow;
    if (countHigh == 0) break;
    sumLow += t * histogram[t];
    final gap = sumLow / countLow - (sum - sumLow) / countHigh;
    final variance = countLow * countHigh * gap * gap;
    if (variance > bestVariance) {
      bestVariance = variance;
      best = t;
    }
  }
  return best;
}

/// Finds the largest solid region delimited by [barrier] (non-zero = wall)
/// and returns the four corners of its outline, clockwise from the top-left
/// one, as `[x0, y0, ... x3, y3]` in pixel-centre coordinates.
///
/// "Region" means everything the image border cannot reach without crossing
/// a wall: the walls themselves and whatever they enclose (text, pictures).
/// The region is eroded by [erosion] pixels before its largest connected
/// part is kept, which detaches thin structures touching the document (a
/// table edge, a cable, a shadow line); the erosion is then compensated
/// analytically on each side.
///
/// Returns null when no region reaches [minPixels] pixels.
Float64List? largestRegionCorners(
  Uint8List barrier,
  int width,
  int height, {
  required int erosion,
  required int minPixels,
}) {
  final n = width * height;
  final stack = Int32List(n);
  var sp = 0;

  // 1. Flood the outside from the image border through non-wall pixels.
  final state = Uint8List(n); // 1 = outside
  void seed(int i) {
    if (barrier[i] == 0 && state[i] == 0) {
      state[i] = 1;
      stack[sp++] = i;
    }
  }

  for (var x = 0; x < width; x++) {
    seed(x);
    seed(n - width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }
  while (sp > 0) {
    final i = stack[--sp];
    final x = i % width;
    if (x > 0) seed(i - 1);
    if (x < width - 1) seed(i + 1);
    if (i >= width) seed(i - width);
    if (i < n - width) seed(i + width);
  }

  // 2. Erode the inside with a square window (summed-area table).
  final iw = width + 1;
  final integral = Int32List(iw * (height + 1));
  for (var y = 0; y < height; y++) {
    var rowSum = 0;
    for (var x = 0; x < width; x++) {
      if (state[y * width + x] == 0) rowSum++;
      integral[(y + 1) * iw + x + 1] = integral[y * iw + x + 1] + rowSum;
    }
  }
  // From here on: 2 = eroded inside, 3 = visited, 4 = kept component.
  var erodedCount = 0;
  for (var y = 0; y < height; y++) {
    final y0 = math.max(0, y - erosion);
    final y1 = math.min(height - 1, y + erosion) + 1;
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (state[i] != 0) continue;
      final x0 = math.max(0, x - erosion);
      final x1 = math.min(width - 1, x + erosion) + 1;
      final sum =
          integral[y1 * iw + x1] -
          integral[y0 * iw + x1] -
          integral[y1 * iw + x0] +
          integral[y0 * iw + x0];
      if (sum == (x1 - x0) * (y1 - y0)) {
        state[i] = 2;
        erodedCount++;
      }
    }
  }
  if (erodedCount < minPixels) return null;

  // 3. Largest 4-connected component of the eroded inside.
  int flood(int start, int from, int to) {
    var size = 0;
    sp = 0;
    state[start] = to;
    stack[sp++] = start;
    while (sp > 0) {
      final i = stack[--sp];
      size++;
      final x = i % width;
      if (x > 0 && state[i - 1] == from) {
        state[i - 1] = to;
        stack[sp++] = i - 1;
      }
      if (x < width - 1 && state[i + 1] == from) {
        state[i + 1] = to;
        stack[sp++] = i + 1;
      }
      if (i >= width && state[i - width] == from) {
        state[i - width] = to;
        stack[sp++] = i - width;
      }
      if (i < n - width && state[i + width] == from) {
        state[i + width] = to;
        stack[sp++] = i + width;
      }
    }
    return size;
  }

  var bestStart = -1;
  var bestSize = 0;
  for (var i = 0; i < n; i++) {
    if (state[i] != 2) continue;
    final size = flood(i, 2, 3);
    if (size > bestSize) {
      bestSize = size;
      bestStart = i;
    }
  }
  if (bestSize < minPixels) return null;
  flood(bestStart, 3, 4);

  // 4. Outline samples: extreme pixels of every row and every column.
  final points = <math.Point<double>>[];
  for (var y = 0; y < height; y++) {
    var first = -1;
    var last = -1;
    final row = y * width;
    for (var x = 0; x < width; x++) {
      if (state[row + x] == 4) {
        if (first < 0) first = x;
        last = x;
      }
    }
    if (first >= 0) {
      points.add(math.Point(first.toDouble(), y.toDouble()));
      if (last != first) points.add(math.Point(last.toDouble(), y.toDouble()));
    }
  }
  for (var x = 0; x < width; x++) {
    var first = -1;
    var last = -1;
    for (var y = 0; y < height; y++) {
      if (state[y * width + x] == 4) {
        if (first < 0) first = y;
        last = y;
      }
    }
    if (first >= 0) {
      points.add(math.Point(x.toDouble(), first.toDouble()));
      if (last != first) points.add(math.Point(x.toDouble(), last.toDouble()));
    }
  }

  final hull = convexHull(points);
  if (hull.length < 4) return null;
  final quad = orderClockwise(reduceToQuad(hull));
  return _pushSidesOutward(quad, erosion.toDouble());
}

/// Andrew's monotone chain. Returns the hull without repeated end point.
List<math.Point<double>> convexHull(List<math.Point<double>> input) {
  final pts = List<math.Point<double>>.of(input)
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (pts.length < 3) return pts;
  double cross(
    math.Point<double> o,
    math.Point<double> a,
    math.Point<double> b,
  ) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  final lower = <math.Point<double>>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <math.Point<double>>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

/// Reduces a convex polygon to four vertices by repeatedly dropping the
/// vertex whose removal loses the least area (rounded corners and pixel
/// staircase go first, the real corners stay).
List<math.Point<double>> reduceToQuad(List<math.Point<double>> hull) {
  final poly = List<math.Point<double>>.of(hull);
  while (poly.length > 4) {
    var index = 0;
    var smallest = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final p = poly[(i - 1 + poly.length) % poly.length];
      final q = poly[i];
      final r = poly[(i + 1) % poly.length];
      final area = ((q.x - p.x) * (r.y - p.y) - (r.x - p.x) * (q.y - p.y))
          .abs();
      if (area < smallest) {
        smallest = area;
        index = i;
      }
    }
    poly.removeAt(index);
  }
  return poly;
}

/// Orders four points clockwise (as seen on screen) starting from the one
/// closest to the top-left, and flattens them to `[x0, y0, ... x3, y3]`.
Float64List orderClockwise(List<math.Point<double>> quad) {
  var cx = 0.0;
  var cy = 0.0;
  for (final p in quad) {
    cx += p.x / quad.length;
    cy += p.y / quad.length;
  }
  final sorted = List<math.Point<double>>.of(quad)
    ..sort(
      (a, b) => math
          .atan2(a.y - cy, a.x - cx)
          .compareTo(math.atan2(b.y - cy, b.x - cx)),
    );
  var start = 0;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) {
      start = i;
    }
  }
  final out = Float64List(8);
  for (var i = 0; i < 4; i++) {
    final p = sorted[(start + i) % 4];
    out[2 * i] = p.x;
    out[2 * i + 1] = p.y;
  }
  return out;
}

/// Intersection of the line through `(px, py)` directed by `(dx, dy)` with
/// the line through `(qx, qy)` directed by `(ex, ey)`; null when parallel.
math.Point<double>? intersectLines(
  double px,
  double py,
  double dx,
  double dy,
  double qx,
  double qy,
  double ex,
  double ey,
) {
  final det = dx * ey - dy * ex;
  if (det.abs() < 1e-9) return null;
  final s = ((qx - px) * ey - (qy - py) * ex) / det;
  return math.Point(px + s * dx, py + s * dy);
}

/// Undoes a square erosion of half-size [radius] on a clockwise quad: each
/// side moved inward by `radius * (|nx| + |ny|)`, n being its unit normal.
Float64List? _pushSidesOutward(Float64List quad, double radius) {
  final lines = Float64List(16);
  for (var k = 0; k < 4; k++) {
    final ax = quad[2 * k];
    final ay = quad[2 * k + 1];
    final bx = quad[2 * ((k + 1) % 4)];
    final by = quad[2 * ((k + 1) % 4) + 1];
    final length = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    if (length < 1e-6) return null;
    final ux = (bx - ax) / length;
    final uy = (by - ay) / length;
    // Outward normal of a clockwise polygon in image coordinates.
    final nx = uy;
    final ny = -ux;
    final shift = radius * (nx.abs() + ny.abs());
    lines[4 * k] = ax + nx * shift;
    lines[4 * k + 1] = ay + ny * shift;
    lines[4 * k + 2] = ux;
    lines[4 * k + 3] = uy;
  }
  final out = Float64List(8);
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
    out[2 * k] = corner.x;
    out[2 * k + 1] = corner.y;
  }
  return out;
}
