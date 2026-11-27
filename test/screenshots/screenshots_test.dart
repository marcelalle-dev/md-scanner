// Renders real screens of the app to PNG files in docs/screenshots.
//
// These are host renderings of the actual widgets (real theme, fonts, texts
// and seeded data), not captures from a phone. Skipped unless requested:
//
//   SCREENSHOTS=1 flutter test test/screenshots
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/app.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/security/secure_key_store.dart';
import 'package:md_scanner/core/security/vault_service.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/features/pdf_tools/presentation/page_placement.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:md_scanner/shared/repositories/sqlite_document_repository.dart';

import '../helpers/test_database.dart';

class _MemoryKeyStore implements SecureKeyStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}

class _NoBiometrics implements BiometricAuthenticator {
  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<Result<void>> authenticate(String reason) async => const Success(null);
}

final GlobalKey _captureKey = GlobalKey();
const double _pixelRatio = 2;
const Size _phone = Size(412, 892);

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
  }
  await inter.load();
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/'
    'material_fonts/materialicons-regular.otf',
  );
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await loader.load();
}

void main() {
  final enabled = Platform.environment['SCREENSHOTS'] == '1';
  late AppDatabase database;
  late FileStorage storage;

  setUpAll(() async {
    if (enabled) await _loadFonts();
  });

  setUp(() async {
    database = await openTestDatabase();
    storage = await createTestStorage();
  });

  tearDown(() async {
    await database.close();
    await storage.root.delete(recursive: true);
  });

  Future<void> seed() async {
    final repository = SqliteDocumentRepository(
      db: database.db,
      storage: storage,
    );
    await repository.createFolder('Administratif');
    await repository.createFolder('Factures');
    Future<DocumentEntity> add(
      String name,
      DocumentFileType type,
      int size, {
      int? pages,
    }) async {
      final path = await storage.writeBytes(
        StorageArea.documents,
        Uint8List(size),
        extension: type.extension,
      );
      return (await repository.register(
        NewDocument(
          name: name,
          filePath: path,
          fileType: type,
          source: DocumentSource.scan,
          pageCount: pages,
        ),
      )).valueOrNull!;
    }

    await add('Notes de réunion', DocumentFileType.txt, 2400);
    await add('Reçu pharmacie', DocumentFileType.jpg, 418000, pages: 1);
    final lease = await add(
      'Contrat de bail',
      DocumentFileType.pdf,
      1840000,
      pages: 6,
    );
    final invoice = await add(
      'Facture électricité',
      DocumentFileType.pdf,
      264000,
      pages: 2,
    );
    await repository.setFavorite(invoice.id, favorite: true);
    await repository.setTags(invoice.id, ['Factures', '2026']);
    await repository.setTags(lease.id, ['Logement']);
    await repository.dispose();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> start(
    WidgetTester tester, {
    bool onboarded = true,
    ThemeMode theme = ThemeMode.light,
  }) async {
    tester.view.physicalSize = _phone * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);
    await tester.runAsync(seed);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            fileStorageProvider.overrideWithValue(storage),
            initialAppSettingsProvider.overrideWithValue(
              AppSettings(
                localeCode: 'fr',
                onboardingCompleted: onboarded,
                themeMode: theme,
              ),
            ),
            documentRepositoryProvider.overrideWith(
              (ref) => ref.watch(sqliteDocumentRepositoryProvider),
            ),
            secureKeyStoreProvider.overrideWithValue(_MemoryKeyStore()),
            biometricAuthenticatorProvider.overrideWithValue(_NoBiometrics()),
          ],
          child: const MdScannerApp(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('docs/screenshots/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }

  Future<void> open(WidgetTester tester, String route) async {
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    // The pushed route stays open for the capture: its result is not awaited.
    // ignore: unawaited_futures
    router.push(route);
    await settle(tester);
  }

  testWidgets('introduction', (tester) async {
    await start(tester, onboarded: false);
    await shot(tester, '01-introduction');
  }, skip: !enabled);

  testWidgets('main tabs', (tester) async {
    await start(tester);
    await shot(tester, '02-accueil');
    await tab(tester, 'Scanner');
    await shot(tester, '03-scanner');
    await tab(tester, 'Outils');
    await shot(tester, '04-outils');
    await tab(tester, 'Documents');
    await shot(tester, '05-documents');
    await tab(tester, 'Profil');
    await shot(tester, '06-profil');
  }, skip: !enabled);

  testWidgets('QR code generator', (tester) async {
    await start(tester);
    await open(tester, AppRoutes.qrGenerator);
    await tester.enterText(find.byType(TextField).first, 'MD SCANNER');
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await shot(tester, '07-generateur-qr');
  }, skip: !enabled);

  testWidgets('vault', (tester) async {
    await start(tester);
    await open(tester, AppRoutes.vault);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await shot(tester, '08-coffre-fort');
  }, skip: !enabled);

  testWidgets('PDF signature tool', (tester) async {
    await start(tester);
    await open(tester, AppRoutes.pdfTool('sign'));
    await shot(tester, '09-signature-pdf');
  }, skip: !enabled);

  testWidgets('dark theme', (tester) async {
    await start(tester, theme: ThemeMode.dark);
    await tab(tester, 'Documents');
    await shot(tester, '10-documents-sombre');
  }, skip: !enabled);

  test('a signature keeps its proportions and stays on the page', () {
    const a4 = 595 / 842;
    final rect = signatureRect(left: 0.55, top: 0.82, pageAspectRatio: a4);
    expect(rect.width, kSignatureWidthFraction);
    expect(
      (rect.width * 595) / (rect.height * 842),
      closeTo(2.2, 0.001),
      reason: 'same aspect ratio as the drawing pad',
    );

    final clamped = signatureRect(left: 0.95, top: 0.99, pageAspectRatio: a4);
    expect(clamped.left + clamped.width, closeTo(1, 1e-9));
    expect(clamped.top + clamped.height, closeTo(1, 1e-9));
    final origin = signatureRect(left: -0.4, top: -1, pageAspectRatio: a4);
    expect(origin.left, 0);
    expect(origin.top, 0);
  });
}
