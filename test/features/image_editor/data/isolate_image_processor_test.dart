import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/features/image_editor/data/isolate_image_processor.dart';
import 'package:md_scanner/features/image_editor/data/raster.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

import '../support/synthetic.dart';
import '../support/workspace.dart';

const int _w = 1000;
const int _h = 750;

/// Where the red marker of [markedPage] sits on the page.
const double _markerU = 0.25;
const double _markerV = 0.7;

void main() {
  late Workspace work;
  late IsolateImageProcessor processor;
  late String scenePath;
  final quad = Projection.tilted.quadIn(_w, _h);

  setUpAll(() async {
    work = await Workspace.create();
    scenePath = await work.write(
      'scene.jpg',
      jpegOf(
        drawScene(
          width: _w,
          height: _h,
          projection: Projection.tilted,
          page: markedPage,
        ),
      ),
    );
  });

  tearDownAll(() => work.dispose());

  setUp(() => processor = IsolateImageProcessor());

  Future<Decoded> render({
    Quad? quad,
    ImageAdjustments adjustments = ImageAdjustments.none,
    ScanMode mode = ScanMode.document,
    int maxLongEdge = ImageRenderRequest.defaultMaxLongEdge,
    String? source,
  }) async {
    final output = work.path('out_${quad == null}_$maxLongEdge.png');
    final result = valueOf(
      await processor.render(
        ImageRenderRequest(
          sourcePath: source ?? scenePath,
          outputPath: output,
          quad: quad,
          adjustments: adjustments,
          mode: mode,
          format: OutputFormat.png,
          maxLongEdge: maxLongEdge,
        ),
      ),
    );
    final decoded = work.decode(result.path);
    expect([decoded.width, decoded.height], [result.width, result.height]);
    return decoded;
  }

  void expectMarkerAt(Decoded page, double u, double v) {
    final centroid = page.redCentroid();
    expect(centroid, isNotNull, reason: 'marker not found');
    expect(centroid!.x / page.width, closeTo(u, 0.01));
    expect(centroid.y / page.height, closeTo(v, 0.01));
  }

  group('inspect', () {
    test('reports the pixel size and the size of the file', () async {
      final info = valueOf(await processor.inspect(scenePath));
      expect([info.width, info.height], [_w, _h]);
      expect(info.byteSize, File(scenePath).lengthSync());
      expect(info.isLandscape, isTrue);
    });

    test('reports the upright size of a rotated capture', () async {
      final path = await work.write(
        'exif.jpg',
        jpegOf(drawFlatPage(200, 100), exifOrientation: 6),
      );
      final info = valueOf(await processor.inspect(path));
      expect([info.width, info.height], [100, 200]);
    });
  });

  group('detectDocument', () {
    test('finds the page of a captured file', () async {
      final found = valueOf(await processor.detectDocument(scenePath));
      expect(found, isNotNull);
      final expected = quad.corners;
      final corners = found!.corners;
      final diagonal = math.sqrt(_w * _w + _h * _h);
      for (var i = 0; i < 4; i++) {
        final dx = (corners[i].x - expected[i].x) * _w;
        final dy = (corners[i].y - expected[i].y) * _h;
        final error = 100 * math.sqrt(dx * dx + dy * dy) / diagonal;
        expect(error, lessThanOrEqualTo(3), reason: 'corner $i');
        expect(error, lessThan(0.6), reason: 'corner $i');
      }
    });

    test('answers null, not a guess, for a featureless capture', () async {
      final path = await work.write('noise.jpg', jpegOf(drawNoise(640, 480)));
      for (final mode in ScanMode.values) {
        final result = await processor.detectDocument(path, mode: mode);
        expect(result.isSuccess, isTrue, reason: '$mode');
        expect(result.valueOrNull, isNull, reason: '$mode');
      }
    });

    test('gives the same answer once the page is loaded for preview', () async {
      final before = valueOf(await processor.detectDocument(scenePath));
      valueOf(
        await processor.preview(ImagePreviewRequest(sourcePath: scenePath)),
      );
      final after = valueOf(await processor.detectDocument(scenePath));
      expect(after, isNotNull);
      for (var i = 0; i < 4; i++) {
        expect(
          after!.corners[i].distanceTo(before!.corners[i]),
          lessThan(0.004),
        );
      }
    });
  });

  group('render geometry', () {
    test('the whole image keeps its size and is never enlarged', () async {
      final page = await render(maxLongEdge: 5000);
      expect([page.width, page.height], [_w, _h]);
      final marker = Projection.tilted.toImage(_markerU, _markerV);
      expectMarkerAt(page, marker.x / _w, marker.y / _h);
    });

    test('Quad.full means the whole image', () async {
      final page = await render(quad: Quad.full);
      expect([page.width, page.height], [_w, _h]);
    });

    test('rectifies the quad: the marker lands where it is on the page and '
        'the size follows the edges of the quad', () async {
      final page = await render(quad: quad);
      expectMarkerAt(page, _markerU, _markerV);

      final c = Projection.tilted.corners;
      double side(int a, int b) => c[a].distanceTo(c[b]);
      expect(page.width, closeTo(math.max(side(0, 1), side(3, 2)), 1));
      expect(page.height, closeTo(math.max(side(0, 3), side(1, 2)), 1));

      // Paper right up to the four borders: no table left, nothing cut.
      for (final (x, y) in [
        (0.02, 0.02),
        (0.98, 0.02),
        (0.98, 0.98),
        (0.02, 0.98),
      ]) {
        expect(
          page.luma((x * page.width).floor(), (y * page.height).floor()),
          greaterThan(200),
        );
      }
    });

    test('quarter turns rotate clockwise and swap the dimensions', () async {
      final upright = await render(quad: quad);
      const expected = {
        1: (1 - _markerV, _markerU),
        2: (1 - _markerU, 1 - _markerV),
        3: (_markerV, 1 - _markerU),
      };
      for (final MapEntry(key: turns, value: (u, v)) in expected.entries) {
        final page = await render(
          quad: quad,
          adjustments: ImageAdjustments(quarterTurns: turns),
        );
        final swapped = turns.isOdd;
        expect(
          [page.width, page.height],
          swapped
              ? [upright.height, upright.width]
              : [upright.width, upright.height],
          reason: '$turns turns',
        );
        expectMarkerAt(page, u, v);
      }
    });

    test(
      'maxLongEdge caps the longest side and keeps the proportions',
      () async {
        final whole = await render(maxLongEdge: 300);
        expect([whole.width, whole.height], [300, 225]);

        final turned = await render(
          maxLongEdge: 300,
          adjustments: const ImageAdjustments(quarterTurns: 1),
        );
        expect([turned.width, turned.height], [225, 300]);

        final full = await render(quad: quad);
        final page = await render(quad: quad, maxLongEdge: 240);
        expect(math.max(page.width, page.height), 240);
        expect(
          page.width / page.height,
          closeTo(full.width / full.height, 0.01),
        );
        expectMarkerAt(page, _markerU, _markerV);
      },
    );

    test('EXIF orientation is baked in before anything else', () async {
      final stored = drawFlatPage(200, 100, page: (u, v) => paperColor);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final i = (y * 200 + x) * 3;
          stored.data[i] = 0xE0;
          stored.data[i + 1] = 0x10;
          stored.data[i + 2] = 0x10;
        }
      }
      final path = await work.write(
        'exif_marker.jpg',
        jpegOf(stored, exifOrientation: 6),
      );
      // Orientation 6: the stored top-left corner is the upright top-right.
      final page = await render(source: path);
      expect([page.width, page.height], [100, 200]);
      expectMarkerAt(page, 0.8, 0.1);
    });

    test('a card close to ID-1 is rendered at exactly 85.6 x 54', () async {
      // 400 x 258 px in the frame: 1.550, a little squashed by the angle.
      const card = Quad(
        topLeft: NormalizedPoint(0.3, 0.2),
        topRight: NormalizedPoint(0.7, 0.2),
        bottomRight: NormalizedPoint(0.7, 0.544),
        bottomLeft: NormalizedPoint(0.3, 0.544),
      );
      final asDocument = await render(quad: card);
      expect([asDocument.width, asDocument.height], [400, 258]);

      final asCard = await render(quad: card, mode: ScanMode.idCard);
      expect(asCard.width, 400);
      expect(asCard.width / asCard.height, closeTo(85.6 / 54, 0.005));

      // A passport page (1.42) is not a card and keeps its proportions.
      final passport = card.copyWith(
        bottomRight: const NormalizedPoint(0.7, 0.576),
        bottomLeft: const NormalizedPoint(0.3, 0.576),
      );
      final page = await render(quad: passport, mode: ScanMode.idCard);
      expect([page.width, page.height], [400, 282]);
    });
  });

  group('render output', () {
    test('writes a JPEG or a PNG and describes it', () async {
      for (final format in OutputFormat.values) {
        final output = work.path('format.${format.extension}');
        final result = valueOf(
          await processor.render(
            ImageRenderRequest(
              sourcePath: scenePath,
              outputPath: output,
              quad: quad,
              format: format,
            ),
          ),
        );
        final bytes = File(output).readAsBytesSync();
        expect(
          hasSignature(
            bytes,
            format == OutputFormat.jpg ? jpegSignature : pngSignature,
          ),
          isTrue,
          reason: '$format',
        );
        expect(result.path, output);
        expect(result.format, format);
        expect(result.byteSize, bytes.length);
        final decoded = Decoded.bytes(bytes);
        expect([decoded.width, decoded.height], [result.width, result.height]);
      }
    });

    test('a lower JPEG quality gives a smaller file', () async {
      Future<int> sizeAt(int quality) async => valueOf(
        await processor.render(
          ImageRenderRequest(
            sourcePath: scenePath,
            outputPath: work.path('quality.jpg'),
            jpegQuality: quality,
          ),
        ),
      ).byteSize;
      expect(await sizeAt(40), lessThan(await sizeAt(88)));
      expect(await sizeAt(88), lessThan(await sizeAt(100)));
    });

    test('replaces an existing output and may overwrite its source', () async {
      final path = await work.write(
        'inplace.jpg',
        File(scenePath).readAsBytesSync(),
      );
      final result = valueOf(
        await processor.render(
          ImageRenderRequest(
            sourcePath: path,
            outputPath: path,
            quad: quad,
            maxLongEdge: 320,
          ),
        ),
      );
      final page = work.decode(path);
      expect(math.max(page.width, page.height), 320);
      expect(result.byteSize, File(path).lengthSync());
      expect(work.fileNames.where((name) => name.endsWith('.part')), isEmpty);
    });

    test('many pages can be rendered at once', () async {
      final results = await Future.wait([
        for (var i = 0; i < 6; i++)
          processor.render(
            ImageRenderRequest(
              sourcePath: scenePath,
              outputPath: work.path('batch_$i.jpg'),
              quad: quad,
              maxLongEdge: 200 + 20 * i,
            ),
          ),
      ]);
      for (var i = 0; i < results.length; i++) {
        final page = valueOf(results[i]);
        expect(math.max(page.width, page.height), 200 + 20 * i);
        expect(File(page.path).existsSync(), isTrue);
      }
    });
  });

  group('preview', () {
    test('returns a JPEG no larger than requested', () async {
      final large = await work.write(
        'large.jpg',
        jpegOf(drawFlatPage(2400, 1800, page: markedPage)),
      );
      final standard = valueOf(
        await processor.preview(ImagePreviewRequest(sourcePath: large)),
      );
      expect(hasSignature(standard, jpegSignature), isTrue);
      final decoded = Decoded.bytes(standard);
      expect([decoded.width, decoded.height], [1280, 960]);

      final small = Decoded.bytes(
        valueOf(
          await processor.preview(
            ImagePreviewRequest(sourcePath: large, maxLongEdge: 400),
          ),
        ),
      );
      expect([small.width, small.height], [400, 300]);
      expectMarkerAt(small, _markerU, _markerV);
    });

    test('applies the quad, the rotation and the filter like render', () async {
      final preview = Decoded.bytes(
        valueOf(
          await processor.preview(
            ImagePreviewRequest(
              sourcePath: scenePath,
              quad: quad,
              adjustments: const ImageAdjustments(quarterTurns: 1),
            ),
          ),
        ),
      );
      final rendered = await render(
        quad: quad,
        adjustments: const ImageAdjustments(quarterTurns: 1),
      );
      expect(preview.width, closeTo(rendered.width, 2));
      expect(preview.height, closeTo(rendered.height, 2));
      expectMarkerAt(preview, 1 - _markerV, _markerU);

      final gray = Decoded.bytes(
        valueOf(
          await processor.preview(
            ImagePreviewRequest(
              sourcePath: scenePath,
              quad: quad,
              adjustments: const ImageAdjustments(filter: ScanFilter.grayscale),
            ),
          ),
        ),
      );
      expect(gray.redCentroid(), isNull);
    });

    test('follows the file when its content changes', () async {
      final path = work.path('changing.jpg');
      await work.write('changing.jpg', jpegOf(drawFlatPage(400, 300)));
      final first = Decoded.bytes(
        valueOf(await processor.preview(ImagePreviewRequest(sourcePath: path))),
      );
      expect(first.redCentroid(), isNull);

      await work.write(
        'changing.jpg',
        jpegOf(drawFlatPage(600, 300, page: markedPage)),
      );
      final second = Decoded.bytes(
        valueOf(await processor.preview(ImagePreviewRequest(sourcePath: path))),
      );
      expect([second.width, second.height], [600, 300]);
      expectMarkerAt(second, _markerU, _markerV);

      processor.clearPreviewCache();
      final third = Decoded.bytes(
        valueOf(await processor.preview(ImagePreviewRequest(sourcePath: path))),
      );
      expect([third.width, third.height], [600, 300]);
    });
  });

  group('thumbnail', () {
    test('fits in maxSize, keeps the proportions, returns its path', () async {
      for (final maxSize in [512, 128, 33]) {
        final output = work.path('thumb_$maxSize.jpg');
        final result = valueOf(
          await processor.thumbnail(scenePath, output, maxSize: maxSize),
        );
        expect(result, output);
        final bytes = File(output).readAsBytesSync();
        expect(hasSignature(bytes, jpegSignature), isTrue);
        final thumb = Decoded.bytes(bytes);
        expect(thumb.width, maxSize);
        expect(thumb.height, lessThanOrEqualTo(maxSize));
        expect(thumb.width / thumb.height, closeTo(_w / _h, 0.03));
      }
    });

    test('is a PNG when asked, and never enlarges a small image', () async {
      final small = await work.write('small.png', pngOf(drawFlatPage(90, 60)));
      final output = work.path('thumb.png');
      valueOf(await processor.thumbnail(small, output));
      final bytes = File(output).readAsBytesSync();
      expect(hasSignature(bytes, pngSignature), isTrue);
      final thumb = Decoded.bytes(bytes);
      expect([thumb.width, thumb.height], [90, 60]);
    });

    test('shows the upright image', () async {
      final path = await work.write(
        'exif_thumb.jpg',
        jpegOf(drawFlatPage(800, 400), exifOrientation: 6),
      );
      final output = work.path('thumb_exif.jpg');
      valueOf(await processor.thumbnail(path, output, maxSize: 100));
      final thumb = work.decode(output);
      expect([thumb.width, thumb.height], [50, 100]);
    });
  });

  test(
    'timing of a 12 megapixel page (printed, not asserted)',
    () async {
      const projection = Projection(
        2300,
        120,
        350,
        -100,
        3200,
        380,
        0.08,
        0.10,
      );
      Raster? scene = drawScene(
        width: 3000,
        height: 4000,
        projection: projection,
        page: markedPage,
      );
      final path = await work.write('big.jpg', jpegOf(scene, quality: 90));
      scene = null;
      final bigQuad = projection.quadIn(3000, 4000);

      Future<int> time(Future<Object?> Function() action) async {
        final watch = Stopwatch()..start();
        await action();
        return watch.elapsedMilliseconds;
      }

      final detect = await time(
        () async =>
            expect(valueOf(await processor.detectDocument(path)), isNotNull),
      );
      final lines = <String>['detectDocument: $detect ms'];
      for (final mode in [ScanMode.document, ScanMode.receipt]) {
        final adjustments = mode.preset.adjustments;
        final format = OutputFormat.recommendedFor(adjustments.filter);
        late ProcessedImage page;
        final ms = await time(
          () async => page = valueOf(
            await processor.render(
              ImageRenderRequest(
                sourcePath: path,
                outputPath: work.path('big_out.${format.extension}'),
                quad: bigQuad,
                adjustments: adjustments,
                mode: mode,
                format: format,
              ),
            ),
          ),
        );
        expect(math.max(page.width, page.height), 2600);
        lines.add(
          'render ${mode.name} -> ${page.width}x${page.height} '
          '${format.name}, ${page.byteSize ~/ 1024} kB: $ms ms',
        );
      }
      final request = ImagePreviewRequest(
        sourcePath: path,
        quad: bigQuad,
        adjustments: ScanModePreset.document.adjustments,
      );
      final firstPreview = await time(() => processor.preview(request));
      final nextPreview = await time(
        () => processor.preview(
          request.copyWith(
            adjustments: const ImageAdjustments(filter: ScanFilter.noShadow),
          ),
        ),
      );
      lines
        ..add('preview, first of a page: $firstPreview ms')
        ..add('preview, following ones: $nextPreview ms')
        ..add(
          'thumbnail: ${await time(() => processor.thumbnail(path, work.path('big_thumb.jpg')))} ms',
        );
      // ignore: avoid_print
      print('3000x4000 JPEG source, host timings:\n  ${lines.join('\n  ')}');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
