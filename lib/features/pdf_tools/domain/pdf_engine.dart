import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/domain/page_range.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';

/// Creates, edits, protects and rasterizes PDF files.
///
/// Common contract of every method:
/// - paths are absolute; input files are never modified;
/// - an output is written next to its final path and renamed once complete,
///   so a failure or a cancellation leaves no partial file behind;
/// - page arguments named `pageIndex`/`pages` are 0-based ([PageRange] is
///   the 1-based notation typed by users);
/// - errors come back as `Err`: `StorageFailure(notFound)` for a missing
///   input, `PdfFailure(passwordRequired | wrongPassword)` for a protected
///   file, `PdfFailure(corrupted)` for a damaged one,
///   `PdfFailure(invalidPageRange)` for a page outside the document,
///   `CancelledFailure` when `isCancelled` returned true;
/// - `password` opens a protected input. The output of an editing operation
///   is never protected: call [protect] on it to keep a password.
///
/// Structural operations (merge, split, extract, delete, reorder, rotate)
/// copy page objects as they are: text stays text, vectors stay vectors.
abstract interface class PdfEngine {
  /// Loads the native PDF library. Every method calls it on demand; calling
  /// it at startup only moves the cost away from the first operation.
  /// Fails with `PdfFailure(engineUnavailable)`.
  Future<Result<void>> ensureInitialized();

  /// Reads the page count, page sizes and protection state of a file.
  /// A document without any page fails with `PdfFailure(emptyDocument)`.
  Future<Result<PdfInfo>> inspect(String path, {String? password});

  /// Builds a PDF with one page per image, in order. JPEG files are embedded
  /// as they are (no recompression, EXIF orientation honoured); PNG pixels
  /// are kept lossless with transparency flattened on white; other formats
  /// (WebP, BMP, GIF, TIFF) are re-encoded as JPEG. Images are processed one
  /// at a time. Fails with `ImageFailure` on an unreadable image.
  Future<Result<PdfOutput>> imagesToPdf({
    required List<String> imagePaths,
    required String outputPath,
    PdfPageSetup setup = const PdfPageSetup(),
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  });

  /// Rasterizes one page to an image file. The resolution is [dpi] (150 by
  /// default), lowered when needed so the long edge stays within
  /// [maxLongEdge] pixels and the image within 24 megapixels.
  Future<Result<RenderedPage>> renderPage({
    required String path,
    required int pageIndex,
    required String outputPath,
    int? maxLongEdge,
    double? dpi,
    PdfImageFormat format = PdfImageFormat.jpeg,
    int jpegQuality = 90,
    String? password,
  });

  /// Rasterizes [pages] (every page when null), one at a time, into
  /// `page_0001.jpg`, `page_0002.jpg`… inside [outputDirectory] (numbers are
  /// page positions). Progress is reported after each page.
  Future<Result<List<RenderedPage>>> pdfToImages({
    required String path,
    required String outputDirectory,
    PdfImageFormat format = PdfImageFormat.jpeg,
    double dpi = 150,
    List<int>? pages,
    int jpegQuality = 90,
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  });

  /// Concatenates [inputPaths] in order. [passwords] maps an input path to
  /// the password that opens it.
  Future<Result<PdfOutput>> merge({
    required List<String> inputPaths,
    required String outputPath,
    Map<String, String> passwords = const {},
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  });

  /// Writes one file per range into [outputDirectory], named
  /// `<fileNamePrefix>_001.pdf`, `<fileNamePrefix>_002.pdf`… in range order.
  Future<Result<List<PdfOutput>>> split({
    required String path,
    required String outputDirectory,
    required List<PageRange> ranges,
    String fileNamePrefix = 'part',
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  });

  /// Writes a document made of [pages], in the order given.
  Future<Result<PdfOutput>> extractPages({
    required String path,
    required String outputPath,
    required List<int> pages,
    String? password,
  });

  /// Writes the document without [pages]. Their content is not carried over
  /// to the output. Removing every page fails with
  /// `PdfFailure(emptyDocument)`.
  Future<Result<PdfOutput>> deletePages({
    required String path,
    required String outputPath,
    required Set<int> pages,
    String? password,
  });

  /// Writes the document with its pages in [order], which must list every
  /// page index exactly once.
  Future<Result<PdfOutput>> reorderPages({
    required String path,
    required String outputPath,
    required List<int> order,
    String? password,
  });

