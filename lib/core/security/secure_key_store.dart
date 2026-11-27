import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets (PIN hash, vault key) kept encrypted at rest by the
/// platform keystore. Never use the settings table for these.
abstract interface class SecureKeyStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Removes every secret (data wipe).
  Future<void> deleteAll();
}

class FlutterSecureKeyStore implements SecureKeyStore {
  const FlutterSecureKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => const FlutterSecureKeyStore(),
);
