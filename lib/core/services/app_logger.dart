import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';

enum LogLevel { debug, info, warning, error }

/// A technical event. By contract it carries no personal data: [name] is a
/// stable dotted identifier (`scan.completed`) and [attributes] only hold
/// counts, durations, booleans or enum names.
@immutable
class LogEvent {
  const LogEvent({
    required this.timestamp,
    required this.level,
    required this.name,
    this.attributes = const {},
  });

  final DateTime timestamp;
  final LogLevel level;
  final String name;
  final Map<String, Object> attributes;

  @override
  String toString() {
    final suffix = attributes.isEmpty ? '' : ' $attributes';
    return '${timestamp.toIso8601String()} ${level.name.toUpperCase()} $name$suffix';
  }
}

/// In-memory technical journal shown in the Security Center.
///
/// Attribute values are restricted to [num], [bool], [Enum] and [Duration] so
/// that a file name, an OCR extract or a scanned QR payload cannot end up in
/// the journal by accident. Anything else is replaced by its type name.
class AppLogger {
  AppLogger({this.capacity = 300, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int capacity;
  final DateTime Function() _clock;
  final Queue<LogEvent> _events = Queue<LogEvent>();

  List<LogEvent> get events => List<LogEvent>.unmodifiable(_events);

  void debug(String name, [Map<String, Object?> attributes = const {}]) =>
      _record(LogLevel.debug, name, attributes);

  void info(String name, [Map<String, Object?> attributes = const {}]) =>
      _record(LogLevel.info, name, attributes);

  void warning(String name, [Map<String, Object?> attributes = const {}]) =>
      _record(LogLevel.warning, name, attributes);

  void error(String name, [Map<String, Object?> attributes = const {}]) =>
      _record(LogLevel.error, name, attributes);

  void failure(String name, Failure failure) {
    _record(LogLevel.error, name, {
      'failure': failure.runtimeType.toString(),
      if (failure.debugMessage != null) 'detail': failure.debugMessage,
    }, trusted: true);
  }

  void clear() => _events.clear();

  void _record(
    LogLevel level,
    String name,
    Map<String, Object?> attributes, {
    bool trusted = false,
  }) {
    final event = LogEvent(
      timestamp: _clock(),
      level: level,
      name: name,
      attributes: {
        for (final entry in attributes.entries)
          if (entry.value != null)
            entry.key: trusted ? entry.value! : _sanitize(entry.value!),
      },
    );
    _events.addLast(event);
    while (_events.length > capacity) {
      _events.removeFirst();
    }
    if (kDebugMode) debugPrint('[md_scanner] $event');
  }

  static Object _sanitize(Object value) => switch (value) {
    num() || bool() => value,
    Enum() => value.name,
    Duration() => value.inMilliseconds,
    _ => '<${value.runtimeType}>',
  };
}

final appLoggerProvider = Provider<AppLogger>((ref) => AppLogger());
