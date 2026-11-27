import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/app.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/storage/settings_store.dart';
import 'package:md_scanner/features/document_scanner/data/plugin_document_capture.dart';
import 'package:md_scanner/features/document_scanner/domain/document_capture.dart';
import 'package:md_scanner/features/image_editor/data/isolate_image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/ocr/data/mlkit_text_recognition.dart';
import 'package:md_scanner/features/ocr/domain/text_recognition.dart';
import 'package:md_scanner/features/pdf_tools/data/pdf_engine_providers.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:md_scanner/shared/services/storage_maintenance.dart';

/// Opens the local stores, wires the engines and starts the app.
///
/// Everything needed before the first frame (database, file storage, saved
/// theme and language) is loaded here so the UI never flashes a wrong state.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicense();

  final logger = AppLogger();
  final database = await AppDatabase.open();
  final storage = await FileStorage.create();
  final settings = AppSettings.fromMap(
    await SettingsStore(database.db).readAll(),
  );

  final container = ProviderContainer(
    overrides: [
      appLoggerProvider.overrideWithValue(logger),
      appDatabaseProvider.overrideWithValue(database),
      fileStorageProvider.overrideWithValue(storage),
      initialAppSettingsProvider.overrideWithValue(settings),
      documentRepositoryProvider.overrideWith(
        (ref) => ref.watch(sqliteDocumentRepositoryProvider),
      ),
      ocrTextRepositoryProvider.overrideWith(
        (ref) => ref.watch(sqliteOcrTextRepositoryProvider),
      ),
      imageProcessorProvider.overrideWith(
        (ref) => IsolateImageProcessor(logger: ref.watch(appLoggerProvider)),
      ),
      documentCaptureProvider.overrideWith((ref) => PluginDocumentCapture()),
      textRecognitionServiceProvider.overrideWith((ref) {
        final service = MlKitTextRecognitionService();
        ref.onDispose(service.dispose);
        return service;
      }),
      pdfEngineOverride(),
    ],
  );

  // Housekeeping must never delay or break startup.
  unawaited(container.read(storageMaintenanceProvider).runStartupCleanup());

  FlutterError.onError = (details) {
    logger.error('app.flutter_error');
    if (kDebugMode) FlutterError.presentError(details);
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MdScannerApp(),
    ),
  );
}

/// Inter is distributed under the SIL Open Font License, which requires the
/// license text to ship with the font: it is shown in the licenses page.
void _registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/fonts/Inter-LICENSE.txt',
    );
    yield LicenseEntryWithLineBreaks(['Inter'], license);
  });
}
