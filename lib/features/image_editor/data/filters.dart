import 'dart:math' as math;
import 'dart:typed_data';

import 'package:md_scanner/features/image_editor/data/raster.dart';

/// Tone curve of the brightness and contrast sliders (both -1..1).
///
/// Contrast is a gain around mid-grey, exponential so that the slider feels
/// symmetric (x3 at +1, x1/3 at -1); brightness is a plain offset.
Uint8List toneLut(double brightness, double contrast) {
  final gain = math.pow(2, 1.6 * contrast).toDouble();
  final offset = brightness * 96;
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = _byte((v - 128) * gain + 128 + offset);
  }
  return lut;
}

int _byte(num value) => value.round().clamp(0, 255).toInt();

/// Applies the manual sliders in place. Saturation scales the distance of
/// each channel to the pixel's luma in 8-bit fixed point (no HSV round trip)
/// and is ignored on grey rasters.
void applyAdjustments(
  Raster raster, {
  required double brightness,
  required double contrast,
  required double saturation,
}) {
  final hasTone = brightness != 0 || contrast != 0;
  final hasSaturation = saturation != 0 && !raster.isGray;
  if (!hasTone && !hasSaturation) return;
  final lut = toneLut(brightness, contrast);
  final data = raster.data;
  if (!hasSaturation) {
    for (var i = 0; i < data.length; i++) {
      data[i] = lut[data[i]];
    }
    return;
  }
  _saturate(data, ((1 + saturation) * 256).round(), lut, lut, lut);
}

/// `out = lut[luma + (channel - luma) * factor]` on interleaved RGB, with
/// [factor] in 8.8 fixed point (256 = unchanged).
void _saturate(
  Uint8List data,
  int factor,
  Uint8List lutR,
  Uint8List lutG,
  Uint8List lutB,
) {
  for (var i = 0; i < data.length; i += 3) {
    final r = data[i];
    final g = data[i + 1];
    final b = data[i + 2];
    final l = (r * 77 + g * 150 + b * 29) >> 8;
    var r2 = l + (((r - l) * factor) >> 8);
    var g2 = l + (((g - l) * factor) >> 8);
    var b2 = l + (((b - l) * factor) >> 8);
    if (r2 < 0) {
      r2 = 0;
    } else if (r2 > 255) {
      r2 = 255;
    }
    if (g2 < 0) {
      g2 = 0;
    } else if (g2 > 255) {
      g2 = 255;
    }
    if (b2 < 0) {
      b2 = 0;
    } else if (b2 > 255) {
      b2 = 255;
    }
    data[i] = lutR[r2];
    data[i + 1] = lutG[g2];
    data[i + 2] = lutB[b2];
  }
}

/// Level below which [fraction] of the [total] samples of [histogram] lie.
int percentile(Int32List histogram, int total, double fraction) {
  final target = (total * fraction).floor();
  var seen = 0;
  for (var v = 0; v < histogram.length; v++) {
    seen += histogram[v];
    if (seen > target) return v;
  }
  return histogram.length - 1;
}

/// Linear stretch of `[low, high]` to the full range. The interval is
/// widened to at least [minRange] so that a flat image is not blown up into
/// noise.
Uint8List levelsLut(int low, int high, {int minRange = 96}) {
  var lo = low.toDouble();
  var hi = high.toDouble();
  if (hi - lo < minRange) {
    final mid = (hi + lo) / 2;
    lo = math.max(0.0, mid - minRange / 2);
    hi = math.min(255.0, lo + minRange);
    lo = hi - minRange;
  }
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    lut[v] = _byte((v - lo) * 255 / (hi - lo));
  }
  return lut;
}

/// Neutral grey rendition: luma, then a gentle stretch so that paper reads
/// as light and ink as dark whatever the exposure.
Raster grayscale(Raster rgb) {
  final gray = luminanceOf(rgb);
  final data = gray.data;
  final histogram = Int32List(256);
  for (var i = 0; i < data.length; i++) {
    histogram[data[i]]++;
  }
  final lut = levelsLut(
    percentile(histogram, data.length, 0.005),
    percentile(histogram, data.length, 0.995),
    minRange: 128,
  );
  for (var i = 0; i < data.length; i++) {
    data[i] = lut[data[i]];
  }
  return gray;
}

