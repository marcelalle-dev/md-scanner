import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:md_scanner/app/configuration/app_config.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/settings_store.dart';
import 'package:md_scanner/features/premium/domain/billing.dart';
import 'package:uuid/uuid.dart';

/// Tasks of the assistant, with the name the backend expects.
enum AiTask {
  summary('summary'),
  sectionSummary('section_summary'),
  qa('qa'),
  extract('extract'),
  translate('translate'),
  flashcards('flashcards'),
  adminAnalysis('admin_analysis');

  const AiTask(this.wireName);

  final String wireName;
}

/// Dates and amounts spotted with plain pattern matching, entirely on the
/// device. No network, no AI: this always works, including offline.
class LocalFindings extends Equatable {
  const LocalFindings({required this.dates, required this.amounts});

  final List<String> dates;
  final List<String> amounts;

  bool get isEmpty => dates.isEmpty && amounts.isEmpty;

  @override
  List<Object?> get props => [dates, amounts];
}

abstract final class LocalExtractor {
  static const String _months =
      'janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|'
      'octobre|novembre|décembre|decembre|january|february|march|april|may|june|'
      'july|august|september|october|november|december';

  static final RegExp _date = RegExp(
    r'\b(?:\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}|\d{4}-\d{2}-\d{2}|'
    '\\d{1,2}(?:er)?\\s+(?:$_months)\\s+\\d{4}|'
    '(?:$_months)\\s+\\d{1,2},?\\s+\\d{4})\\b',
    caseSensitive: false,
  );

  static final RegExp _amount = RegExp(
    r'(?:(?:€|\$|£)\s?\d{1,3}(?:[ .,  ]?\d{3})*(?:[.,]\d{1,2})?|'
    r'\d{1,3}(?:[ .,  ]?\d{3})*(?:[.,]\d{1,2})?\s?'
    r'(?:€|\$|£|EUR|USD|GBP|XOF|F\s?CFA|FCFA|CFA)(?![A-Za-z]))',
    caseSensitive: false,
  );

  static LocalFindings extract(String text) => LocalFindings(
    dates: _unique(_date.allMatches(text)),
    amounts: _unique(_amount.allMatches(text)),
  );

  static List<String> _unique(Iterable<RegExpMatch> matches) {
    final seen = <String>{};
    return [
      for (final match in matches)
        if (seen.add(match.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim()))
          match.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim(),
    ];
  }
}

class AiAnswer extends Equatable {
  const AiAnswer({required this.text, this.remainingToday});

  /// Readable rendering of the structured result.
  final String text;
  final int? remainingToday;

  @override
  List<Object?> get props => [text, remainingToday];
}

/// Client of the MD SCANNER backend, which relays to the AI provider.
///
/// No AI key lives in the app. Only text is sent, never a file, and the
/// caller must have obtained the user's consent first.
class AiAssistantService {
  AiAssistantService({
    required this.baseUrl,
    required this._settings,
    required this._activePurchase,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final SettingsStore _settings;
  final ActivePurchase? Function() _activePurchase;
  final http.Client _client;

  static const String _installIdKey = 'ai.install_id';
  static const String consentKey = 'ai.consent_given';
  static const Duration _timeout = Duration(seconds: 90);

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<bool> get hasConsent => _settings.readBool(consentKey);

  Future<void> recordConsent() => _settings.writeBool(consentKey, value: true);

  /// Random identifier of this installation, used by the server for quotas.
  /// It is not derived from the device or the user.
  Future<String> _installId() async {
    final existing = await _settings.read(_installIdKey);
    if (existing != null) return existing;
    final created = const Uuid().v4();
    await _settings.write(_installIdKey, created);
    return created;
  }

  Future<Result<AiAnswer>> run({
    required AiTask task,
    required String documentText,
    required String outputLanguage,
    String? question,
    String? targetLanguage,
  }) => guard(
    () async {
      if (!isConfigured) {
        throw const FailureException(
          NetworkFailure(NetworkFailureKind.notConfigured),
        );
      }
      final purchase = _activePurchase();
      final response = await _client
          .post(
            Uri.parse(baseUrl).resolve('/v1/ai/tasks'),
            headers: {
              'content-type': 'application/json',
              'x-install-id': await _installId(),
              if (purchase != null) ...{
                'authorization': 'Bearer ${purchase.token}',
                'x-product-id': purchase.productId,
              },
            },
            body: jsonEncode({
              'task': task.wireName,
              'outputLanguage': outputLanguage,
              'documentText': documentText,
              'question': ?question,
              'targetLanguage': ?targetLanguage,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw FailureException(_failureFor(response.statusCode));
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> || !body.containsKey('result')) {
        throw const FailureException(
          NetworkFailure(NetworkFailureKind.invalidResponse),
        );
      }
      final quota = body['quota'];
      return AiAnswer(
        text: renderAiResult(body['result']),
        remainingToday: quota is Map<String, dynamic>
            ? quota['remaining'] as int?
            : null,
      );
    },
    onError: (error, _) => switch (error) {
      FormatException() ||
      TypeError() => const NetworkFailure(NetworkFailureKind.invalidResponse),
      http.ClientException() ||
      SocketException() => const NetworkFailure(NetworkFailureKind.offline),
      _ => null,
    },
  );

  static Failure _failureFor(int status) => switch (status) {
    401 || 402 || 403 => const NetworkFailure(
      NetworkFailureKind.unauthorized,
      statusCode: 403,
    ),
    413 => const ValidationFailure('document_too_long'),
    429 => const NetworkFailure(NetworkFailureKind.quotaExceeded),
    _ => NetworkFailure(NetworkFailureKind.serverError, statusCode: status),
  };
}

/// Turns the structured JSON result of any task into readable text: keys
/// become headings, lists become bullet points.
String renderAiResult(Object? result) {
  final buffer = StringBuffer();
  void write(Object? value, int depth, {String? label}) {
    final indent = '  ' * depth;
    final title = label == null ? '' : '${_humanize(label)} : ';
    switch (value) {
      case null:
        return;
      case final Map<String, dynamic> map:
        if (label != null) buffer.writeln('$indent${_humanize(label)}');
        for (final entry in map.entries) {
          write(
            entry.value,
            label == null ? depth : depth + 1,
            label: entry.key,
          );
        }
      case final List<dynamic> list:
        if (label != null) buffer.writeln('$indent${_humanize(label)}');
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            buffer.writeln(
              '$indent• ${item.values.where((v) => v != null && v is! List && v is! Map).join(' — ')}',
            );
            for (final entry in item.entries) {
              if (entry.value is List || entry.value is Map) {
                write(entry.value, depth + 1, label: entry.key);
              }
            }
          } else {
            buffer.writeln('$indent• $item');
          }
        }
      default:
        buffer.writeln('$indent$title$value');
    }
  }

  write(result, 0);
  return buffer.toString().trim();
}

String _humanize(String key) {
  final spaced = key
      .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .toLowerCase();
  return spaced.isEmpty
      ? spaced
      : spaced[0].toUpperCase() + spaced.substring(1);
}

final aiAssistantServiceProvider = Provider<AiAssistantService>(
  (ref) => AiAssistantService(
    baseUrl: AppConfig.aiBackendUrl,
    settings: ref.watch(settingsStoreProvider),
    activePurchase: () => ref.read(billingServiceProvider).activePurchase,
  ),
);
