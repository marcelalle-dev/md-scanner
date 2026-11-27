import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:path/path.dart' as p;

import '../../helpers/test_database.dart';

void main() {
  late FileStorage storage;

  setUp(() async => storage = await createTestStorage());
  tearDown(() => storage.root.delete(recursive: true));

  test('creates one directory per storage area', () async {
    for (final area in StorageArea.values) {
      expect(
        await storage.directoryOf(area).exists(),
        isTrue,
        reason: area.name,
      );
    }
  });

  test(
    'stored paths are relative, use forward slashes and round-trip',
    () async {
      final relative = await storage.writeBytes(
        StorageArea.documents,
        Uint8List.fromList([1, 2, 3]),
        extension: '.PDF',
      );

      expect(relative, startsWith('documents/'));
      expect(relative, endsWith('.pdf'));
      expect(relative, isNot(contains(r'\')));
      expect(storage.relativePath(storage.absolutePath(relative)), relative);
      expect(await storage.sizeOf(relative), 3);
    },
  );

  test('a stored path stays valid when the storage root moves', () async {
    final relative = await storage.writeBytes(
      StorageArea.documents,
      Uint8List.fromList([7]),
      extension: 'txt',
    );
    final movedRoot = Directory('${storage.root.path}_moved');
    await storage.root.rename(movedRoot.path);
    final moved = FileStorage(movedRoot);

    expect(await moved.file(relative).readAsBytes(), [7]);

    await movedRoot.rename(storage.root.path);
  });

  test('rejects paths escaping the storage root', () {
    expect(() => storage.absolutePath('../outside.pdf'), throwsArgumentError);
    expect(
      () => storage.absolutePath('documents/../../outside.pdf'),
      throwsArgumentError,
    );
    expect(
      () => storage.relativePath(p.join(storage.root.parent.path, 'x.pdf')),
      throwsArgumentError,
    );
  });

  test('imports an external file and keeps its extension', () async {
    final external = File(p.join(storage.root.parent.path, 'scan_source.JPG'));
    await external.writeAsBytes([9, 9]);
    addTearDown(external.delete);

    final relative = await storage.importFile(external.path, StorageArea.pages);

    expect(relative, matches(RegExp(r'^pages/[0-9a-f-]+\.jpg$')));
    expect(await storage.file(relative).readAsBytes(), [9, 9]);
    expect(await external.exists(), isTrue);
  });

  test('move relocates the file to another area', () async {
    final source = await storage.writeBytes(
      StorageArea.documents,
      Uint8List.fromList([4, 2]),
      extension: 'pdf',
    );

    final moved = await storage.move(source, StorageArea.vault);

    expect(moved, startsWith('vault/'));
    expect(await storage.exists(source), isFalse);
    expect(await storage.file(moved).readAsBytes(), [4, 2]);
  });

  test('delete is idempotent', () async {
    final relative = await storage.writeBytes(
      StorageArea.temp,
      Uint8List.fromList([1]),
      extension: 'bin',
    );

    await storage.delete(relative);
    await storage.delete(relative);

    expect(await storage.exists(relative), isFalse);
  });

  test('purge only removes files older than the threshold', () async {
    final old = await storage.writeBytes(
      StorageArea.temp,
      Uint8List.fromList([1]),
      extension: 'bin',
    );
    final recent = await storage.writeBytes(
      StorageArea.temp,
      Uint8List.fromList([2]),
      extension: 'bin',
    );
    await storage
        .file(old)
        .setLastModified(DateTime.now().subtract(const Duration(days: 3)));

    final deleted = await storage.purge(
      StorageArea.temp,
      olderThan: const Duration(days: 1),
    );

    expect(deleted, 1);
    expect(await storage.exists(old), isFalse);
    expect(await storage.exists(recent), isTrue);
  });

  test('grouped files can be deleted together', () async {
    final first = await storage.writeBytes(
      StorageArea.sessions,
      Uint8List.fromList([1]),
      extension: 'jpg',
      group: 'session-a',
    );
    await storage.writeBytes(
      StorageArea.sessions,
      Uint8List.fromList([2, 3]),
      extension: 'jpg',
      group: 'session-a',
    );

    expect(first, startsWith('sessions/session-a/'));
    expect(await storage.usedBytes(StorageArea.sessions), 3);

    await storage.deleteGroup(StorageArea.sessions, 'session-a');

    expect(await storage.usedBytes(StorageArea.sessions), 0);
  });
}
