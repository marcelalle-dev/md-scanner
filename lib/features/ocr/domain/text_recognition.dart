import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';

/// Text read on one image. Lines keep the reading order given by the engine.
class OcrPage extends Equatable {
  const OcrPage({required this.text, this.lines = const []});

  final String text;
  final List<String> lines;

  bool get isEmpty => text.trim().isEmpty;

  @override
  List<Object?> get props => [text, lines];
}

/// On-device text recognition. Hides the ML Kit plugin, which only runs on a
/// device, so the OCR workflow stays testable.
abstract interface class TextRecognitionService {
  /// Recognizes Latin-script text (French, English…) on the image at
  /// [imagePath]. An image without text yields an empty [OcrPage], not an
  /// error.
  Future<Result<OcrPage>> recognize(String imagePath);

  Future<void> dispose();
}

/// Bound to the ML Kit implementation in `bootstrap()`.
final textRecognitionServiceProvider = Provider<TextRecognitionService>(
  (ref) =>
      throw StateError('textRecognitionServiceProvider must be overridden'),
);

/// Case- and accent-insensitive search used to locate text in an OCR result.
abstract final class TextSearch {
  static const Map<String, String> _folds = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ì': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'ñ': 'n',
  };

  /// Lower-cases and strips accents, one output character per input
  /// character so offsets in the folded text match the original.
  static String fold(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final lower = char.toLowerCase();
      final folded = _folds[lower] ?? lower;
      buffer.write(folded.length == char.length ? folded : char);
    }
    return buffer.toString();
  }

  /// Start offsets of every non-overlapping occurrence of [query] in [text].
  static List<int> findAll(String text, String query) {
    final needle = fold(query.trim());
    if (needle.isEmpty) return const [];
    final haystack = fold(text);
    final matches = <int>[];
    var from = 0;
    while (true) {
      final index = haystack.indexOf(needle, from);
      if (index < 0) return matches;
      matches.add(index);
      from = index + needle.length;
    }
  }
}
