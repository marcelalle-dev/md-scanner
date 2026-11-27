import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/app/app.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool.dart';
import 'package:md_scanner/shared/providers/app_settings.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late FileStorage storage;

  setUp(() async {
    database = await openTestDatabase();
    storage = await createTestStorage();
  });

  tearDown(() async {
    await database.close();
    await storage.root.delete(recursive: true);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(localeCode: 'fr'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          fileStorageProvider.overrideWithValue(storage),
          initialAppSettingsProvider.overrideWithValue(settings),
          documentRepositoryProvider.overrideWith(
            (ref) => ref.watch(sqliteDocumentRepositoryProvider),
          ),
        ],
        child: const MdScannerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts on Home with the five navigation entries', (
    tester,
  ) async {
    await tester.runAsync(() => pumpApp(tester));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in [
      'Accueil',
      'Scanner',
      'Outils',
      'Documents',
      'Profil',
    ]) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text('Documents récents'), findsOneWidget);
  });

  testWidgets('each tab opens its screen', (tester) async {
    await tester.runAsync(() => pumpApp(tester));
    await tester.pumpAndSettle();

    Future<void> open(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open('Scanner');
    expect(find.text('Numériser avec l\'appareil photo'), findsOneWidget);
    expect(find.text('Reçu'), findsOneWidget);

    await open('Outils');
    expect(find.text('Fusionner des PDF'), findsOneWidget);
    expect(find.byType(ListTile), findsAtLeastNWidgets(5));

    await open('Documents');
    expect(find.text('Rechercher par nom'), findsOneWidget);

    await open('Profil');
    expect(find.text('Apparence'), findsOneWidget);
  });

  testWidgets('the interface follows the saved language', (tester) async {
    await tester.runAsync(
      () => pumpApp(tester, settings: const AppSettings(localeCode: 'en')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent documents'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  test('every PDF tool is reachable by its route id', () {
    for (final tool in PdfTool.values) {
      expect(PdfTool.byId(tool.id), tool);
    }
    expect(PdfTool.byId('unknown'), isNull);
    expect(PdfTool.values.map((t) => t.id).toSet(), hasLength(10));
  });
}
