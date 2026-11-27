import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_engine_impl.dart';
import 'package:md_scanner/features/pdf_tools/domain/page_range.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:path/path.dart' as p;

import '../helpers/pdf_fixtures.dart';

const _invalidRange = PdfFailure(PdfFailureKind.invalidPageRange);

void main() {
  late Directory dir;
  late PdfEngineImpl engine;
  late String five;
  late String three;
  var counter = 0;

  String out([String extension = 'pdf']) =>
      p.join(dir.path, 'out_${counter++}.$extension');

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('mds_structure_');
    engine = createTestEngine(dir);
    five = (await writeTextPdf(dir, 'five.pdf', count: 5)).path;
    three = (await writeTextPdf(dir, 'three.pdf', count: 3, label: 'Doc')).path;
  });

  tearDownAll(() => dir.delete(recursive: true));

  tearDown(() {
    expect(leftoverPartials(dir), isEmpty);
    expect(leftoverTempFiles(dir), isEmpty);
  });

  group('inspect', () {
    test('reads page count, sizes, protection and file size', () async {
      final info = (await engine.inspect(five)).valueOrNull!;
      expect(info.pageCount, 5);
      expect(info.isEncrypted, isFalse);
      expect(info.fileSize, File(five).lengthSync());
      expect(info.pageSizes, hasLength(5));
      expect(info.pageSizes.first.width, closeTo(300, 0.01));
      expect(info.pageSizes.first.height, closeTo(400, 0.01));
      expect(info.pageSizes.last.height, closeTo(440, 0.01));
      expect(info.pageSizes.first.rotationDegrees, 0);
    });

    test('a missing file is a storage failure', () async {
      final result = await engine.inspect(p.join(dir.path, 'nope.pdf'));
      expect(
        result.failureOrNull,
        const StorageFailure(StorageFailureKind.notFound),
      );
    });

    test('garbage, empty and truncated-header files are corrupted', () async {
      final garbage = File(p.join(dir.path, 'garbage.pdf'))
        ..writeAsBytesSync([
          ...'%PDF-1.7\n'.codeUnits,
          for (var i = 0; i < 5000; i++) (i * 37 + 11) & 0xFF,
        ]);
      final noHeader = File(p.join(dir.path, 'no_header.pdf'))
        ..writeAsBytesSync(List<int>.filled(2000, 0x41));
      final empty = File(p.join(dir.path, 'empty.pdf'))..writeAsBytesSync([]);
      for (final file in [garbage, noHeader, empty]) {
        final failure = (await engine.inspect(file.path)).failureOrNull;
        expect(failure, const PdfFailure(PdfFailureKind.corrupted));
      }
    });
  });

  group('merge', () {
    test('concatenates documents in order without rasterizing', () async {
      final target = out();
      final progress = <(int, int)>[];
      final result = await engine.merge(
        inputPaths: [five, three],
        outputPath: target,
        onProgress: (done, total) => progress.add((done, total)),
      );
      final output = result.valueOrNull!;
      expect(output.pageCount, 8);
      expect(output.fileSize, File(target).lengthSync());
      expect(progress, [(1, 3), (2, 3), (3, 3)]);
      expect(await readPageTexts(target), [
        'Page 1',
        'Page 2',
        'Page 3',
        'Page 4',
        'Page 5',
        'Doc 1',
        'Doc 2',
        'Doc 3',
      ]);
      expect((await readPageSizes(target)).map((s) => s.$2), [
        400,
        410,
        420,
        430,
        440,
        400,
        410,
        420,
      ]);
      // Text pages must stay text: no image may have been introduced.
      final bytes = File(target).readAsBytesSync();
      expect(countOccurrences(bytes, '/Subtype /Image'), 0);
      expect(countOccurrences(bytes, '/Subtype/Image'), 0);
    });

    test('fails on an empty list and on a missing input', () async {
      final target = out();
      expect(
        (await engine.merge(inputPaths: [], outputPath: target)).failureOrNull,
        const PdfFailure(PdfFailureKind.emptyDocument),
      );
      final missing = await engine.merge(
        inputPaths: [five, p.join(dir.path, 'absent.pdf')],
        outputPath: target,
      );
      expect(
        missing.failureOrNull,
        const StorageFailure(StorageFailureKind.notFound),
      );
      expect(File(target).existsSync(), isFalse);
    });

    test('stops when cancelled and writes nothing', () async {
      final target = out();
      var cancelled = false;
      final result = await engine.merge(
        inputPaths: [five, three, five],
        outputPath: target,
        onProgress: (done, total) => cancelled = done >= 1,
        isCancelled: () => cancelled,
      );
      expect(result.failureOrNull, isA<CancelledFailure>());
      expect(File(target).existsSync(), isFalse);
    });
  });

  group('split', () {
    test('writes one file per range', () async {
      final folder = p.join(dir.path, 'split_ranges');
      final ranges = parsePageRanges('1-2,3,4-').valueOrNull!;
      final outputs = (await engine.split(
        path: five,
        outputDirectory: folder,
        ranges: ranges,
      )).valueOrNull!;
      expect(outputs.map((o) => p.basename(o.path)), [
        'part_001.pdf',
        'part_002.pdf',
        'part_003.pdf',
      ]);
      expect(outputs.map((o) => o.pageCount), [2, 1, 2]);
      expect(await readPageTexts(outputs[0].path), ['Page 1', 'Page 2']);
      expect(await readPageTexts(outputs[1].path), ['Page 3']);
      expect(await readPageTexts(outputs[2].path), ['Page 4', 'Page 5']);
    });

    test('splitEvery cuts fixed-size chunks', () async {
      final outputs = (await engine.splitEvery(
        path: five,
        outputDirectory: p.join(dir.path, 'split_every'),
        pagesPerFile: 2,
        fileNamePrefix: 'lot',
      )).valueOrNull!;
      expect(outputs.map((o) => p.basename(o.path)), [
        'lot_001.pdf',
        'lot_002.pdf',
        'lot_003.pdf',
      ]);
      expect(outputs.map((o) => o.pageCount), [2, 2, 1]);
      expect(await readPageTexts(outputs[2].path), ['Page 5']);
      expect(
        (await engine.splitEvery(
          path: five,
          outputDirectory: p.join(dir.path, 'split_zero'),
          pagesPerFile: 0,
        )).failureOrNull,
        _invalidRange,
      );
    });

    test('splitIntoSinglePages writes one file per page', () async {
      final progress = <int>[];
      final outputs = (await engine.splitIntoSinglePages(
        path: three,
        outputDirectory: p.join(dir.path, 'split_single'),
        onProgress: (done, total) => progress.add(done),
      )).valueOrNull!;
      expect(outputs, hasLength(3));
      expect(progress, [1, 2, 3]);
      for (var i = 0; i < 3; i++) {
        expect(await readPageTexts(outputs[i].path), ['Doc ${i + 1}']);
      }
    });

    test('rejects a range outside the document before writing', () async {
      final folder = Directory(p.join(dir.path, 'split_invalid'));
      final result = await engine.split(
        path: five,
        outputDirectory: folder.path,
        ranges: const [PageRange(1, 2), PageRange(5, 6)],
      );
      expect(result.failureOrNull, _invalidRange);
      expect(folder.existsSync() && folder.listSync().isNotEmpty, isFalse);
      expect(
        (await engine.split(
          path: five,
          outputDirectory: folder.path,
          ranges: const [],
        )).failureOrNull,
        _invalidRange,
      );
    });

    test('removes the files already written when cancelled', () async {
      final folder = Directory(p.join(dir.path, 'split_cancel'));
      var written = 0;
      final result = await engine.splitIntoSinglePages(
        path: five,
        outputDirectory: folder.path,
        onProgress: (done, total) => written = done,
        isCancelled: () => written >= 2,
      );
      expect(result.failureOrNull, isA<CancelledFailure>());
      expect(written, 2);
      expect(folder.listSync(), isEmpty);
    });
  });

  group('extractPages', () {
    test('keeps the requested pages in the requested order', () async {
      final target = out();
      final output = (await engine.extractPages(
        path: five,
        outputPath: target,
        pages: [4, 0, 2],
      )).valueOrNull!;
      expect(output.pageCount, 3);
      expect(await readPageTexts(target), ['Page 5', 'Page 1', 'Page 3']);
      expect((await readPageSizes(target)).map((s) => s.$2), [440, 400, 420]);
    });

    test('rejects an empty selection and unknown pages', () async {
      for (final pages in <List<int>>[
        [],
        [5],
        [-1],
      ]) {
        final result = await engine.extractPages(
          path: five,
          outputPath: out(),
          pages: pages,
        );
        expect(result.failureOrNull, _invalidRange);
      }
    });
  });

  group('deletePages', () {
    test('removes the pages and their content from the file', () async {
      final target = out();
      final output = (await engine.deletePages(
        path: five,
        outputPath: target,
        pages: {1, 3},
      )).valueOrNull!;
      expect(output.pageCount, 3);
      expect(await readPageTexts(target), ['Page 1', 'Page 3', 'Page 5']);
    });

    test('drops the image data of a deleted scanned page', () async {
      final images = [
        for (var i = 0; i < 3; i++)
          (await writeJpeg(dir, 'del_$i.jpg', 320, 440, seed: i)).path,
      ];
      final scan = out();
      await engine.imagesToPdf(imagePaths: images, outputPath: scan);
      expect(countOccurrences(File(scan).readAsBytesSync(), '/DCTDecode'), 3);
      final target = out();
      await engine.deletePages(path: scan, outputPath: target, pages: {1});
      final bytes = File(target).readAsBytesSync();
      expect(countOccurrences(bytes, '/DCTDecode'), 2);
      expect(bytes.length, lessThan(File(scan).lengthSync()));
    });

    test('refuses to delete every page or an unknown page', () async {
      expect(
        (await engine.deletePages(
          path: three,
          outputPath: out(),
          pages: {0, 1, 2},
        )).failureOrNull,
        const PdfFailure(PdfFailureKind.emptyDocument),
      );
      for (final pages in <Set<int>>[
        {},
        {3},
      ]) {
        expect(
          (await engine.deletePages(
            path: three,
            outputPath: out(),
            pages: pages,
          )).failureOrNull,
          _invalidRange,
        );
      }
    });
  });

  group('reorderPages', () {
    test('applies a full permutation', () async {
      for (final order in [
        [4, 3, 2, 1, 0],
        [2, 0, 1, 4, 3],
        [0, 1, 2, 3, 4],
      ]) {
        final target = out();
        final output = (await engine.reorderPages(
          path: five,
          outputPath: target,
          order: order,
        )).valueOrNull!;
        expect(output.pageCount, 5);
        expect(await readPageTexts(target), [
          for (final index in order) 'Page ${index + 1}',
        ]);
        expect((await readPageSizes(target)).map((s) => s.$2), [
          for (final index in order) 400 + 10 * index,
        ]);
      }
    });

    test('rejects anything that is not a permutation', () async {
      for (final order in [
        [0, 1, 2, 3],
        [0, 1, 2, 3, 3],
        [0, 1, 2, 3, 5],
        <int>[],
      ]) {
        final result = await engine.reorderPages(
          path: five,
          outputPath: out(),
          order: order,
        );
        expect(result.failureOrNull, _invalidRange);
      }
    });
  });

  group('rotatePages', () {
    test('adds quarter turns per page and keeps the text', () async {
      final target = out();
      final output = (await engine.rotatePages(
        path: five,
        outputPath: target,
        quarterTurns: {0: 1, 2: 2, 4: -1},
      )).valueOrNull!;
      expect(output.pageCount, 5);
      expect(await readPageRotations(target), [90, 0, 180, 0, 270]);
      final sizes = await readPageSizes(target);
      expect(sizes[0], (400, 300));
      expect(sizes[1], (300, 410));
      expect(sizes[4], (440, 300));
      // Text extraction order inside a rotated page is not guaranteed.
      final texts = await readPageTexts(target);
      expect(
        [for (final text in texts) (text.split(' ')..sort()).join(' ')],
        [for (var i = 1; i <= 5; i++) '$i Page'],
      );

      final info = (await engine.inspect(target)).valueOrNull!;
      expect(info.pageSizes.map((s) => s.rotationDegrees), [
        90,
        0,
        180,
        0,
        270,
      ]);
      expect(info.pageSizes.first.isLandscape, isTrue);

      final again = out();
      await engine.rotatePages(
        path: target,
        outputPath: again,
        quarterTurns: {0: 1, 4: 5},
      );
      expect(await readPageRotations(again), [180, 0, 180, 0, 0]);
    });

    test('rejects an empty request and unknown pages', () async {
      for (final turns in <Map<int, int>>[
        {},
        {5: 1},
      ]) {
        final result = await engine.rotatePages(
          path: five,
          outputPath: out(),
          quarterTurns: turns,
        );
        expect(result.failureOrNull, _invalidRange);
      }
    });
  });
}
