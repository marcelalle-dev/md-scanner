import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/shared/services/backup/backup_format.dart';

/// A file to store in the archive under [entry].
class ZipSource {
  const ZipSource({
    required this.path,
    required this.entry,
    this.compress = false,
  });

  /// Absolute path of the file to read.
  final String path;
  final String entry;

  /// Deflate the content. Off for PDF, JPEG, PNG and DOCX files, which are
  /// already compressed: storing them as-is is much faster.
  final bool compress;
}

enum BackupArchiveError { unsafeEntry, unreadable, io }

/// The only error leaving the archive isolates: it carries nothing but
/// codes, so it can always cross the isolate boundary and never holds a path.
class BackupArchiveException implements Exception {
  const BackupArchiveException(this.error, {this.osErrorCode});

  final BackupArchiveError error;
  final int? osErrorCode;

  Failure toFailure({required bool writing}) => switch (error) {
    BackupArchiveError.unsafeEntry => const StorageFailure(
      StorageFailureKind.corrupted,
      debugMessage: 'backup_unsafe_entry',
    ),
    BackupArchiveError.unreadable => const StorageFailure(
      StorageFailureKind.corrupted,
      debugMessage: 'backup_unreadable',
    ),
    BackupArchiveError.io => switch (osErrorCode) {
      // ENOSPC on POSIX, ERROR_DISK_FULL on Windows.
      28 || 112 => const StorageFailure(StorageFailureKind.insufficientSpace),
      _ => StorageFailure(
        writing ? StorageFailureKind.writeError : StorageFailureKind.readError,
        debugMessage: 'backup_io(os=$osErrorCode)',
      ),
    },
  };

  @override
  String toString() => 'BackupArchiveException(${error.name})';
}

/// Writes [sources] into a new zip at [zipPath] on a background isolate.
/// Files are streamed one by one: memory use does not depend on their size.
/// [onProgress] receives the fraction of bytes written so far.
Future<void> writeBackupZip({
  required String zipPath,
  required List<ZipSource> sources,
  void Function(double fraction)? onProgress,
}) => _withProgress(
  onProgress,
  (port) => _spawn(() => _writeZip(zipPath, sources, port)),
);

/// Lists the file entries of the zip at [zipPath] with their uncompressed
/// size. Fails with [BackupArchiveError.unsafeEntry] when any entry name
/// could leave an extraction folder, before a single byte is extracted.
Future<Map<String, int>> inspectBackupZip(String zipPath) =>
    _spawn(() => _inspect(zipPath));

/// Extracts the entries named by the keys of [targets] to the absolute paths
/// given as values, on a background isolate, checking sizes and CRC-32.
/// On failure every file written by the call is deleted.
Future<void> extractBackupEntries({
  required String zipPath,
  required Map<String, String> targets,
  void Function(double fraction)? onProgress,
}) => _withProgress(
  onProgress,
  (port) => _spawn(() => _extract(zipPath, targets, port)),
);

/// The closure handed to `Isolate.run` is created by the callers above from
/// top-level functions and plain values only, so nothing unsendable (a
/// database, a UI callback) is ever captured.
Future<T> _spawn<T>(FutureOr<T> Function() job) => Isolate.run(job);

Future<T> _withProgress<T>(
  void Function(double fraction)? onProgress,
  Future<T> Function(SendPort? port) run,
) async {
  if (onProgress == null) return run(null);
  final port = ReceivePort();
  final subscription = port.listen((message) {
    if (message is double) onProgress(message);
  });
  try {
    return await run(port.sendPort);
  } finally {
    await subscription.cancel();
    port.close();
  }
}

Future<void> _writeZip(
  String zipPath,
  List<ZipSource> sources,
  SendPort? progress,
) async {
  try {
    final sizes = [
      for (final source in sources) File(source.path).lengthSync(),
    ];
    final total = sizes.fold(0, (sum, size) => sum + size);
    final encoder = ZipFileEncoder()
      ..create(zipPath, level: ZipFileEncoder.store);
    var written = 0;
    try {
      for (final (index, source) in sources.indexed) {
        await encoder.addFile(
          File(source.path),
          source.entry,
          source.compress ? 6 : ZipFileEncoder.store,
        );
        written += sizes[index];
        progress?.send(total == 0 ? 1.0 : written / total);
      }
    } finally {
      await encoder.close();
    }
  } on FileSystemException catch (error) {
    throw BackupArchiveException(
      BackupArchiveError.io,
      osErrorCode: error.osError?.errorCode,
    );
  }
}

Map<String, int> _inspect(String zipPath) => _reading(zipPath, (archive) {
  final entries = <String, int>{};
  for (final entry in archive) {
    if (!isSafeArchivePath(entry.name) || entry.isSymbolicLink) {
      throw const BackupArchiveException(BackupArchiveError.unsafeEntry);
    }
    if (entry.isFile) entries[entry.name] = entry.size;
  }
  return entries;
});

void _extract(String zipPath, Map<String, String> targets, SendPort? progress) {
  final written = <String>[];
  try {
    _reading(zipPath, (archive) {
      final wanted = [
        for (final entry in archive)
          if (entry.isFile && targets.containsKey(entry.name)) entry,
      ];
      if (wanted.length != targets.length) {
        throw const BackupArchiveException(BackupArchiveError.unreadable);
      }
      final total = wanted.fold(0, (sum, entry) => sum + entry.size);
      var done = 0;
      for (final entry in wanted) {
        final destination = targets[entry.name]!;
        File(destination).parent.createSync(recursive: true);
        written.add(destination);
        final output = OutputFileStream(destination);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        done += entry.size;
        progress?.send(total == 0 ? 1.0 : done / total);
      }
    });
  } on BackupArchiveException {
    for (final path in written) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        continue;
      }
    }
    rethrow;
  }
}

/// Opens the zip strictly (`verify`: structure, sizes and checksums are
/// errors, not warnings) and turns whatever goes wrong into a
/// [BackupArchiveException]: a damaged archive can fail in many ways.
T _reading<T>(String zipPath, T Function(Archive archive) body) {
  InputFileStream? input;
  try {
    input = InputFileStream(zipPath);
    return body(ZipDecoder().decodeStream(input, verify: true));
  } on BackupArchiveException {
    rethrow;
  } on FileSystemException catch (error) {
    throw BackupArchiveException(
      BackupArchiveError.io,
      osErrorCode: error.osError?.errorCode,
    );
  } catch (_) {
    throw const BackupArchiveException(BackupArchiveError.unreadable);
  } finally {
    input?.closeSync();
  }
}
