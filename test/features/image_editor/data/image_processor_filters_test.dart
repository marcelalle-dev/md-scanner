import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/features/image_editor/data/isolate_image_processor.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

import '../support/synthetic.dart';
import '../support/workspace.dart';

const int _w = 480;
const int _h = 360;

/// Per-image statistics computed in one pass over the decoded pixels.
class _Stats {
  _Stats(Decoded page) {
    var sum = 0.0;
    var squares = 0.0;
    var chromaSum = 0.0;
    for (var y = 0; y < page.height; y++) {
      for (var x = 0; x < page.width; x++) {
        final c = page.rgb(x, y);
        final luma = (c[0] * 77 + c[1] * 150 + c[2] * 29) / 256;
        sum += luma;
        squares += luma * luma;
        final spread = c.reduce(math.max) - c.reduce(math.min);
        chromaSum += spread;
        maxChannelSpread = math.max(maxChannelSpread, spread);
        if (c[0] == 0 && c[1] == 0 && c[2] == 0) black++;
        if (c[0] == 255 && c[1] == 255 && c[2] == 255) white++;
      }
    }
    pixels = page.width * page.height;
    meanLuma = sum / pixels;
    deviation = math.sqrt(math.max(0, squares / pixels - meanLuma * meanLuma));
    meanChroma = chromaSum / pixels;
  }

  late final int pixels;
  late final double meanLuma;
  late final double deviation;
  late final double meanChroma;
  int maxChannelSpread = 0;
  int black = 0;
  int white = 0;
}

/// Mean absolute difference of two same-sized images, in levels per channel.
double _difference(Decoded a, Decoded b) {
  expect([a.width, a.height], [b.width, b.height]);
  var sum = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final p = a.rgb(x, y);
      final q = b.rgb(x, y);
      sum += (p[0] - q[0]).abs() + (p[1] - q[1]).abs() + (p[2] - q[2]).abs();
    }
  }
  return sum / (3 * a.width * a.height);
}

/// Paper luma in the left margin minus paper luma in the right margin: the
/// strength of the shadow drawn by [castShadow] (margins hold no text).
double _shadowGradient(Decoded page) =>
    page.meanLuma(0.02, 0.1, 0.07, 0.9) - page.meanLuma(0.93, 0.1, 0.98, 0.9);

