import 'dart:io';
import 'dart:typed_data';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:pdf_cos/pdf_cos.dart';

/// Sendable arguments of [classifyOpenFailure].
typedef OpenFailureQuery = ({String path, String? password});

/// Explains why the native library refused to open a file.
///
/// PDFium does not report a reliable error code on every platform (on
/// Windows any failure looks like a password error), so the file is parsed
/// again in pure Dart to tell a protected file from a damaged one.
/// Synchronous and potentially heavy: run it in a background isolate.
Failure classifyOpenFailure(OpenFailureQuery query) {
  final password = query.password;
  final passwordGiven = password != null && password.isNotEmpty;
  try {
    final file = File(query.path);
    if (!_startsLikePdf(file)) {
      return const PdfFailure(PdfFailureKind.corrupted);
    }
    final document = CosDocument.open(
      file.readAsBytesSync(),
      password: password ?? '',
    );
    // Parsed and authenticated here although PDFium gave up: either a
    // damaged file the lenient parser recovered, or a protection scheme
    // PDFium does not handle.
    return PdfFailure(
      document.isEncrypted
          ? PdfFailureKind.unsupported
          : PdfFailureKind.corrupted,
    );
  } on CosPasswordException {
    return PdfFailure(
      passwordGiven
          ? PdfFailureKind.wrongPassword
          : PdfFailureKind.passwordRequired,
    );
  } on UnsupportedEncryptionException {
    return const PdfFailure(PdfFailureKind.unsupported);
  } on PathNotFoundException {
    return const StorageFailure(StorageFailureKind.notFound);
  } on FileSystemException {
    return const StorageFailure(StorageFailureKind.readError);
  } on Exception {
    return const PdfFailure(PdfFailureKind.corrupted);
  } on Error catch (error) {
    return PdfFailure(
      PdfFailureKind.corrupted,
      debugMessage: 'classify.${error.runtimeType}',
    );
  }
}

/// The `%PDF-` marker must appear within the first 1024 bytes.
bool _startsLikePdf(File file) {
  final handle = file.openSync();
  final Uint8List head;
  try {
    head = handle.readSync(1024);
  } finally {
    handle.closeSync();
  }
  const marker = [0x25, 0x50, 0x44, 0x46, 0x2D];
  outer:
  for (var i = 0; i + marker.length <= head.length; i++) {
    for (var j = 0; j < marker.length; j++) {
      if (head[i + j] != marker[j]) continue outer;
    }
    return true;
  }
  return false;
}
