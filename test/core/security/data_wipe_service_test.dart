import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/security/data_wipe_service.dart';
import 'package:md_scanner/core/security/pin_service.dart';
import 'package:md_scanner/core/security/secure_key_store.dart';
import 'package:md_scanner/core/security/vault_service.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/storage/settings_store.dart';
import 'package:md_scanner/features/qr_scanner/data/code_history_repository.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/sqlite_document_repository.dart';

import '../../helpers/test_database.dart';

class _MemoryKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  late AppDatabase database;
  late FileStorage storage;
  late SqliteDocumentRepository documents;
  late _MemoryKeyStore keys;

  setUp(() async {
    database = await openTestDatabase();
    storage = await createTestStorage();
    documents = SqliteDocumentRepository(db: database.db, storage: storage);
    keys = _MemoryKeyStore();
  });

  tearDown(() async {
    await documents.dispose();
    await database.close();
    await storage.root.delete(recursive: true);
  });

  Future<DocumentEntity> register(String name) async {
    final path = await storage.writeBytes(
      StorageArea.documents,
      Uint8List.fromList(List.filled(64, 7)),
      extension: 'pdf',
    );
    return (await documents.register(
      NewDocument(
        name: name,
        filePath: path,
        fileType: DocumentFileType.pdf,
        source: DocumentSource.scan,
      ),
    )).valueOrNull!;
  }

  test('erases documents, vault, histories, settings and secrets', () async {
    // A library document with a folder, a tag and saved text.
    final folder = (await documents.createFolder('Banque')).valueOrNull!;
    final kept = await register('Relevé');
    await documents.moveToFolder([kept.id], folder.id);
    await documents.setTags(kept.id, ['2026']);
    await documents.setFavorite(kept.id, favorite: true);

    // A document in the vault, a PIN, histories, preferences, caches.
    final vault = VaultService(
      keyStore: keys,
      storage: storage,
      documents: documents,
    );
    await vault.moveToVault(await register('Passeport'));
    await PinService(
      keys,
      parameters: const PinHashParameters(memoryKib: 64, iterations: 1),
    ).setPin('4821');
    final history = CodeHistoryRepository(database.db);
    await history.add(
      content: 'https://example.org',
      format: 'QR Code',
      kind: CodeHistoryKind.scanned,
    );
    await history.dispose();
    await SettingsStore(database.db).write('app.theme_mode', 'dark');
    await database.db.insert('ai_usage', {
      'feature': 'summary',
      'created_at': 1,
    });
    await database.db.insert('subscription_cache', {
      'product_id': 'md_scanner_premium_yearly',
      'state': 'active',
      'verification_source': 'playStore',
      'last_verified_at': 1,
    });
    await storage.writeBytes(
      StorageArea.temp,
      Uint8List.fromList([1, 2, 3]),
      extension: 'tmp',
    );
    expect(await storage.usedBytes(), greaterThan(0));
    expect(keys.values, isNotEmpty);

    final result = await DataWipeService(
      database: database.db,
      documents: documents,
      keyStore: keys,
    ).wipeEverything();

    expect(result.isSuccess, isTrue);
    expect(await storage.usedBytes(), 0);
    expect(keys.values, isEmpty);
    for (final table in [
      'documents',
      'document_pages',
      'folders',
      'tags',
      'document_tags',
      'favorites',
      'ocr_results',
      'qr_history',
      'scan_history',
      'scan_sessions',
      'ai_usage',
      'subscription_cache',
      'app_settings',
    ]) {
      expect(await database.db.query(table), isEmpty, reason: table);
    }
    // The storage areas still exist, so the app keeps working afterwards.
    for (final area in StorageArea.values) {
      expect(
        await storage.directoryOf(area).exists(),
        isTrue,
        reason: area.name,
      );
    }
    expect((await register('Nouveau')).name, 'Nouveau');
  });

  test('wiping an empty app succeeds', () async {
    final result = await DataWipeService(
      database: database.db,
      documents: documents,
      keyStore: keys,
    ).wipeEverything();

    expect(result.isSuccess, isTrue);
  });
}
