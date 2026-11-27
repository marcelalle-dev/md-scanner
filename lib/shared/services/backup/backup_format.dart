import 'dart:convert';

import 'package:equatable/equatable.dart';

/// How a backup meets the library already on the device.
enum RestoreMode {
  /// Adds what is missing; a document whose id already exists is skipped.
  merge,

  /// The exportable library (documents outside the vault, folders, tags)
  /// becomes the backup's content. Vault documents stay: no backup holds them.
  replace,
}

/// Layout of a backup archive, format version 1:
///
/// ```
/// manifest.json
/// metadata/<table>.jsonl        one JSON object (a row) per line
/// files/<stored relative path>  the bytes of documents, thumbnails, pages
/// ```
abstract final class BackupFormat {
  static const int version = 1;
  static const String appId = 'md_scanner';
  static const String manifestEntry = 'manifest.json';
  static const String filesPrefix = 'files/';

  static const String folders = 'folders';
  static const String tags = 'tags';
  static const String documents = 'documents';
  static const String pages = 'document_pages';
  static const String documentTags = 'document_tags';
  static const String ocrResults = 'ocr_results';
  static const String favorites = 'favorites';

  static const List<String> tables = [
    folders,
    tags,
    documents,
    pages,
    documentTags,
    ocrResults,
    favorites,
  ];

  static String tableEntry(String table) => 'metadata/$table.jsonl';

  static String fileEntry(String relativePath) => '$filesPrefix$relativePath';
}

/// True when [name] is a plain relative path with forward slashes: no drive
/// or scheme, no leading slash, no backslash, no `.`/`..`/empty segment and
/// no control character. Such a name cannot leave the folder it is resolved
/// in (zip-slip). A single trailing slash (directory entry) is accepted.
bool isSafeArchivePath(String name) {
  final path = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
  if (path.isEmpty || path.length > 1024) return false;
  if (path.startsWith('/') || path.contains(r'\') || path.contains(':')) {
    return false;
  }
  if (path.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) return false;
  return path
      .split('/')
      .every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

/// Thrown while reading a backup whose content cannot be trusted or parsed.
class BackupFormatException implements Exception {
  const BackupFormatException(this.reason);

  /// Stable technical code (`manifest_invalid`), never a value of the backup.
  final String reason;

  @override
  String toString() => 'BackupFormatException($reason)';
}

class BackupManifest extends Equatable {
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.counts,
    required this.files,
    required this.skippedVaultDocuments,
  });

  /// Parses a `manifest.json`. Throws [BackupFormatException] when a field is
  /// missing or mistyped; version checks are left to the caller.
  factory BackupManifest.decode(String source) {
    const invalid = BackupFormatException('manifest_invalid');
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      throw invalid;
    }
    if (json case {
      'app': BackupFormat.appId,
      'formatVersion': final int formatVersion,
      'schemaVersion': final int schemaVersion,
      'createdAt': final String createdAtText,
      'counts': final Map<String, Object?> rawCounts,
    }) {
      final createdAt = DateTime.tryParse(createdAtText);
      final counts = <String, int>{};
      for (final key in [...BackupFormat.tables, 'files']) {
        final count = rawCounts[key];
        if (count is! int || count < 0) throw invalid;
        counts[key] = count;
      }
      final skipped = json['skippedVaultDocuments'];
      if (createdAt == null || (skipped != null && skipped is! int)) {
        throw invalid;
      }
      return BackupManifest(
        formatVersion: formatVersion,
        schemaVersion: schemaVersion,
        createdAt: createdAt.toUtc(),
        files: counts.remove('files')!,
        counts: counts,
        skippedVaultDocuments: skipped is int ? skipped : 0,
      );
    }
    throw invalid;
  }

  final int formatVersion;

  /// Version of the SQLite schema the rows were read from.
  final int schemaVersion;
  final DateTime createdAt;

  /// Number of rows per exported table.
  final Map<String, int> counts;

  /// Number of entries under `files/`.
  final int files;

  /// Vault documents left out: their key never leaves the device.
  final int skippedVaultDocuments;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'app': BackupFormat.appId,
    'formatVersion': formatVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'counts': {...counts, 'files': files},
    'skippedVaultDocuments': skippedVaultDocuments,
  });

  @override
  List<Object?> get props => [
    formatVersion,
    schemaVersion,
    createdAt,
    counts,
    files,
    skippedVaultDocuments,
  ];
}

/// Outcome of an export.
class BackupSummary extends Equatable {
  const BackupSummary({
    required this.documents,
    required this.folders,
    required this.tags,
    required this.files,
    required this.archiveBytes,
    required this.skippedVaultDocuments,
    required this.skippedMissingFiles,
  });

  final int documents;
  final int folders;
  final int tags;

  /// Files stored in the archive (documents, thumbnails, page images).
  final int files;
  final int archiveBytes;

  /// Vault documents are never exported: their key cannot leave the device.
  final int skippedVaultDocuments;

  /// Documents left out because their file was missing from storage.
  final int skippedMissingFiles;

  @override
  List<Object?> get props => [
    documents,
    folders,
    tags,
    files,
    archiveBytes,
    skippedVaultDocuments,
    skippedMissingFiles,
  ];
}

/// Outcome of a restore.
class RestoreSummary extends Equatable {
  const RestoreSummary({
    required this.mode,
    required this.documentsImported,
    required this.documentsSkipped,
    required this.foldersImported,
    required this.tagsImported,
    required this.filesRestored,
  });

  final RestoreMode mode;
  final int documentsImported;

  /// Documents of the backup whose id already existed on the device.
  final int documentsSkipped;

  /// Folders created; a folder matching an existing one is reused instead.
  final int foldersImported;
  final int tagsImported;
  final int filesRestored;

  @override
  List<Object?> get props => [
    mode,
    documentsImported,
    documentsSkipped,
    foldersImported,
    tagsImported,
    filesRestored,
  ];
}
