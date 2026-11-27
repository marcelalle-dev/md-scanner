import 'package:equatable/equatable.dart';

/// Look applied to a scanned page after perspective correction.
enum ScanFilter {
  /// Pixels as captured.
  original,

  /// Colour auto-enhance: levels, light white balance, contrast and
  /// saturation. Keeps photos and coloured documents natural.
  enhanced,

  /// Neutral grey levels.
  grayscale,

  /// Pure black ink on pure white paper (locally adaptive threshold).
  blackAndWhite,

  /// Whitened paper and darker text, colours kept.
  readability,

  /// Evens out the lighting so soft shadows disappear, colours kept.
  noShadow;

  /// True when the result has no colour information (single channel).
  bool get isMonochrome => this == grayscale || this == blackAndWhite;

  static ScanFilter fromName(String? name) =>
      values.asNameMap()[name] ?? ScanFilter.original;
}

/// User-controlled corrections of one page. Immutable and cheap to compare,
/// so it can serve as a cache key for previews.
///
/// With [ScanFilter.blackAndWhite] the result has only two tones:
/// [brightness] then moves the ink threshold (brighter = thinner strokes and
/// fewer specks) and [saturation] has no effect.
class ImageAdjustments extends Equatable {
  const ImageAdjustments({
    this.quarterTurns = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.filter = ScanFilter.original,
  });

  /// Tolerant on purpose: unknown filters and out-of-range numbers coming
  /// from an older or damaged session fall back to neutral values.
  factory ImageAdjustments.fromJson(Map<String, Object?> json) {
    double read(String key) {
      final value = json[key];
      return value is num && value.isFinite ? value.toDouble() : 0.0;
    }

    final turns = json['quarterTurns'];
    final filter = json['filter'];
    return ImageAdjustments(
      quarterTurns: turns is int ? turns : 0,
      brightness: read('brightness'),
      contrast: read('contrast'),
      saturation: read('saturation'),
      filter: ScanFilter.fromName(filter is String ? filter : null),
    ).normalized();
  }

  static const ImageAdjustments none = ImageAdjustments();

  /// Clockwise rotation in steps of 90 degrees, 0 to 3.
  final int quarterTurns;

  /// -1 (darker) to 1 (brighter), 0 leaves the image unchanged.
  final double brightness;

  /// -1 (flatter) to 1 (punchier), 0 leaves the image unchanged.
  final double contrast;

  /// -1 (grey) to 1 (twice as vivid), 0 leaves the image unchanged.
  final double saturation;

  final ScanFilter filter;

  /// True when rendering with these adjustments only crops the image.
  bool get isIdentity => normalized() == none;

  /// True when the page ends up rotated by a quarter turn either way.
  bool get swapsDimensions => quarterTurns.isOdd;

  /// The same adjustments with every value brought back into its range.
  /// The image processor always applies the normalized form.
  ImageAdjustments normalized() => ImageAdjustments(
    quarterTurns: quarterTurns % 4,
    brightness: _unit(brightness),
    contrast: _unit(contrast),
    saturation: _unit(saturation),
    filter: filter,
  );

  ImageAdjustments rotatedClockwise() =>
      copyWith(quarterTurns: (quarterTurns + 1) % 4);

  ImageAdjustments rotatedCounterClockwise() =>
      copyWith(quarterTurns: (quarterTurns + 3) % 4);

  ImageAdjustments copyWith({
    int? quarterTurns,
    double? brightness,
    double? contrast,
    double? saturation,
    ScanFilter? filter,
  }) => ImageAdjustments(
    quarterTurns: quarterTurns ?? this.quarterTurns,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    filter: filter ?? this.filter,
  );

  Map<String, Object?> toJson() => {
    'quarterTurns': quarterTurns,
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'filter': filter.name,
  };

  @override
  List<Object?> get props => [
    quarterTurns,
    brightness,
    contrast,
    saturation,
    filter,
  ];

  static double _unit(double value) =>
      value.isNaN ? 0.0 : value.clamp(-1.0, 1.0).toDouble();
}
