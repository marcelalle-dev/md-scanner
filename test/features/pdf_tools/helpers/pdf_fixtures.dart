import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:md_scanner/features/pdf_tools/data/pdf_engine_impl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfium;

Directory? _pdfiumCache;

/// The production engine, wired for host tests: PDFium comes from the
/// Dart-only initializer and working files go under [directory].
PdfEngineImpl createTestEngine(Directory directory) => PdfEngineImpl(
  initializePdfium: initPdfiumForTests,
  tempDirectory: () => Directory(p.join(directory.path, 'engine_tmp')),
);

/// Files left in the engine's working directory (must be none after a call).
List<String> leftoverTempFiles(Directory directory) {
  final temp = Directory(p.join(directory.path, 'engine_tmp'));
  if (!temp.existsSync()) return const [];
  return [for (final entity in temp.listSync()) p.basename(entity.path)];
}

/// Partial outputs left anywhere under [directory] (must be none).
List<String> leftoverPartials(Directory directory) => [
  for (final entity in directory.listSync(recursive: true))
    if (entity.path.endsWith('.part')) p.basename(entity.path),
];

/// Loads PDFium for host tests with the Dart-only initializer of
/// pdfrx_engine (the app uses the Flutter one).
Future<void> initPdfiumForTests() async {
  _pdfiumCache ??= await Directory.systemTemp.createTemp('mds_pdfium_cache_');
  await pdfium.pdfrxInitialize(tmpPath: _pdfiumCache!.path);
}

/// A page of a generated vector PDF: its size in points and the text drawn
/// at its centre.
typedef TextPageSpec = ({double width, double height, String text});

/// Builds a PDF whose pages carry real text (Helvetica), so content can be
/// read back by a parser.
Future<Uint8List> buildTextPdf(List<TextPageSpec> pages) async {
  final document = pw.Document();
  for (final page in pages) {
    document.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat(page.width, page.height),
        build: (context) => pw.Center(
          child: pw.Text(page.text, style: const pw.TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
  return document.save();
}

/// `count` pages of distinct heights (400, 410, 420…) labelled
/// `<label> 1`, `<label> 2`…
Future<File> writeTextPdf(
  Directory directory,
  String name, {
  required int count,
  String label = 'Page',
  double width = 300,
  double firstHeight = 400,
}) async {
  final bytes = await buildTextPdf([
    for (var i = 0; i < count; i++)
      (width: width, height: firstHeight + 10 * i, text: '$label ${i + 1}'),
  ]);
  final file = File(p.join(directory.path, name));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// A synthetic photo-like image: smooth gradients plus texture, so JPEG
/// compression behaves as it does on a real scan.
img.Image syntheticImage(int width, int height, {int seed = 0}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final noise = ((x * 31 + y * 17 + seed * 101) * 2654435761) >> 24 & 63;
      image.setPixelRgb(
        x,
        y,
        (x * 255 ~/ width + noise) & 255,
        (y * 255 ~/ height + noise + seed * 40) & 255,
        ((x + y) * 127 ~/ (width + height) + noise) & 255,
      );
    }
  }
  return image;
}

Uint8List syntheticJpeg(int width, int height, {int seed = 0, int q = 85}) =>
    img.encodeJpg(syntheticImage(width, height, seed: seed), quality: q);

Future<File> writeJpeg(
  Directory directory,
  String name,
  int width,
  int height, {
  int seed = 0,
  int quality = 85,
}) async {
  final file = File(p.join(directory.path, name));
  await file.writeAsBytes(
    syntheticJpeg(width, height, seed: seed, q: quality),
    flush: true,
  );
  return file;
}

/// Text of every page as PDFium extracts it, whitespace-trimmed.
Future<List<String>> readPageTexts(String path, {String? password}) async {
  final document = await pdfium.PdfDocument.openFile(
    path,
    passwordProvider: pdfium.createSimplePasswordProvider(password),
  );
  try {
    final texts = <String>[];
    for (final page in document.pages) {
      final text = await page.loadText();
      texts.add((text?.fullText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim());
    }
    return texts;
  } finally {
    await document.dispose();
  }
}

/// Displayed size of every page, rounded to whole points.
Future<List<(int, int)>> readPageSizes(String path, {String? password}) async {
  final document = await pdfium.PdfDocument.openFile(
    path,
    passwordProvider: pdfium.createSimplePasswordProvider(password),
  );
  try {
    return [
      for (final page in document.pages)
        (page.width.round(), page.height.round()),
    ];
  } finally {
    await document.dispose();
  }
}

Future<List<int>> readPageRotations(String path) async {
  final document = await pdfium.PdfDocument.openFile(path);
  try {
    return [for (final page in document.pages) page.rotation.index * 90];
  } finally {
    await document.dispose();
  }
}

int countOccurrences(Uint8List haystack, String needle) {
  final pattern = needle.codeUnits;
  var count = 0;
  outer:
  for (var i = 0; i <= haystack.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (haystack[i + j] != pattern[j]) continue outer;
    }
    count++;
  }
  return count;
}
