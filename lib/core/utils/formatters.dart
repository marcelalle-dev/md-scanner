import 'package:intl/intl.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';

/// Human-readable file size in the user's language ("1,4 Mo" / "1.4 MB").
String formatFileSize(CoreLocalizations l10n, int bytes) {
  const kilo = 1024;
  final number = NumberFormat.decimalPatternDigits(
    locale: l10n.localeName,
    decimalDigits: 1,
  );
  if (bytes < kilo) return l10n.fileSizeBytes(bytes.toString());
  if (bytes < kilo * kilo) {
    return l10n.fileSizeKilobytes(number.format(bytes / kilo));
  }
  if (bytes < kilo * kilo * kilo) {
    return l10n.fileSizeMegabytes(number.format(bytes / (kilo * kilo)));
  }
  return l10n.fileSizeGigabytes(number.format(bytes / (kilo * kilo * kilo)));
}

/// Short date such as "27 nov. 2026" / "Nov 27, 2026".
String formatDate(String localeName, DateTime date) =>
    DateFormat.yMMMd(localeName).format(date.toLocal());

/// Date with time such as "27 nov. 2026 14:05".
String formatDateTime(String localeName, DateTime date) =>
    DateFormat.yMMMd(localeName).add_Hm().format(date.toLocal());

/// Removes characters that are illegal or risky in a file name and trims it
/// to [maxLength]. Returns [fallback] when nothing usable is left.
String sanitizeFileName(
  String input, {
  String fallback = 'document',
  int maxLength = 80,
}) {
  final cleaned = input
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+'), '');
  if (cleaned.isEmpty) return fallback;
  return cleaned.length <= maxLength
      ? cleaned
      : cleaned.substring(0, maxLength).trim();
}