  /// Rotates pages by quarter turns: [quarterTurns] maps a page index to a
  /// number of clockwise 90° steps (negative for counter-clockwise), added
  /// to the rotation the page already has.
  Future<Result<PdfOutput>> rotatePages({
    required String path,
    required String outputPath,
    required Map<int, int> quarterTurns,
    String? password,
  });

  /// Shrinks a file. When no smaller file can be produced nothing is written
  /// and the result reports `reduced == false` with the original size.
  /// Re-encoding the images of a long scan takes time: [isCancelled] stops
  /// the work at any moment.
  Future<Result<PdfCompressionResult>> compress({
    required String path,
    required String outputPath,
    required PdfCompressionLevel level,
    String? password,
    PdfCancellationCheck? isCancelled,
  });

  /// Draws [watermark] centred on each selected page.
  Future<Result<PdfOutput>> addWatermark({
    required String path,
    required String outputPath,
    required PdfWatermark watermark,
    String? password,
  });

  Future<Result<PdfOutput>> addPageNumbers({
    required String path,
    required String outputPath,
    PdfPageNumbering numbering = const PdfPageNumbering(),
    String? password,
  });

  /// Draws each of [texts] on its page.
  Future<Result<PdfOutput>> addText({
    required String path,
    required String outputPath,
    required List<PdfTextStamp> texts,
    String? password,
  });

  /// Draws each image of [stamps] on its page, keeping PNG transparency.
  Future<Result<PdfOutput>> stampImage({
    required String path,
    required String outputPath,
    required List<PdfImageStamp> stamps,
    String? password,
  });

  /// Encrypts the document with AES-256 (PDF 2.0 standard security handler,
  /// revision 6). [userPassword] is asked to open the file; [ownerPassword]
  /// defaults to it. Every permission is granted once the file is open.
  ///
  /// Passwords must be 1 to 127 UTF-8 bytes long, otherwise the call fails
  /// with `ValidationFailure('pdf_password_empty' | 'pdf_password_too_long')`.
  /// [currentPassword] opens an input that is already protected.
  Future<Result<PdfOutput>> protect({
    required String path,
    required String outputPath,
    required String userPassword,
    String? ownerPassword,
    String? currentPassword,
  });

  /// Writes an unprotected copy. Succeeds only when [password] (user or
  /// owner) opens the file.
  Future<Result<PdfOutput>> unlock({
    required String path,
    required String outputPath,
    required String password,
  });
}

/// Splitting shortcuts built on [PdfEngine.inspect] and [PdfEngine.split].
extension PdfEngineSplitting on PdfEngine {
  /// Cuts the document into files of [pagesPerFile] pages (the last one may
  /// be shorter).
  Future<Result<List<PdfOutput>>> splitEvery({
    required String path,
    required String outputDirectory,
    required int pagesPerFile,
    String fileNamePrefix = 'part',
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) async {
    if (pagesPerFile < 1) {
      return const Err(PdfFailure(PdfFailureKind.invalidPageRange));
    }
    final info = await inspect(path, password: password);
    return info.andThen(
      (value) => split(
        path: path,
        outputDirectory: outputDirectory,
        ranges: pageRangesEvery(pagesPerFile, value.pageCount),
        fileNamePrefix: fileNamePrefix,
        password: password,
        onProgress: onProgress,
        isCancelled: isCancelled,
      ),
    );
  }

  /// Writes one single-page file per page.
  Future<Result<List<PdfOutput>>> splitIntoSinglePages({
    required String path,
    required String outputDirectory,
    String fileNamePrefix = 'page',
    String? password,
    PdfProgressCallback? onProgress,
    PdfCancellationCheck? isCancelled,
  }) => splitEvery(
    path: path,
    outputDirectory: outputDirectory,
    pagesPerFile: 1,
    fileNamePrefix: fileNamePrefix,
    password: password,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
}

/// Bound in `bootstrap()` with `pdfEngineOverride()` from
/// `features/pdf_tools/data/pdf_engine_providers.dart`; tests override it
/// with a fake or with an engine initialized by `pdfrxInitialize`.
final pdfEngineProvider = Provider<PdfEngine>(
  (ref) => throw StateError('pdfEngineProvider must be overridden'),
);
