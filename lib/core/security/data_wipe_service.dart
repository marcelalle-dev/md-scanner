import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/security/secure_key_store.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:sqflite/sqflite.dart';

/// Erases everything the app stored on the device: documents and their
/// files (vault included), histories, caches, preferences, the PIN and the
/// vault key.
///
/// A Premium purchase is not affected: it belongs to the Google account and
/// is checked again with Google Play at the next start.
class DataWipeService {
  DataWipeService({
    required Database database,
    required this._documents,
    required this._keyStore,
    this._logger,
  }) : _db = database;

  final Database _db;
  final DocumentRepository _documents;
  final SecureKeyStore _keyStore;
  final AppLogger? _logger;

  /// Tables that are not owned by the document repository.
  static const List<String> _tables = [
    'qr_history',
    'scan_history',
    'scan_sessions',
    'ai_usage',
    'subscription_cache',
    'app_settings',
  ];

  Future<Result<void>> wipeEverything() => guard(() async {
    // Rows and every storage area (documents, pages, thumbnails, vault,
    // sessions, exports, temporary files).
    final wiped = await _documents.wipeAll();
    if (wiped case Err(:final failure)) throw FailureException(failure);
    await _db.transaction<void>((txn) async {
      for (final table in _tables) {
        await txn.delete(table);
      }
    });
    // Without its key, any encrypted remnant is unreadable for good.
    await _keyStore.deleteAll();
    _logger?.clear();
  });
}

final dataWipeServiceProvider = Provider<DataWipeService>(
  (ref) => DataWipeService(
    database: ref.watch(databaseProvider),
    documents: ref.watch(documentRepositoryProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
