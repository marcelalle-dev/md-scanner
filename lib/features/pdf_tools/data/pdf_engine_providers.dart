import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_engine_impl.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

/// Production binding of [pdfEngineProvider], to list in the overrides of
/// the root `ProviderScope` after `fileStorageProvider`.
///
/// PDFium is loaded by pdfrx's Flutter initializer the first time the engine
/// needs it; working copies go to the `temp` storage area.
Override pdfEngineOverride() => pdfEngineProvider.overrideWith((ref) {
  final storage = ref.watch(fileStorageProvider);
  return PdfEngineImpl(
    initializePdfium: pdfrxFlutterInitialize,
    tempDirectory: () => storage.directoryOf(StorageArea.temp),
    logger: ref.watch(appLoggerProvider),
  );
});
