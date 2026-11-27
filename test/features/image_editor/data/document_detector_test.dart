import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/features/image_editor/data/document_detector.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

import '../support/synthetic.dart';

const int _w = 520;
const int _h = 390;

/// Largest corner error of [quad], as a percentage of the image diagonal.
double _worstError(Quad quad, Projection truth, int width, int height) {
  final expected = truth.corners;
  final found = quad.corners;
  var worst = 0.0;
  for (var i = 0; i < 4; i++) {
    final dx = found[i].x * width - expected[i].x;
    final dy = found[i].y * height - expected[i].y;
    worst = math.max(worst, math.sqrt(dx * dx + dy * dy));
  }
  return 100 * worst / math.sqrt(width * width + height * height);
}

Quad? _detect(Raster scene, [ScanMode mode = ScanMode.document]) =>
    detectDocumentQuad(luminanceOf(scene), mode.preset.hints);

void main() {
  final tilted = Projection.tilted.scaled(_w / 1000, _h / 750);

  group('finds the page', () {
    test('light page with dark stripes on a darker textured table', () {
      final quad = _detect(
        drawScene(width: _w, height: _h, projection: tilted),
      );
      expect(quad, isNotNull);
      final error = _worstError(quad!, tilted, _w, _h);
      // Product requirement: 3 % of the diagonal. The detector snaps sides
      // onto the edges with sub-pixel accuracy, so hold it to much better.
      expect(error, lessThanOrEqualTo(3));
      expect(error, lessThan(0.5));
      expect(quad.isConvex, isTrue);
      expect(quad.clamped(), quad);
      expect(quad.area, closeTo(tilted.quadIn(_w, _h).area, 0.01));
    });

    test('whatever the grain of the table', () {
      for (final noise in [0, 45, 70]) {
        final quad = _detect(
          drawScene(width: _w, height: _h, projection: tilted, noise: noise),
        );
        expect(quad, isNotNull, reason: 'noise $noise');
        expect(
          _worstError(quad!, tilted, _w, _h),
          lessThan(0.5),
          reason: 'noise $noise',
        );
      }
    });

    test('despite a bright line crossing the table behind it', () {
      final scene = drawScene(width: _w, height: _h, projection: tilted);
      for (var x = 0; x < _w; x++) {
        final y = (0.55 * _h + 0.05 * x).round();
        final p = tilted.toPage(x + 0.5, y + 0.5);
        if (p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1) continue;
        for (var t = 0; t < 2; t++) {
          final i = ((y + t) * _w + x) * 3;
          scene.data.fillRange(i, i + 3, 228);
        }
      }
      final quad = _detect(scene);
      expect(quad, isNotNull);
      expect(_worstError(quad!, tilted, _w, _h), lessThan(0.5));
    });

    test('under a soft shadow', () {
      final scene = drawScene(width: _w, height: _h, projection: tilted);
      castShadow(scene, dark: 0.5);
      final quad = _detect(scene);
      expect(quad, isNotNull);
      expect(_worstError(quad!, tilted, _w, _h), lessThan(0.5));
    });

    test('when it is only slightly lighter than the table', () {
      final quad = _detect(
        drawScene(
          width: _w,
          height: _h,
          projection: tilted,
          page: (u, v) => 0x848078,
        ),
      );
      expect(quad, isNotNull);
      expect(_worstError(quad!, tilted, _w, _h), lessThan(0.5));
    });

    test('when it is darker than the table', () {
      final scene = drawScene(width: _w, height: _h, projection: tilted);
      for (var i = 0; i < scene.data.length; i++) {
        scene.data[i] = 255 - scene.data[i];
      }
      final quad = _detect(scene);
      expect(quad, isNotNull);
      expect(_worstError(quad!, tilted, _w, _h), lessThan(0.5));
    });

    test('rotated by 40 degrees', () {
      final c = math.cos(40 * math.pi / 180);
      final s = math.sin(40 * math.pi / 180);
      final rotated = Projection(
        260 * c,
        -200 * s,
        240,
        260 * s,
        200 * c,
        30,
        0,
        0,
      );
      final quad = _detect(
        drawScene(width: _w, height: _h, projection: rotated),
      );
      expect(quad, isNotNull);
      expect(_worstError(quad!, rotated, _w, _h), lessThan(0.5));
    });

    test('and prefers the page to a frame printed on it', () {
      int framed(double u, double v) {
        final outer = u > 0.15 && u < 0.85 && v > 0.2 && v < 0.8;
        final inner = u > 0.17 && u < 0.83 && v > 0.22 && v < 0.78;
        return outer && !inner ? inkColor : paperColor;
      }

      final quad = _detect(
        drawScene(width: _w, height: _h, projection: tilted, page: framed),
      );
      expect(quad, isNotNull);
      expect(_worstError(quad!, tilted, _w, _h), lessThan(0.5));
    });
  });

  group('capture mode changes what is accepted', () {
    // A narrow strip covering about 12 % of the frame.
    final strip = const Projection(
      170,
      10,
      420,
      -8,
      640,
      50,
      0.02,
      0.05,
    ).scaled(_w / 1000, _h / 750);

    test('a receipt is too small for a document, fine for a receipt', () {
      final scene = drawScene(width: _w, height: _h, projection: strip);
      expect(strip.quadIn(_w, _h).area, lessThan(0.2));
      expect(_detect(scene), isNull);
      final quad = _detect(scene, ScanMode.receipt);
      expect(quad, isNotNull);
      expect(_worstError(quad!, strip, _w, _h), lessThan(0.5));
    });

    test('a strip that long is not an identity card', () {
      final scene = drawScene(width: _w, height: _h, projection: strip);
      expect(_detect(scene, ScanMode.idCard), isNull);
    });
  });

  group('never invents a quad', () {
    test('flat noise yields null at every amplitude and in every mode', () {
      for (final range in [(0, 255), (60, 200), (100, 140), (127, 129)]) {
        final noise = drawNoise(_w, _h, low: range.$1, high: range.$2);
        for (final mode in ScanMode.values) {
          expect(_detect(noise, mode), isNull, reason: '$range $mode');
        }
      }
    });

    test('a uniform image yields null', () {
      final blank = Raster.rgb(_w, _h)..data.fillRange(0, _w * _h * 3, 180);
      expect(_detect(blank), isNull);
    });

    test('a page filling the frame has no visible outline', () {
      expect(_detect(drawFlatPage(_w, _h)), isNull);
    });

    test('a page leaving the frame on one side yields null', () {
      const leaving = Projection(360, 20, 230, -20, 330, 30, 0.05, 0.07);
      expect(leaving.corners[1].x, greaterThan(_w));
      expect(
        _detect(drawScene(width: _w, height: _h, projection: leaving)),
        isNull,
      );
    });

    test('smooth clouds and random clutter yield null', () {
      final random = math.Random(5);
      const gridW = 14;
      const gridH = 11;
      final grid = List.generate(gridW * gridH, (_) => random.nextInt(256));
      final clouds = Raster.rgb(_w, _h);
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          final gx = x / _w * (gridW - 1);
          final gy = y / _h * (gridH - 1);
          final x0 = math.min(gx.floor(), gridW - 2);
          final y0 = math.min(gy.floor(), gridH - 2);
          final tx = gx - x0;
          final ty = gy - y0;
          final v =
              grid[y0 * gridW + x0] * (1 - tx) * (1 - ty) +
              grid[y0 * gridW + x0 + 1] * tx * (1 - ty) +
              grid[(y0 + 1) * gridW + x0] * (1 - tx) * ty +
              grid[(y0 + 1) * gridW + x0 + 1] * tx * ty;
          final i = (y * _w + x) * 3;
          clouds.data.fillRange(i, i + 3, v.round());
        }
      }
      final clutter = drawNoise(_w, _h, low: 90, high: 120);
      for (var k = 0; k < 25; k++) {
        final rx = random.nextInt(_w - 60);
        final ry = random.nextInt(_h - 60);
        final rw = 20 + random.nextInt(40);
        final rh = 20 + random.nextInt(40);
        final v = random.nextInt(256);
        for (var y = ry; y < ry + rh; y++) {
          final i = (y * _w + rx) * 3;
          clutter.data.fillRange(i, i + rw * 3, v);
        }
      }
      for (final mode in ScanMode.values) {
        expect(_detect(clouds, mode), isNull, reason: 'clouds $mode');
        expect(_detect(clutter, mode), isNull, reason: 'clutter $mode');
      }
    });

    test('an image too small to judge yields null', () {
      final tiny = drawScene(
        width: 60,
        height: 45,
        projection: Projection.tilted.scaled(0.06, 0.06),
      );
      expect(_detect(tiny), isNull);
    });
  });
}