void main() {
  late Workspace work;
  late IsolateImageProcessor processor;
  late String pagePath;
  late String shadowedPath;
  late Decoded source;

  setUpAll(() async {
    work = await Workspace.create();
    processor = IsolateImageProcessor();
    pagePath = await work.write(
      'page.png',
      pngOf(drawFlatPage(_w, _h, page: markedPage)),
    );
    final shadowed = drawFlatPage(_w, _h, page: markedPage);
    castShadow(shadowed);
    shadowedPath = await work.write('shadowed.png', pngOf(shadowed));
    source = work.decode(pagePath);
  });

  tearDownAll(() => work.dispose());

  Future<Decoded> render(
    ImageAdjustments adjustments, {
    ScanMode mode = ScanMode.document,
    String? sourcePath,
    OutputFormat format = OutputFormat.png,
    int maxLongEdge = ImageRenderRequest.defaultMaxLongEdge,
  }) async {
    final result = valueOf(
      await processor.render(
        ImageRenderRequest(
          sourcePath: sourcePath ?? pagePath,
          outputPath: work.path('look.${format.extension}'),
          adjustments: adjustments,
          mode: mode,
          format: format,
          maxLongEdge: maxLongEdge,
        ),
      ),
    );
    return work.decode(result.path);
  }

  Future<Decoded> filtered(
    ScanFilter filter, {
    ScanMode mode = ScanMode.document,
    String? sourcePath,
  }) => render(
    ImageAdjustments(filter: filter),
    mode: mode,
    sourcePath: sourcePath,
  );

  test('original with neutral sliders returns the pixels untouched', () async {
    final page = await render(ImageAdjustments.none);
    expect(_difference(page, source), 0);
  });

  group('blackAndWhite', () {
    test(
      'contains only pure black and pure white, in a 1-channel PNG',
      () async {
        final page = await filtered(ScanFilter.blackAndWhite);
        final stats = _Stats(page);
        expect(stats.black + stats.white, stats.pixels);
        expect(page.channels, 1);
        // Text lines cover 35 % of 80 % x 84 % of the page.
        expect(stats.black / stats.pixels, closeTo(0.35 * 0.8 * 0.84, 0.04));
        // First text line is ink, margin and line spacing are paper.
        expect(page.rgb(_w ~/ 2, (0.09 * _h).round()), [0, 0, 0]);
        expect(page.rgb(_w ~/ 2, (0.13 * _h).round()), [255, 255, 255]);
        expect(page.rgb(10, _h ~/ 2), [255, 255, 255]);
      },
    );

    test('stays two-tone under a shadow and with every slider', () async {
      final shadowed = await filtered(
        ScanFilter.blackAndWhite,
        sourcePath: shadowedPath,
      );
      final stats = _Stats(shadowed);
      expect(stats.black + stats.white, stats.pixels);
      // The shadowed half reads as well as the lit one: a global threshold
      // would turn it solid black.
      expect(shadowed.meanLuma(0.93, 0.1, 0.98, 0.9), 255);
      expect(shadowed.rgb((0.85 * _w).round(), (0.09 * _h).round()), [0, 0, 0]);

      final tuned = _Stats(
        await render(
          const ImageAdjustments(
            filter: ScanFilter.blackAndWhite,
            brightness: 0.4,
            contrast: -0.5,
            saturation: 1,
          ),
        ),
      );
      expect(tuned.black + tuned.white, tuned.pixels);
    });

    test('brightness thins the ink', () async {
      final noisy = drawFlatPage(_w, _h);
      final random = math.Random(5);
      for (var i = 0; i < noisy.data.length; i++) {
        noisy.data[i] = (noisy.data[i] + random.nextInt(61) - 30).clamp(0, 255);
      }
      final path = await work.write('noisy.png', pngOf(noisy));
      var previous = 1 << 30;
      for (final brightness in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
        final black = _Stats(
          await render(
            ImageAdjustments(
              filter: ScanFilter.blackAndWhite,
              brightness: brightness,
            ),
            sourcePath: path,
          ),
        ).black;
        expect(black, lessThan(previous), reason: 'brightness $brightness');
        previous = black;
      }
    });

    test('receipt mode keeps faint print that document mode drops', () async {
      // Worn thermal paper: print only slightly darker than the paper.
      final faint = drawFlatPage(
        _w,
        _h,
        page: (u, v) => stripedPage(u, v) == inkColor ? 0xC8C8C8 : 0xECECEC,
      );
      final path = await work.write('faint.png', pngOf(faint));
      const adjustments = ImageAdjustments(filter: ScanFilter.blackAndWhite);
      final asDocument = _Stats(await render(adjustments, sourcePath: path));
      final asReceipt = _Stats(
        await render(adjustments, sourcePath: path, mode: ScanMode.receipt),
      );
      final printed = 0.35 * 0.8 * 0.84 * asReceipt.pixels;
      expect(asReceipt.black, greaterThan(0.85 * printed));
      expect(asDocument.black, lessThan(0.3 * printed));
    });
  });

  group('grayscale', () {
    test('has equal channels in PNG and in JPEG', () async {
      final png = await filtered(ScanFilter.grayscale);
      expect(_Stats(png).maxChannelSpread, 0);
      expect(png.redCentroid(), isNull);

      final jpg = await render(
        const ImageAdjustments(filter: ScanFilter.grayscale, saturation: 1),
        format: OutputFormat.jpg,
      );
      expect(_Stats(jpg).maxChannelSpread, lessThanOrEqualTo(2));
    });

    test('keeps paper light and ink dark', () async {
      final page = await filtered(ScanFilter.grayscale);
      expect(page.luma(10, _h ~/ 2), greaterThan(215));
      expect(page.luma(_w ~/ 2, (0.09 * _h).round()), lessThan(60));
    });
  });

  group('sliders', () {
    test('brightness is monotonic', () async {
      var previous = -1.0;
      for (final brightness in [-1.0, -0.6, -0.2, 0.0, 0.2, 0.6, 1.0]) {
        final mean = _Stats(
          await render(ImageAdjustments(brightness: brightness)),
        ).meanLuma;
        expect(
          mean,
          greaterThan(previous + 1),
          reason: 'brightness $brightness',
        );
        previous = mean;
      }
    });

    test('contrast is monotonic', () async {
      // Mid-tones only, so that no step is hidden by clipping.
      final soft = drawFlatPage(
        _w,
        _h,
        page: (u, v) => stripedPage(u, v) == inkColor ? 0x6E6E6E : 0x969696,
      );
      final path = await work.write('soft.png', pngOf(soft));
      var previous = -1.0;
      for (final contrast in [-1.0, -0.6, -0.2, 0.0, 0.2, 0.6, 1.0]) {
        final deviation = _Stats(
          await render(ImageAdjustments(contrast: contrast), sourcePath: path),
        ).deviation;
        expect(
          deviation,
          greaterThan(previous + 0.5),
          reason: 'contrast $contrast',
        );
        previous = deviation;
      }
    });

    test('saturation goes from grey to vivid', () async {
      var previous = -1.0;
      for (final saturation in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
        final stats = _Stats(
          await render(ImageAdjustments(saturation: saturation)),
        );
        expect(
          stats.meanChroma,
          greaterThan(previous),
          reason: 'saturation $saturation',
        );
        previous = stats.meanChroma;
        if (saturation == -1) {
          expect(stats.maxChannelSpread, lessThanOrEqualTo(1));
        }
        // Saturation leaves the brightness of the page alone.
        expect(stats.meanLuma, closeTo(_Stats(source).meanLuma, 1.5));
      }
    });
  });

  group('illumination', () {
    test(
      'noShadow removes most of the luminance gradient of a shadowed page',
      () async {
        final before = _shadowGradient(work.decode(shadowedPath));
        expect(before, greaterThan(100));

        final page = await filtered(
          ScanFilter.noShadow,
          sourcePath: shadowedPath,
        );
        final after = _shadowGradient(page).abs();
        expect(after, lessThan(0.1 * before));

        // Text survives on both sides, and so does the colour of the marker.
        for (final u in [0.15, 0.85]) {
          final x = (u * _w).round();
          final ink = page.luma(x, (0.09 * _h).round());
          final paper = page.luma(x, (0.13 * _h).round());
          expect(paper - ink, greaterThan(120), reason: 'u=$u');
        }
        expect(page.redCentroid(), isNotNull);
      },
    );

    test('readability also whitens the paper under the shadow', () async {
      final page = await filtered(
        ScanFilter.readability,
        sourcePath: shadowedPath,
      );
      expect(_shadowGradient(page).abs(), lessThan(6));
      expect(page.meanLuma(0.02, 0.1, 0.07, 0.9), greaterThan(245));
      expect(page.meanLuma(0.93, 0.1, 0.98, 0.9), greaterThan(245));
      expect(page.luma((0.85 * _w).round(), (0.09 * _h).round()), lessThan(60));
    });

    test('filters without illumination correction keep the shadow', () async {
      final before = _shadowGradient(work.decode(shadowedPath));
      for (final filter in [ScanFilter.original, ScanFilter.grayscale]) {
        final page = await filtered(filter, sourcePath: shadowedPath);
        expect(
          _shadowGradient(page),
          greaterThan(0.7 * before),
          reason: '$filter',
        );
      }
    });
  });

  test('enhanced stretches a dull capture and keeps its colours', () async {
    final dull = drawFlatPage(
      _w,
      _h,
      page: (u, v) => switch (markedPage(u, v)) {
        inkColor => 0x5A5A60,
        markerColor => 0xB04040,
        _ => 0xB4B0A8,
      },
    );
    final path = await work.write('dull.png', pngOf(dull));
    final before = _Stats(work.decode(path));
    final page = await filtered(ScanFilter.enhanced, sourcePath: path);
    final after = _Stats(page);
    expect(after.deviation, greaterThan(1.3 * before.deviation));
    expect(page.luma(10, _h ~/ 2), greaterThan(225));
    expect(page.luma(_w ~/ 2, (0.09 * _h).round()), lessThan(60));
    final marker = page.rgb((0.25 * _w).round(), (0.7 * _h).round());
    expect(marker[0] - math.max(marker[1], marker[2]), greaterThan(112));
  });

  test(
    'a filter looks the same on a reduced copy (preview = render)',
    () async {
      for (final filter in ScanFilter.values) {
        final full = _Stats(await filtered(filter, sourcePath: shadowedPath));
        final reduced = _Stats(
          await render(
            ImageAdjustments(filter: filter),
            sourcePath: shadowedPath,
            maxLongEdge: _w ~/ 2,
          ),
        );
        expect(reduced.meanLuma, closeTo(full.meanLuma, 6), reason: '$filter');
      }
    },
  );

  group('capture modes', () {
    test('each preset yields a measurably different page', () async {
      final pages = <ScanMode, Decoded>{
        for (final mode in ScanMode.values)
          mode: await render(
            mode.preset.adjustments,
            mode: mode,
            sourcePath: shadowedPath,
          ),
      };
      final untouched = work.decode(shadowedPath);
      final report = StringBuffer();
      for (final a in ScanMode.values) {
        expect(
          _difference(pages[a]!, untouched),
          greaterThan(4),
          reason: '$a vs original',
        );
        for (final b in ScanMode.values) {
          if (b.index <= a.index) continue;
          final difference = _difference(pages[a]!, pages[b]!);
          report.writeln('${a.name} vs ${b.name}: $difference');
          expect(difference, greaterThan(1), reason: '$a vs $b');
        }
      }
      printOnFailure(report.toString());
    });

    test('each preset has the character its mode calls for', () async {
      Future<Decoded> preset(ScanMode mode) =>
          render(mode.preset.adjustments, mode: mode, sourcePath: shadowedPath);
      final document = await preset(ScanMode.document);
      final receipt = await preset(ScanMode.receipt);
      final book = await preset(ScanMode.book);
      final whiteboard = await preset(ScanMode.whiteboard);
      final idCard = await preset(ScanMode.idCard);

      List<int> markerOf(Decoded page) =>
          page.rgb((0.25 * _w).round(), (0.7 * _h).round());
      int vividness(Decoded page) {
        final c = markerOf(page);
        return c[0] - math.max(c[1], c[2]);
      }

      // Receipt: two tones only.
      final receiptStats = _Stats(receipt);
      expect(receiptStats.black + receiptStats.white, receiptStats.pixels);

      // Document: colours kept on whitened paper.
      expect(vividness(document), greaterThan(100));
      expect(_shadowGradient(document).abs(), lessThan(6));

      // Book: stronger than document, ink is darker in the shadowed part.
      final inkX = (0.85 * _w).round();
      final inkY = (0.09 * _h).round();
      expect(book.luma(inkX, inkY), lessThan(document.luma(inkX, inkY)));
      expect(_Stats(book).meanLuma, lessThan(_Stats(document).meanLuma));

      // Whiteboard: even lighting, the most vivid marker of all.
      expect(_shadowGradient(whiteboard).abs(), lessThan(8));
      expect(vividness(whiteboard), greaterThanOrEqualTo(vividness(document)));
      expect(
        _Stats(whiteboard).meanChroma,
        greaterThan(_Stats(document).meanChroma),
      );

      // Identity card: a photo-like rendition, lighting left as it is.
      expect(
        _shadowGradient(idCard),
        greaterThan(0.6 * _shadowGradient(work.decode(shadowedPath))),
      );
      expect(vividness(idCard), greaterThan(100));
    });
  });

  test(
    'a large page keeps the filters exact (integral image overflow)',
    () async {
      // 2600 x 1900 of near-white paper: window sums exceed 32 bits if the
      // summed-area tables are not handled with care.
      Raster? big = drawFlatPage(2600, 1900);
      final path = await work.write('bigpage.png', pngOf(big));
      big = null;
      final page = await filtered(
        ScanFilter.blackAndWhite,
        sourcePath: path,
        mode: ScanMode.receipt,
      );
      final stats = _Stats(page);
      expect(stats.black + stats.white, stats.pixels);
      expect(stats.black / stats.pixels, closeTo(0.35 * 0.8 * 0.84, 0.03));
      expect(File(path).existsSync(), isTrue);
    },
  );
}
