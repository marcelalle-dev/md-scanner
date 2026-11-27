import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/security/file_cipher.dart';
import 'package:md_scanner/core/security/pin_service.dart';
import 'package:md_scanner/core/security/secure_key_store.dart';
import 'package:md_scanner/core/security/vault_service.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/sqlite_document_repository.dart';
import 'package:path/path.dart' as p;

import '../../helpers/test_database.dart';

class _MemoryKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Small Argon2 cost so the suite stays fast; the algorithm is the same.
const _fastHash = PinHashParameters(memoryKib: 64, iterations: 1);

void main() {
  group('PinService', () {
    late _MemoryKeyStore store;
    late DateTime now;
    PinService service() =>
        PinService(store, parameters: _fastHash, clock: () => now);

    setUp(() {
      store = _MemoryKeyStore();
      now = DateTime.utc(2026, 11, 27, 12);
    });

    test('accepts the right PIN and never stores it in clear', () async {
      expect(await service().isPinSet, isFalse);
      expect((await service().setPin('482913')).isSuccess, isTrue);

      expect(await service().isPinSet, isTrue);
      expect(store.values.values.join(), isNot(contains('482913')));
      expect((await service().verifyPin('482913')).isSuccess, isTrue);
      expect(
        (await service().verifyPin('000000')).failureOrNull,
        const SecurityFailure(SecurityFailureKind.wrongPin),
      );
    });

    test('rejects a malformed PIN', () async {
      for (final pin in ['123', '123456789', '12a4', '']) {
        expect(
          (await service().setPin(pin)).failureOrNull,
          const ValidationFailure('pin_format'),
          reason: pin,
        );
      }
      expect(await service().isPinSet, isFalse);
    });

    test('verifying without a PIN fails cleanly', () async {
      expect(
        (await service().verifyPin('1234')).failureOrNull,
        const SecurityFailure(SecurityFailureKind.pinNotSet),
      );
    });

    test('locks out after repeated failures, across restarts', () async {
      await service().setPin('1234');
      for (var i = 0; i < PinService.freeAttempts - 1; i++) {
        expect(
          (await service().verifyPin('9999')).failureOrNull,
          const SecurityFailure(SecurityFailureKind.wrongPin),
        );
      }
      final fifth = (await service().verifyPin('9999')).failureOrNull;
      expect(fifth, isA<SecurityFailure>());
      expect((fifth! as SecurityFailure).kind, SecurityFailureKind.lockedOut);
      expect((fifth as SecurityFailure).retryAfter, PinService.firstLockout);

      // A new instance (app restart) is still locked, even for the right PIN.
      final during = (await service().verifyPin('1234')).failureOrNull;
      expect((during! as SecurityFailure).kind, SecurityFailureKind.lockedOut);

      now = now.add(PinService.firstLockout);
      final sixth = (await service().verifyPin('9999')).failureOrNull;
      expect(
        (sixth! as SecurityFailure).retryAfter,
        PinService.firstLockout * 2,
      );

      now = now.add(PinService.firstLockout * 2);
      expect((await service().verifyPin('1234')).isSuccess, isTrue);
      expect(
        (await service().verifyPin('9999')).failureOrNull,
        const SecurityFailure(SecurityFailureKind.wrongPin),
      );
    });

    test('the lock-out delay is capped', () async {
      await service().setPin('1234');
      Duration? last;
      for (var i = 0; i < 20; i++) {
        final failure =
            (await service().verifyPin('9999')).failureOrNull!
                as SecurityFailure;
        last = failure.retryAfter;
        now = now.add(PinService.maxLockout);
      }
      expect(last, PinService.maxLockout);
    });

    test('removing the PIN requires the current PIN', () async {
      await service().setPin('1234');

      expect((await service().removePin('0000')).isFailure, isTrue);
      expect(await service().isPinSet, isTrue);
      expect((await service().removePin('1234')).isSuccess, isTrue);
      expect(await service().isPinSet, isFalse);
    });
  });

  group('FileCipher', () {
    late Directory directory;
    final key = List<int>.generate(32, (i) => i * 7 % 256);
    final cipher = FileCipher(chunkSize: 1024, random: Random(1));

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('md_scanner_cipher_');
    });
    tearDown(() => directory.delete(recursive: true));

    String path(String name) => p.join(directory.path, name);

    Future<Uint8List> roundTrip(Uint8List clear) async {
      await File(path('clear')).writeAsBytes(clear);
      final encrypted = await cipher.encryptFile(
        sourcePath: path('clear'),
        destinationPath: path('sealed'),
        key: key,
      );
      expect(encrypted.isSuccess, isTrue);
      final decrypted = await cipher.decryptFile(
        sourcePath: path('sealed'),
        destinationPath: path('opened'),
        key: key,
      );
      expect(decrypted.isSuccess, isTrue, reason: '${decrypted.failureOrNull}');
      return File(path('opened')).readAsBytes();
    }

    Uint8List bytes(int length) =>
        Uint8List.fromList(List.generate(length, (i) => (i * 31 + 7) % 256));

    test('round-trips files of every boundary size', () async {
      for (final length in [0, 1, 1023, 1024, 1025, 2048, 5000]) {
        expect(
          await roundTrip(bytes(length)),
          bytes(length),
          reason: '$length',
        );
      }
    });

    test('the encrypted file does not contain the plaintext', () async {
      final clear = Uint8List.fromList(
        ('CONFIDENTIEL-PASSEPORT' * 40).codeUnits,
      );
      await roundTrip(clear);
      final sealed = String.fromCharCodes(
        await File(path('sealed')).readAsBytes(),
      );

      expect(sealed, isNot(contains('CONFIDENTIEL')));
      expect(sealed.startsWith('MDSV'), isTrue);
    });

    Future<Failure?> decryptTampered(
      Uint8List Function(Uint8List sealed) tamper, {
      List<int>? withKey,
    }) async {
      await roundTrip(bytes(3000));
      final sealed = await File(path('sealed')).readAsBytes();
      await File(path('sealed')).writeAsBytes(tamper(sealed));
      await File(path('opened')).delete();
      final result = await cipher.decryptFile(
        sourcePath: path('sealed'),
        destinationPath: path('opened'),
        key: withKey ?? key,
      );
      expect(await File(path('opened')).exists(), isFalse);
      expect(await File('${path('opened')}.part').exists(), isFalse);
      return result.failureOrNull;
    }

    const failed = SecurityFailure(SecurityFailureKind.decryptionFailed);

    test('detects a flipped byte', () async {
      expect(await decryptTampered((s) => s..[100] ^= 1), failed);
    });

    test('detects a tampered header', () async {
      expect(await decryptTampered((s) => s..[12] ^= 1), failed);
    });

    test('detects truncation at a chunk boundary', () async {
      expect(
        await decryptTampered((s) => Uint8List.sublistView(s, 0, 17 + 1040)),
        failed,
      );
    });

    test('detects swapped chunks', () async {
      expect(
        await decryptTampered((s) {
          final first = Uint8List.fromList(s.sublist(17, 17 + 1040));
          final second = Uint8List.fromList(s.sublist(17 + 1040, 17 + 2080));
          return s
            ..setAll(17, second)
            ..setAll(17 + 1040, first);
        }),
        failed,
      );
    });

    test('rejects a wrong key', () async {
      expect(
        await decryptTampered((s) => s, withKey: List<int>.filled(32, 9)),
        failed,
      );
    });

    test('rejects a file that is not a vault container', () async {
      expect(
        await decryptTampered((s) => Uint8List.fromList('%PDF-1.7'.codeUnits)),
        failed,
      );
    });
  });

  group('VaultService', () {
    late AppDatabase database;
    late FileStorage storage;
    late SqliteDocumentRepository documents;
    late _MemoryKeyStore keys;
    late VaultService vault;

    setUp(() async {
      database = await openTestDatabase();
      storage = await createTestStorage();
      documents = SqliteDocumentRepository(db: database.db, storage: storage);
      keys = _MemoryKeyStore();
      vault = VaultService(
        keyStore: keys,
        storage: storage,
        documents: documents,
      );
    });

    tearDown(() async {
      await documents.dispose();
      await database.close();
      await storage.root.delete(recursive: true);
    });

    Future<DocumentEntity> register(List<int> content) async {
      final path = await storage.writeBytes(
        StorageArea.documents,
        Uint8List.fromList(content),
        extension: 'pdf',
      );
      final thumbnail = await storage.writeBytes(
        StorageArea.thumbnails,
        Uint8List.fromList([1]),
        extension: 'jpg',
      );
      return (await documents.register(
        NewDocument(
          name: 'Passeport',
          filePath: path,
          fileType: DocumentFileType.pdf,
          source: DocumentSource.scan,
          thumbnailPath: thumbnail,
        ),
      )).valueOrNull!;
    }

    test('moving in encrypts the file and hides it from the library', () async {
      final content = ('SECRET-DOCUMENT' * 20).codeUnits;
      final document = await register(content);

      final moved = (await vault.moveToVault(document)).valueOrNull!;

      expect(moved.isInVault, isTrue);
      expect(moved.isEncrypted, isTrue);
      expect(moved.filePath, startsWith('vault/'));
      expect(await storage.exists(document.filePath), isFalse);
      expect(await storage.exists(document.thumbnailPath!), isFalse);
      final sealed = String.fromCharCodes(
        await storage.file(moved.filePath).readAsBytes(),
      );
      expect(sealed, isNot(contains('SECRET')));
      expect(
        (await documents.query(const DocumentQuery())).valueOrNull,
        isEmpty,
      );
      expect(
        (await documents.query(const DocumentQuery(inVault: true))).valueOrNull,
        hasLength(1),
      );
    });

    test('a decrypted view is identical and purged on lock', () async {
      final content = List<int>.generate(4000, (i) => i % 251);
      final moved = (await vault.moveToVault(
        await register(content),
      )).valueOrNull!;

      final view = (await vault.openDecrypted(moved)).valueOrNull!;
      expect(await File(view).readAsBytes(), content);

      await vault.purgeDecrypted();
      expect(await File(view).exists(), isFalse);
    });

    test('moving out restores the clear file in the library', () async {
      final content = List<int>.generate(2500, (i) => (i * 3) % 256);
      final moved = (await vault.moveToVault(
        await register(content),
      )).valueOrNull!;

      final restored = (await vault.removeFromVault(moved)).valueOrNull!;

      expect(restored.isInVault, isFalse);
      expect(restored.isEncrypted, isFalse);
      expect(await storage.file(restored.filePath).readAsBytes(), content);
      expect(await storage.exists(moved.filePath), isFalse);
      expect(await storage.usedBytes(StorageArea.vault), 0);
    });

    test('without its key a vault document cannot be opened', () async {
      final moved = (await vault.moveToVault(
        await register([1, 2, 3]),
      )).valueOrNull!;
      keys.values.clear();

      final result = await vault.openDecrypted(moved);

      expect(
        result.failureOrNull,
        const SecurityFailure(SecurityFailureKind.keyUnavailable),
      );
    });
  });
}
