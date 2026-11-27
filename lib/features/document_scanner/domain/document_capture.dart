import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';

/// Source of page images for a scan session. Hides the device-only plugins
/// (Google document scanner, photo picker) so the session logic is testable.
abstract interface class DocumentCapture {
  /// Opens Google's document scanner, which detects edges, crops and lets the
  /// user review each page. Returns the absolute paths of the captured pages.
  ///
  /// Fails with `ScanFailure(scannerUnavailable)` when the scanner cannot run
  /// on this device, and with `CancelledFailure` when the user backs out.
  Future<Result<List<String>>> scanWithCamera({required int pageLimit});

  /// Lets the user pick photos with the system photo picker (no permission).
  Future<Result<List<String>>> pickFromGallery();
}

/// Bound to the plugin implementation in the data layer.
final documentCaptureProvider = Provider<DocumentCapture>(
  (ref) => throw StateError('documentCaptureProvider must be overridden'),
);
