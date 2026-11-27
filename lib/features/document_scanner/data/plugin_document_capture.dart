import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/document_scanner/domain/document_capture.dart';

class PluginDocumentCapture implements DocumentCapture {
  PluginDocumentCapture({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Result<List<String>>> scanWithCamera({required int pageLimit}) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        mode: ScannerMode.full,
        pageLimit: pageLimit,
        isGalleryImport: false,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      if (images.isEmpty) return const Err(CancelledFailure());
      return Success([for (final uri in images) _toPath(uri)]);
    } on PlatformException catch (error) {
      final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (message.contains('cancel')) return const Err(CancelledFailure());
      return Err(
        ScanFailure(
          ScanFailureKind.scannerUnavailable,
          debugMessage: error.code,
        ),
      );
    } on MissingPluginException {
      return const Err(ScanFailure(ScanFailureKind.scannerUnavailable));
    } finally {
      await scanner.close();
    }
  }

  @override
  Future<Result<List<String>>> pickFromGallery() async {
    try {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty) return const Err(CancelledFailure());
      return Success([for (final file in files) file.path]);
    } on PlatformException catch (error) {
      return Err(
        PermissionFailure(AppPermission.photos, debugMessage: error.code),
      );
    } on MissingPluginException {
      return const Err(ScanFailure(ScanFailureKind.scannerUnavailable));
    }
  }

  /// The scanner returns `file://` URIs on Android.
  String _toPath(String value) =>
      value.startsWith('file:') ? Uri.parse(value).toFilePath() : value;
}
