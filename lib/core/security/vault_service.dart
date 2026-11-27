import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/security/file_cipher.dart';
import 'package:md_scanner/core/security/secure_key_store.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Biometric prompt of the system, hidden behind an interface for tests.
abstract interface class BiometricAuthenticator {
  /// True when the device has biometrics enrolled and usable.
  Future<bool> get isAvailable;

  Future<Result<void>> authenticate(String reason);
}

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> get isAvailable async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Result<void>> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
      return ok
          ? const Success(null)
          : const Err(SecurityFailure(SecurityFailureKind.biometricFailed));
    } on LocalAuthException catch (error) {
      return Err(switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          const CancelledFailure(),
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet => const SecurityFailure(
          SecurityFailureKind.biometricNotEnrolled,
        ),
        LocalAuthExceptionCode.noBiometricHardware => const SecurityFailure(
          SecurityFailureKind.biometricUnavailable,
        ),
        _ => SecurityFailure(
          SecurityFailureKind.biometricFailed,
          debugMessage: error.code.name,
        ),
      });
    } on MissingPluginException {
      return const Err(
        SecurityFailure(SecurityFailureKind.biometricUnavailable),
      );
    }
  }
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalAuthBiometricAuthenticator(),
);

/// Encrypts documents into the vault and gives temporary clear copies back.
///
/// The data key is random, generated once, and kept in the secure key store
/// (wrapped by the Android Keystore). It is deliberately NOT derived from the
/// PIN: changing the PIN never re-encrypts files. The PIN gates access in the
/// app; the Keystore protects the key at rest.
class VaultService {
  VaultService({
    required this._keyStore,
    required this._storage,
    required this._documents,
    FileCipher? cipher,
    this._logger,
    Random? random,
  }) : _cipher = cipher ?? FileCipher(),
       _random = random ?? Random.secure();

  final SecureKeyStore _keyStore;
  final FileStorage _storage;
  final DocumentRepository _documents;
  final FileCipher _cipher;
  final AppLogger? _logger;
  final Random _random;

  static const String _keyName = 'vault.data_key.v1';
  static const String _viewFolder = 'vault_view';

  Future<List<int>> _key({required bool create}) async {
    final stored = await _keyStore.read(_keyName);
    if (stored != null) return base64Decode(stored);
    if (!create) {
      throw const FailureException(
        SecurityFailure(SecurityFailureKind.keyUnavailable),
      );
    }
    final key = List<int>.generate(32, (_) => _random.nextInt(256));
    await _keyStore.write(_keyName, base64Encode(key));
    return key;
  }

  /// Encrypts the document into the vault area, then deletes the clear file
  /// and its thumbnail. The document leaves the library listing.
  Future<Result<DocumentEntity>> moveToVault(
    DocumentEntity document, {
    void Function(double fraction)? onProgress,
  }) async {
    if (document.isInVault) return Success(document);
    final target = _storage.allocate(StorageArea.vault, extension: 'enc');
    final result = await guard(() async {
      final key = await _key(create: true);
      _unwrap(
        await _cipher.encryptFile(
          sourcePath: _storage.absolutePath(document.filePath),
          destinationPath: _storage.absolutePath(target),
          key: key,
          onProgress: onProgress,
        ),
      );
      final updated = _unwrap(
        await _documents.updateVaultState(
          document.id,
          filePath: target,
          isInVault: true,
          isEncrypted: true,
        ),
      );
      await _storage.delete(document.filePath);
      final thumbnail = document.thumbnailPath;
      if (thumbnail != null) await _storage.delete(thumbnail);
      _logger?.info('vault.document_added');
      return updated;
    });
    if (result.isFailure) await _storage.delete(target);
    return result;
  }

  /// Decrypts the document back into the library.
  Future<Result<DocumentEntity>> removeFromVault(
    DocumentEntity document, {
    void Function(double fraction)? onProgress,
  }) async {
    if (!document.isInVault) return Success(document);
    final target = _storage.allocate(
      StorageArea.documents,
      extension: document.fileType.extension,
    );
    final result = await guard(() async {
      _unwrap(
        await _cipher.decryptFile(
          sourcePath: _storage.absolutePath(document.filePath),
          destinationPath: _storage.absolutePath(target),
          key: await _key(create: false),
          onProgress: onProgress,
        ),
      );
      final updated = _unwrap(
        await _documents.updateVaultState(
          document.id,
          filePath: target,
          isInVault: false,
          isEncrypted: false,
        ),
      );
      await _storage.delete(document.filePath);
      _logger?.info('vault.document_removed');
      return updated;
    });
    if (result.isFailure) await _storage.delete(target);
    return result;
  }

  /// Decrypts a vault document to a temporary file for viewing and returns
  /// its absolute path. [purgeDecrypted] removes these copies.
  Future<Result<String>> openDecrypted(DocumentEntity document) =>
      guard(() async {
        final folder = Directory(
          p.join(_storage.directoryOf(StorageArea.temp).path, _viewFolder),
        );
        await folder.create(recursive: true);
        final target = p.join(
          folder.path,
          '${const Uuid().v4()}.${document.fileType.extension}',
        );
        _unwrap(
          await _cipher.decryptFile(
            sourcePath: _storage.absolutePath(document.filePath),
            destinationPath: target,
            key: await _key(create: false),
          ),
        );
        return target;
      });

  /// Deletes every temporary clear copy. Called whenever the vault locks.
  Future<void> purgeDecrypted() async {
    final folder = Directory(
      p.join(_storage.directoryOf(StorageArea.temp).path, _viewFolder),
    );
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  T _unwrap<T>(Result<T> result) => switch (result) {
    Success<T>(:final value) => value,
    Err<T>(:final failure) => throw FailureException(failure),
  };
}

final vaultServiceProvider = Provider<VaultService>(
  (ref) => VaultService(
    keyStore: ref.watch(secureKeyStoreProvider),
    storage: ref.watch(fileStorageProvider),
    documents: ref.watch(documentRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
