import 'dart:convert';
import 'dart:io';

import 'package:md_scanner/shared/services/backup/backup_format.dart';

const BackupFormatException kInvalidBackupRow = BackupFormatException(
  'row_invalid',
);

/// Reads a `.jsonl` metadata file row by row, so a large table (OCR text)
/// is never decoded in one piece.
Stream<Map<String, Object?>> readBackupRows(File file) async* {
  final lines = file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    if (line.isEmpty) continue;
    final Object? row;
    try {
      row = jsonDecode(line);
    } on FormatException {
      throw kInvalidBackupRow;
    }
    if (row is! Map<String, Object?>) throw kInvalidBackupRow;
    yield row;
  }
}

/// Typed access to a column of an untrusted row: a missing or mistyped value
/// invalidates the backup instead of reaching SQLite.
T backupField<T>(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is T) return value;
  throw kInvalidBackupRow;
}

/// What a restore is going to write, decided before any change is made.
///
/// Rows are already validated and point at freshly allocated storage paths;
/// only `folder_id` and `tag_id` still hold ids of the backup, resolved while
/// the rows are written.
class ImportPlan {
  ImportPlan({
    required this.mode,
    required this.manifest,
    required this.ocrFile,
  });

  final RestoreMode mode;
  final BackupManifest manifest;

  /// Streamed while writing: the only table that can be large.
  final File ocrFile;

  final List<Map<String, Object?>> folders = [];

  /// Tags of the backup by id; created on the device only when a restored
  /// document uses them.
  final Map<String, Map<String, Object?>> tags = {};
  final List<Map<String, Object?>> documents = [];
  final List<Map<String, Object?>> pages = [];
  final List<Map<String, Object?>> documentTags = [];
  final List<Map<String, Object?>> favorites = [];

  /// Ids of the documents that will be inserted.
  final Set<String> importedIds = {};

  /// Documents of the backup left out because their id exists on the device.
  int skippedDocuments = 0;

  /// Archive entry name -> absolute destination of the extracted file.
  final Map<String, String> targets = {};

  /// Relative storage paths of the destinations, to undo a failed restore.
  final List<String> newFiles = [];
}

/// What writing an [ImportPlan] changed.
class ImportOutcome {
  const ImportOutcome({
    required this.foldersCreated,
    required this.tagsCreated,
    required this.obsoleteFiles,
  });

  final int foldersCreated;
  final int tagsCreated;

  /// Files of the documents a `replace` restore removed, to delete once the
  /// transaction is committed.
  final Set<String> obsoleteFiles;
}
