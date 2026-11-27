import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/features/image_editor/data/isolate_image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';

import '../support/synthetic.dart';
import '../support/workspace.dart';

Uint8List _garbage(int length, {List<int> prefix = const [0x13, 0x37]}) {
  final random = math.Random(11);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  bytes.setRange(0, prefix.length, prefix);
  return bytes;
}

void main() {
  late Workspace work;
  late AppLogger logger;
  late IsolateImageProcessor processor;
  late String validPath;

  setUp(() async {
    work = await Workspace.create();
    logger = AppLogger();
    processor = IsolateImageProcessor(logger: logger);
    validPath = await work.write('valid.jpg', jpegOf(drawFlatPage(320, 240)));
  });

  tearDown(() => work.dispose());

  /// Runs the five operations on [path] and checks each fails with [matcher]
  /// without creating any file.
  Future<void> expectAllFail(String path, Matcher matcher) async {
    final before = work.fileNames;
    final output = work.path('never.jpg');
    expect(await processor.inspect(path), matcher, reason: 'inspect');
    expect(await processor.detectDocument(path), matcher, reason: 'detect');
    expect(
      await processor.render(
        ImageRenderRequest(sourcePath: path, outputPath: output),
      ),
      matcher,
      reason: 'render',
    );
    expect(
      await processor.preview(ImagePreviewRequest(sourcePath: path)),
      matcher,
      reason: 'preview',
    );
    expect(
      await processor.thumbnail(path, work.path('never_thumb.jpg')),
      matcher,
      reason: 'thumbnail',
    );
    expect(work.fileNames, before);
  }

  group('undecodable sources', () {
    test('random bytes -> decodeFailed', () async {
      final path = await work.write('garbage.jpg', _garbage(4096));
      await expectAllFail(path, failsWithImage(ImageFailureKind.decodeFailed));
    });

    test('an empty file -> decodeFailed', () async {
      final path = await work.write('empty.jpg', const []);
      await expectAllFail(path, failsWithImage(ImageFailureKind.decodeFailed));
    });

    test('a JPEG signature followed by garbage -> decodeFailed', () async {
      final path = await work.write(
        'fake.jpg',
        _garbage(4096, prefix: const [0xFF, 0xD8, 0xFF, 0xE0]),
      );
      await expectAllFail(path, failsWithImage(ImageFailureKind.decodeFailed));
    });

    test('a JPEG cut inside its headers -> decodeFailed', () async {
      final bytes = File(validPath).readAsBytesSync();
      final path = await work.write('cut.jpg', bytes.sublist(0, 60));
      await expectAllFail(path, failsWithImage(ImageFailureKind.decodeFailed));
    });

    test('a PNG whose pixel data is damaged fails to render', () async {
      final bytes = pngOf(drawNoise(200, 150));
      // Leave the header intact: the size is still readable, pixels are not.
      bytes.fillRange(60, bytes.length - 20, 0x5A);
      final path = await work.write('damaged.png', bytes);
      final output = work.path('damaged_out.png');
      expect(
        await processor.render(
          ImageRenderRequest(sourcePath: path, outputPath: output),
        ),
        failsWithImage(ImageFailureKind.decodeFailed),
      );
      expect(File(output).existsSync(), isFalse);
    });
  });

  group('recognized formats that cannot be read -> unsupportedFormat', () {
    final samples = <String, List<int>>{
      'HEIC': [
        0,
        0,
        0,
        0x18,
        ...'ftypheic'.codeUnits,
        0,
        0,
        0,
        0,
        ...'mif1heic'.codeUnits,
      ],
      'AVIF': [
        0,
        0,
        0,
        0x1C,
        ...'ftypavif'.codeUnits,
        0,
        0,
        0,
        0,
        ...'avifmif1'.codeUnits,
      ],
      'PDF': '%PDF-1.7\n1 0 obj\n<<>>\nendobj\n'.codeUnits,
      'SVG': '<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits,
      'JPEG 2000': [
        0,
        0,
        0,
        0x0C,
        0x6A,
        0x50,
        0x20,
        0x20,
        0x0D,
        0x0A,
        0x87,
        0x0A,
      ],
      'Photoshop': [...'8BPS'.codeUnits, 0, 1, 0, 0, 0, 0, 0, 0],
    };
    for (final MapEntry(key: name, value: bytes) in samples.entries) {
      test(name, () async {
        // The extension lies on purpose: only the content counts.
        final path = await work.write('renamed.jpg', bytes);
        await expectAllFail(
          path,
          failsWithImage(ImageFailureKind.unsupportedFormat),
        );
      });
    }
  });

  group('oversized sources -> tooLarge', () {
    test('just above 64 megapixels, refused from the header alone', () async {
      final path = await work.write('81mp.png', pngHeaderClaiming(9000, 9000));
      await expectAllFail(path, failsWithImage(ImageFailureKind.tooLarge));
    });

    test('absurd sizes, including ones whose product overflows', () async {
      for (final (width, height) in [
        (30000, 30000),
        (0x7FFFFFFF, 0x7FFFFFFF),
      ]) {
        final path = await work.write(
          'huge.png',
          pngHeaderClaiming(width, height),
        );
        expect(
          await processor.inspect(path),
          failsWithImage(ImageFailureKind.tooLarge),
          reason: '$width x $height',
        );
      }
    });

    test('64 megapixels exactly is within the limit', () async {
      final path = await work.write('64mp.png', pngHeaderClaiming(8000, 8000));
      final info = valueOf(await processor.inspect(path));
      expect(info.pixelCount, ImageProcessor.maxSourcePixels);
    });
  });

  group('storage problems', () {
    test('a missing source -> StorageFailure(notFound)', () async {
      await expectAllFail(
        work.path('missing.jpg'),
        failsWithStorage(StorageFailureKind.notFound),
      );
    });

    test('an unwritable output -> StorageFailure(writeError), nothing left '
        'behind', () async {
      // A regular file where the output directory should be.
      final blocker = await work.write('blocker', const [1, 2, 3]);
      final before = work.fileNames;
      final output = '$blocker${Platform.pathSeparator}page.jpg';
      expect(
        await processor.render(
          ImageRenderRequest(sourcePath: validPath, outputPath: output),
        ),
        failsWithStorage(StorageFailureKind.writeError),
      );
      expect(
        await processor.thumbnail(validPath, output),
        failsWithStorage(StorageFailureKind.writeError),
      );
      expect(work.fileNames, before);
      expect(File(blocker).readAsBytesSync(), [1, 2, 3]);
    });
  });

  group('a failed render', () {
    test('keeps the previous output untouched', () async {
      final output = await work.write('page.jpg', const [9, 8, 7, 6]);
      final broken = await work.write('broken.jpg', _garbage(2048));
      expect(
        await processor.render(
          ImageRenderRequest(sourcePath: broken, outputPath: output),
        ),
        failsWithImage(ImageFailureKind.decodeFailed),
      );
      expect(File(output).readAsBytesSync(), [9, 8, 7, 6]);
      expect(work.fileNames, ['broken.jpg', 'page.jpg', 'valid.jpg']);
    });

    test('refuses a quad that cannot be rectified', () async {
      const crossed = Quad(
        topLeft: NormalizedPoint(0.1, 0.1),
        topRight: NormalizedPoint(0.9, 0.9),
        bottomRight: NormalizedPoint(0.9, 0.1),
        bottomLeft: NormalizedPoint(0.1, 0.9),
      );
      const flat = Quad(
        topLeft: NormalizedPoint(0.1, 0.5),
        topRight: NormalizedPoint(0.4, 0.5),
        bottomRight: NormalizedPoint(0.7, 0.5),
        bottomLeft: NormalizedPoint(0.9, 0.5),
      );
      for (final quad in [crossed, flat]) {
        final output = work.path('quad.jpg');
        const expected = Err<Object?>(
          ValidationFailure(ImageProcessor.invalidQuadCode),
        );
        expect(
          (await processor.render(
            ImageRenderRequest(
              sourcePath: validPath,
              outputPath: output,
              quad: quad,
            ),
          )).failureOrNull,
          expected.failure,
        );
        expect(
          (await processor.preview(
            ImagePreviewRequest(sourcePath: validPath, quad: quad),
          )).failureOrNull,
          expected.failure,
        );
        expect(File(output).existsSync(), isFalse);
      }
    });

    test(
      'out-of-range corners and settings are clamped, not refused',
      () async {
        const outside = Quad(
          topLeft: NormalizedPoint(-0.4, -0.2),
          topRight: NormalizedPoint(1.3, 0),
          bottomRight: NormalizedPoint(1.2, 1.5),
          bottomLeft: NormalizedPoint(0, 1.1),
        );
        final page = valueOf(
          await processor.render(
            ImageRenderRequest(
              sourcePath: validPath,
              outputPath: work.path('clamped.jpg'),
              quad: outside,
              jpegQuality: 400,
              maxLongEdge: -5,
            ),
          ),
        );
        // The clamped quad is the whole image; the smallest accepted long
        // edge is 16 pixels.
        expect([page.width, page.height], [16, 12]);
      },
    );
  });

  group('technical journal', () {
    test(
      'records the duration of a render and nothing about the file',
      () async {
        valueOf(
          await processor.render(
            ImageRenderRequest(
              sourcePath: validPath,
              outputPath: work.path('logged.jpg'),
            ),
          ),
        );
        final event = logger.events.single;
        expect(event.name, 'image.render');
        expect(event.level, LogLevel.info);
        expect(event.attributes.keys, ['ms']);
        expect(event.attributes['ms'], isA<int>());
      },
    );

    test('records failures by kind, never with a path', () async {
      final path = await work.write('secret_name.jpg', _garbage(512));
      await processor.render(
        ImageRenderRequest(
          sourcePath: path,
          outputPath: work.path('secret_out.jpg'),
        ),
      );
      await processor.inspect(work.path('secret_missing.jpg'));
      expect(logger.events.map((e) => e.name), [
        'image.render.failed',
        'image.inspect.failed',
      ]);
      for (final event in logger.events) {
        expect(event.level, LogLevel.error);
        expect(event.toString(), isNot(contains('secret')));
        expect(event.toString(), isNot(contains(work.directory.path)));
      }
    });
  });
}
