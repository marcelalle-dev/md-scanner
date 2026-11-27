import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum CodeHistoryKind { scanned, generated }

class CodeHistoryEntry extends Equatable {
  const CodeHistoryEntry({
    required this.id,
    required this.content,
    required this.format,
    required this.kind,
    required this.date,
  });

  final String id;
  final String content;
  final String format;
  final CodeHistoryKind kind;
  final DateTime date;

  @override
  List<Object?> get props => [id, content, format, kind, date];
}

/// History of scanned and generated codes (table `qr_history`).
class CodeHistoryRepository {
  CodeHistoryRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  static const String _table = 'qr_history';

  Stream<void> get changes => _changes.stream;

  /// Records a code. Scanning the same code twice in a row is stored once.
  Future<Result<void>> add({
    required String content,
    required String format,
    required CodeHistoryKind kind,
  }) => guard(() async {
    final latest = await _db.query(
      _table,
      where: 'kind = ?',
      whereArgs: [kind.name],
      orderBy: 'scanned_at DESC',
      limit: 1,
    );
    if (latest.isNotEmpty &&
        latest.first['content'] == content &&
        latest.first['format'] == format) {
      return;
    }
    await _db.insert(_table, {
      'id': const Uuid().v4(),
      'content': content,
      'format': format,
      'kind': kind.name,
      'scanned_at': _clock().toUtc().millisecondsSinceEpoch,
    });
    _changes.add(null);
  });

  Future<Result<List<CodeHistoryEntry>>> list({CodeHistoryKind? kind}) =>
      guard(() async {
        final rows = await _db.query(
          _table,
          where: kind == null ? null : 'kind = ?',
          whereArgs: kind == null ? null : [kind.name],
          orderBy: 'scanned_at DESC',
          limit: 500,
        );
        return [
          for (final row in rows)
            CodeHistoryEntry(
              id: row['id']! as String,
              content: row['content']! as String,
              format: row['format']! as String,
              kind: CodeHistoryKind.values.byName(row['kind']! as String),
              date: DateTime.fromMillisecondsSinceEpoch(
                row['scanned_at']! as int,
                isUtc: true,
              ),
            ),
        ];
      });

  Future<Result<void>> delete(String id) => guard(() async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  });

  Future<Result<void>> clear() => guard(() async {
    await _db.delete(_table);
    _changes.add(null);
  });

  Future<void> dispose() => _changes.close();
}

final codeHistoryRepositoryProvider = Provider<CodeHistoryRepository>((ref) {
  final repository = CodeHistoryRepository(ref.watch(databaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

/// History entries, refreshed whenever the history changes.
final codeHistoryProvider = FutureProvider.autoDispose
    .family<List<CodeHistoryEntry>, CodeHistoryKind?>((ref, kind) async {
      final repository = ref.watch(codeHistoryRepositoryProvider);
      final subscription = repository.changes.listen(
        (_) => ref.invalidateSelf(),
      );
      ref.onDispose(subscription.cancel);
      final result = await repository.list(kind: kind);
      return switch (result) {
        Success(:final value) => value,
        Err(:final failure) => throw FailureException(failure),
      };
    });
