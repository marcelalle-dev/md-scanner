import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Logical areas of the private app storage.
enum StorageArea {
  /// Final documents listed in the library.
  documents,

  /// Page images backing a scanned document (kept for later re-editing).
  pages,

  /// Small previews shown in lists and grids.
  thumbnails,

  /// Encrypted files of the vault.
  vault,

  /// Working files of an in-progress scan session (recoverable).
  sessions,

  /// Files produced for a share/export action. Safe to purge.
  exports,

  /// Short-lived working files. Purged at startup.
  temp,
}

/// Single owner of every path inside the app's private storage.
///
/// SQLite stores paths RELATIVE to [root], always with forward slashes
/// (`documents/3f2a….pdf`). The absolute root may change between installs,
/// OS updates or backup restores; relative paths never do.
class FileStorage {
  FileStorage(this.root, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Directory root;
  final Uuid _uuid;

  static const String rootFolderName = 'md_scanner';

  static Future<FileStorage> create() async {
    final base = await getApplicationDocumentsDirectory();
    final storage = FileStorage(Directory(p.join(base.path, rootFolderName)));
    await storage.ensureReady();
    return storage;
  }

  Future<void> ensureReady() async {
    for (final area in StorageArea.values) {
      await Directory(p.join(root.path, area.name)).create(recursive: true);
    }
  }

  /// Resolves a stored relative path. Throws [ArgumentError] when the path
  /// would escape [root] (corrupted database or malicious backup).
  String absolutePath(String relativePath) {
    final resolved = p.normalize(
      p.joinAll([root.path, ...p.posix.split(relativePath)]),
    );
    if (!p.isWithin(root.path, resolved)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'escapes storage root',
      );
    }
    return resolved;
  }

  /// Converts an absolute path located inside [root] to its stored form.
  String relativePath(String absolutePath) {
    final normalized = p.normalize(absolutePath);
    if (!p.isWithin(root.path, normalized)) {
      throw ArgumentError.value(
        absolutePath,
        'absolutePath',
        'outside storage root',
      );
    }
    return p.posix.joinAll(p.split(p.relative(normalized, from: root.path)));
  }

  File file(String relativePath) => File(absolutePath(relativePath));

  Directory directoryOf(StorageArea area) =>
      Directory(p.join(root.path, area.name));

  /// Reserves a unique relative path in [area]. The file is not created.
  String allocate(
    StorageArea area, {
    required String extension,
    String? group,
  }) {
    final ext = extension.startsWith('.') ? extension.substring(1) : extension;
    final name = '${_uuid.v4()}.${ext.toLowerCase()}';
    return group == null
        ? p.posix.join(area.name, name)
        : p.posix.join(area.name, group, name);
  }

  Future<String> writeBytes(
    StorageArea area,
    Uint8List bytes, {
    required String extension,
    String? group,
  }) async {
    final relative = allocate(area, extension: extension, group: group);
    final target = file(relative);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    return relative;
  }

  /// Copies an external file (picker result, camera capture, plugin output)
  /// into [area] and returns its relative path.
  Future<String> importFile(
    String sourceAbsolutePath,
    StorageArea area, {
    String? extension,
    String? group,
  }) async {
    final ext = extension ?? p.extension(sourceAbsolutePath);
    final relative = allocate(
      area,
      extension: ext.isEmpty ? 'bin' : ext,
      group: group,
    );
    final target = file(relative);
    await target.parent.create(recursive: true);
    await File(sourceAbsolutePath).copy(target.path);
    return relative;
  }

  Future<String> copy(String relativePath, StorageArea to, {String? group}) =>
      importFile(absolutePath(relativePath), to, group: group);

  Future<String> move(
    String relativePath,
    StorageArea to, {
    String? group,
  }) async {
    final source = file(relativePath);
    final relative = allocate(
      to,
      extension: p.extension(relativePath),
      group: group,
    );
    final target = file(relative);
    await target.parent.create(recursive: true);
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
    return relative;
  }

  Future<bool> exists(String relativePath) => file(relativePath).exists();

  Future<int> sizeOf(String relativePath) async {
    final target = file(relativePath);
    return await target.exists() ? target.length() : 0;
  }

  /// Deletes a file. Missing files are ignored so deletion is idempotent.
  Future<void> delete(String relativePath) async {
    final target = file(relativePath);
    if (await target.exists()) await target.delete();
  }

  Future<void> deleteGroup(StorageArea area, String group) async {
    final dir = Directory(p.join(root.path, area.name, group));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes files of [area], optionally only those older than [olderThan].
  /// Returns the number of deleted files.
  Future<int> purge(
    StorageArea area, {
    Duration? olderThan,
    DateTime? now,
  }) async {
    final dir = directoryOf(area);
    if (!await dir.exists()) return 0;
    final threshold = olderThan == null
        ? null
        : (now ?? DateTime.now()).subtract(olderThan);
    var deleted = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (threshold != null) {
        final modified = await entity.lastModified();
        if (modified.isAfter(threshold)) continue;
      }
      await entity.delete();
      deleted++;
    }
    return deleted;
  }

  /// Total size in bytes of [area], or of the whole storage when null.
  Future<int> usedBytes([StorageArea? area]) async {
    final dir = area == null ? root : directoryOf(area);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}

/// Overridden in `bootstrap()` (and in tests) with a ready storage.
final fileStorageProvider = Provider<FileStorage>(
  (ref) => throw StateError('fileStorageProvider must be overridden'),
);