/// Colour auto-enhance, in place: black and white points from the
/// histogram, a bounded white balance, an S-curve and a saturation lift.
///
/// The white point is taken per channel so a warm or cold cast on the paper
/// is neutralized, but each channel may only move 12 % away from the luma
/// white point: an image dominated by one colour keeps that colour.
/// [strength] (0..1) sets the amount of contrast and saturation.
void enhanceColor(Raster rgb, double strength) {
  assert(rgb.channels == 3);
  final data = rgb.data;
  final hr = Int32List(256);
  final hg = Int32List(256);
  final hb = Int32List(256);
  final hl = Int32List(256);
  for (var i = 0; i < data.length; i += 3) {
    final r = data[i];
    final g = data[i + 1];
    final b = data[i + 2];
    hr[r]++;
    hg[g]++;
    hb[b]++;
    hl[(r * 77 + g * 150 + b * 29) >> 8]++;
  }
  final total = data.length ~/ 3;
  // Bounded so that an image without real blacks or whites (a pale card, a
  // night shot) is not stretched into something it never was.
  final black = math.min(percentile(hl, total, 0.005), 90);
  final white = math.max(percentile(hl, total, 0.99), 140);
  final curve = 0.10 + 0.20 * strength;

  Uint8List channelLut(Int32List histogram) {
    final own = percentile(histogram, total, 0.99);
    final top = own
        .clamp(white * 0.88, white * 1.12)
        .clamp(black + 64, 255)
        .toDouble();
    final lut = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      final x = ((v - black) / (top - black)).clamp(0.0, 1.0).toDouble();
      final y = x - curve * math.sin(2 * math.pi * x) / (2 * math.pi);
      lut[v] = _byte(y * 255);
    }
    return lut;
  }

  final lutR = channelLut(hr);
  final lutG = channelLut(hg);
  final lutB = channelLut(hb);
  for (var i = 0; i < data.length; i += 3) {
    data[i] = lutR[data[i]];
    data[i + 1] = lutG[data[i + 1]];
    data[i + 2] = lutB[data[i + 2]];
  }
  final identity = Uint8List.fromList(List<int>.generate(256, (v) => v));
  final factor = ((1.10 + 0.25 * strength) * 256).round();
  _saturate(data, factor, identity, identity, identity);
}

/// Black ink on white paper: every pixel becomes 0 or 255.
///
/// Bradley's adaptive threshold on a summed-area table: a pixel is ink when
/// it is darker than the mean of its neighbourhood by more than a tolerance,
/// which follows uneven lighting where a global threshold cannot. A second,
/// four times wider neighbourhood with a much larger tolerance fills the
/// inside of shapes larger than the first window (logos, thick headings),
/// which a single-scale threshold leaves hollow.
///
/// [strength] (0..1) lowers the tolerance: more of the faint print of a
/// thermal receipt is kept. [bias] (-1..1, the brightness slider) moves it
/// the other way: positive values thin the strokes and drop specks.
Raster adaptiveThreshold(
  Raster gray, {
  required double strength,
  double bias = 0,
}) {
  assert(gray.isGray);
  final w = gray.width;
  final h = gray.height;
  final g = gray.data;
  final iw = w + 1;
  // 32-bit sums wrap on very large pages; differences stay exact as long as
  // a window sum fits in 32 bits, which the masks below rely on.
  final integral = Uint32List(iw * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    final row = y * w;
    final above = y * iw;
    final here = above + iw;
    for (var x = 0; x < w; x++) {
      rowSum += g[row + x];
      integral[here + x + 1] = integral[above + x + 1] + rowSum;
    }
  }

  final r1 = math.max(4, math.min(w, h) ~/ 28);
  final r2 = 4 * r1;
  final tolerance = (0.16 - 0.07 * strength + 0.10 * bias)
      .clamp(0.02, 0.30)
      .toDouble();
  final k1 = ((1 - tolerance) * 1024).round();
  final k2 = ((1 - 0.45) * 1024).round();

  final left1 = Int32List(w);
  final right1 = Int32List(w);
  final left2 = Int32List(w);
  final right2 = Int32List(w);
  for (var x = 0; x < w; x++) {
    left1[x] = math.max(0, x - r1);
    right1[x] = math.min(w - 1, x + r1) + 1;
    left2[x] = math.max(0, x - r2);
    right2[x] = math.min(w - 1, x + r2) + 1;
  }

  final out = Raster.gray(w, h);
  final o = out.data;
  for (var y = 0; y < h; y++) {
    final top1 = math.max(0, y - r1);
    final bottom1 = math.min(h - 1, y + r1) + 1;
    final top2 = math.max(0, y - r2);
    final bottom2 = math.min(h - 1, y + r2) + 1;
    final rows1 = bottom1 - top1;
    final rows2 = bottom2 - top2;
    final t1 = top1 * iw;
    final b1 = bottom1 * iw;
    final t2 = top2 * iw;
    final b2 = bottom2 * iw;
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final v = g[row + x];
      final xa = left1[x];
      final xb = right1[x];
      final sum1 =
          (integral[b1 + xb] -
              integral[t1 + xb] -
              integral[b1 + xa] +
              integral[t1 + xa]) &
          0xFFFFFFFF;
      var ink = v * (xb - xa) * rows1 * 1024 < sum1 * k1;
      if (!ink) {
        final xc = left2[x];
        final xd = right2[x];
        final sum2 =
            (integral[b2 + xd] -
                integral[t2 + xd] -
                integral[b2 + xc] +
                integral[t2 + xc]) &
            0xFFFFFFFF;
        ink = v * (xd - xc) * rows2 * 1024 < sum2 * k2;
      }
      o[row + x] = ink ? 0 : 255;
    }
  }
  return out;
}
