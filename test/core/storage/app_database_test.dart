import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/database/migrations.dart';
import 'package:md_scanner/core/storage/settings_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() async => database = await openTestDatabase());
  tearDown(() => database.close());

  Future<void> insertDocument(String id, {String? folderId}) {
    return database.db.insert('documents', {
      'id': id,
      'name': 'Facture',
      'file_path': 'documents/$id.pdf',
      'file_type': 'pdf',
      'folder_id': folderId,
      'created_at': 1,
      'updated_at': 1,
    });
  }

  test('creates every table required by the specification', () async {
    final rows = await database.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tables = rows.map((row) => row['name']).toSet();

    expect(
      tables,
      containsAll(<String>[
        'documents',
        'document_pages',
        'folders',
        'ocr_results',
        'scan_history',
        'qr_history',
        'favorites',
        'app_settings',
        'subscription_cache',
      ]),
    );
    expect(await database.db.getVersion(), kMigrations.length);
  });

  test('enforces foreign keys', () async {
    expect(
      () => database.db.insert('document_pages', {
        'id': 'p1',
        'document_id': 'missing',
        'page_order': 0,
        'image_path': 'pages/p1.jpg',
        'created_at': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('rejects an unsupported file type', () async {
    expect(
      () => database.db.insert('documents', {
        'id': 'd1',
        'name': 'Archive',
        'file_path': 'documents/d1.zip',
        'file_type': 'zip',
        'created_at': 1,
        'updated_at': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('deleting a document cascades to its pages', () async {
    await insertDocument('d1');
    await database.db.insert('document_pages', {
      'id': 'p1',
      'document_id': 'd1',
      'page_order': 0,
      'image_path': 'pages/p1.jpg',
      'created_at': 1,
    });

    await database.db.delete('documents', where: 'id = ?', whereArgs: ['d1']);

    expect(await database.db.query('document_pages'), isEmpty);
  });

  test('deleting a folder keeps its documents at the root', () async {
    await database.db.insert('folders', {
      'id': 'f1',
      'name': 'Administratif',
      'created_at': 1,
      'updated_at': 1,
    });
    await insertDocument('d1', folderId: 'f1');

    await database.db.delete('folders', where: 'id = ?', whereArgs: ['f1']);

    final document = (await database.db.query('documents')).single;
    expect(document['folder_id'], isNull);
  });

  test('favorites table keeps documents.is_favorite in sync', () async {
    await insertDocument('d1');

    await database.db.insert('favorites', {
      'id': 'fav1',
      'document_id': 'd1',
      'created_at': 1,
    });
    expect((await database.db.query('documents')).single['is_favorite'], 1);

    await database.db.delete('favorites');
    expect((await database.db.query('documents')).single['is_favorite'], 0);
  });

  test(
    'folder names are unique within the same parent, ignoring case',
    () async {
      Future<void> insertFolder(String id, String name) => database.db.insert(
        'folders',
        {'id': id, 'name': name, 'created_at': 1, 'updated_at': 1},
      );

      await insertFolder('f1', 'Factures');

      expect(
        () => insertFolder('f2', 'factures'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test('settings store round-trips values', () async {
    final store = SettingsStore(database.db);

    expect(await store.read('app.locale'), isNull);
    await store.write('app.locale', 'fr');
    await store.write('app.locale', 'en');
    await store.writeBool('app.onboarding_completed', value: true);
    await store.writeInt('security.auto_lock_seconds', 30);

    expect(await store.read('app.locale'), 'en');
    expect(await store.readBool('app.onboarding_completed'), isTrue);
    expect(await store.readInt('security.auto_lock_seconds'), 30);
    expect(await store.readAll(), hasLength(3));

    await store.remove('app.locale');
    expect(await store.read('app.locale'), isNull);
  });
}
