import 'package:equatable/equatable.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';

/// A run of consecutive pages, written the way a user types it: page numbers
/// start at 1 and both ends are included.
///
/// Engine arguments named `pageIndex` or `pages` are 0-based instead; use
/// [indexes] or [resolvePageRanges] to convert.
class PageRange extends Equatable {
  /// [end] null means "up to the last page".
  const PageRange(this.start, [this.end]);

  const PageRange.single(int page) : this(page, page);

  /// First page number (1-based).
  final int start;

  /// Last page number (1-based, inclusive), or null for an open range.
  final int? end;

  bool get isOpenEnded => end == null;

  /// True when the range designates at least one page of a document of
  /// [pageCount] pages and does not reach beyond it.
  bool isValidFor(int pageCount) {
    final last = end ?? pageCount;
    return start >= 1 && last >= start && last <= pageCount;
  }

  /// 0-based indexes covered by the range in a document of [pageCount]
  /// pages. Only meaningful when [isValidFor] is true.
  List<int> indexes(int pageCount) {
    final last = end ?? pageCount;
    return [for (var page = start; page <= last; page++) page - 1];
  }

  @override
  List<Object?> get props => [start, end];

  @override
  String toString() => switch (end) {
    null => '$start-',
    final last when last == start => '$start',
    final last => '$start-$last',
  };
}

const Failure _invalid = PdfFailure(PdfFailureKind.invalidPageRange);

final RegExp _token = RegExp(r'^(\d{1,9})?(\s*-\s*(\d{1,9})?)?$');

/// Parses `"1-3,5,8-"` into ranges. Accepted tokens, separated by commas or
/// semicolons: `5`, `2-4`, `8-` (to the end) and `-3` (from the start).
///
/// Fails with `PdfFailure(invalidPageRange)` on an empty or malformed input,
/// a page number 0, a reversed range (`5-2`) and, when [pageCount] is given,
/// any page beyond the document.
Result<List<PageRange>> parsePageRanges(String input, {int? pageCount}) {
  final tokens = input.split(RegExp('[,;]')).map((token) => token.trim());
  final ranges = <PageRange>[];
  for (final token in tokens) {
    if (token.isEmpty) return const Err(_invalid);
    final match = _token.firstMatch(token);
    if (match == null) return const Err(_invalid);
    final first = match.group(1);
    final hasDash = match.group(2) != null;
    final second = match.group(3);
    if (first == null && second == null) return const Err(_invalid);

    final PageRange range;
    if (!hasDash) {
      range = PageRange.single(int.parse(first!));
    } else {
      range = PageRange(
        first == null ? 1 : int.parse(first),
        second == null ? null : int.parse(second),
      );
    }
    final end = range.end;
    if (range.start < 1 || (end != null && end < range.start)) {
      return const Err(_invalid);
    }
    if (pageCount != null && !range.isValidFor(pageCount)) {
      return const Err(_invalid);
    }
    ranges.add(range);
  }
  if (ranges.isEmpty) return const Err(_invalid);
  return Success(ranges);
}

/// Flattens [ranges] into 0-based page indexes, in the order given (a page
/// listed twice appears twice). Fails with `PdfFailure(invalidPageRange)`
/// when the list is empty or a range does not fit in [pageCount] pages.
Result<List<int>> resolvePageRanges(List<PageRange> ranges, int pageCount) {
  if (ranges.isEmpty || pageCount < 1) return const Err(_invalid);
  final indexes = <int>[];
  for (final range in ranges) {
    if (!range.isValidFor(pageCount)) return const Err(_invalid);
    indexes.addAll(range.indexes(pageCount));
  }
  return Success(indexes);
}

/// Ranges that cut a document of [pageCount] pages into chunks of
/// [pagesPerFile] pages (the last chunk may be shorter). Empty when either
/// argument is below 1.
List<PageRange> pageRangesEvery(int pagesPerFile, int pageCount) {
  if (pagesPerFile < 1 || pageCount < 1) return const [];
  return [
    for (var start = 1; start <= pageCount; start += pagesPerFile)
      PageRange(
        start,
        start + pagesPerFile - 1 > pageCount
            ? pageCount
            : start + pagesPerFile - 1,
      ),
  ];
}

/// One single-page range per page of the document.
List<PageRange> pageRangesForEachPage(int pageCount) =>
    pageRangesEvery(1, pageCount);
