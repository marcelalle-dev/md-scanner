import 'package:equatable/equatable.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';

/// What the user is scanning. Chosen on the capture screen; it selects a
/// [ScanModePreset] and therefore changes detection and rendering.
enum ScanMode {
  document,
  receipt,
  book,
  whiteboard,
  idCard;

  ScanModePreset get preset => ScanModePreset.of(this);

  static ScanMode fromName(String? name) =>
      values.asNameMap()[name] ?? ScanMode.document;
}

/// Mode-specific tuning of the image pipeline. These are not user settings:
/// they describe the physical object being scanned.
class ProcessingHints extends Equatable {
  const ProcessingHints({
    required this.filterStrength,
    required this.minAreaFraction,
    required this.maxElongation,
    this.aspectRatio,
    this.aspectTolerance = 0.08,
  }) : assert(filterStrength >= 0 && filterStrength <= 1),
       assert(minAreaFraction > 0 && minAreaFraction < 1),
       assert(maxElongation >= 1),
       assert(aspectRatio == null || aspectRatio >= 1);

  /// How aggressive the document filters are, 0 (gentle) to 1 (strong):
  /// threshold sensitivity of black and white, amount of paper whitening and
  /// text darkening of readability, target level of the illumination
  /// normalization, punch of the colour enhancement.
  final double filterStrength;

  /// Smallest share of the frame a detected outline may cover. Lower for
  /// narrow or small objects (receipts, cards).
  final double minAreaFraction;

  /// Largest long-edge / short-edge ratio accepted for a detected outline.
  final double maxElongation;

  /// Long edge / short edge of the physical object when it is standardized
  /// (ID-1 cards), null when any proportion is legitimate.
  final double? aspectRatio;

  /// Relative distance to [aspectRatio] under which the rectified page is
  /// snapped to it. Kept below the gap between ID-1 (1.585) and passport
  /// pages (1.42) so that the latter are never squeezed into a card.
  final double aspectTolerance;

  /// Returns [aspectRatio] when [measured] (long edge / short edge of the
  /// rectified outline, hence >= 1) is close enough to it, else [measured].
  double resolveAspect(double measured) {
    final expected = aspectRatio;
    if (expected == null || !measured.isFinite || measured <= 0) {
      return measured;
    }
    return (measured / expected - 1).abs() <= aspectTolerance
        ? expected
        : measured;
  }

  @override
  List<Object?> get props => [
    filterStrength,
    minAreaFraction,
    maxElongation,
    aspectRatio,
    aspectTolerance,
  ];
}

/// Defaults of a [ScanMode]: the adjustments a freshly captured page starts
/// with and the [ProcessingHints] the image processor applies for that mode.
class ScanModePreset extends Equatable {
  const ScanModePreset._({
    required this.mode,
    required this.adjustments,
    required this.hints,
  });

  factory ScanModePreset.of(ScanMode mode) => switch (mode) {
    ScanMode.document => document,
    ScanMode.receipt => receipt,
    ScanMode.book => book,
    ScanMode.whiteboard => whiteboard,
    ScanMode.idCard => idCard,
  };

  /// ISO/IEC 7810 ID-1 (bank and identity cards): 85.6 mm x 54 mm.
  static const double id1AspectRatio = 85.6 / 54.0;

  /// Office paper: whitened background, darker text, colours kept (stamps,
  /// signatures, highlighting).
  static const ScanModePreset document = ScanModePreset._(
    mode: ScanMode.document,
    adjustments: ImageAdjustments(filter: ScanFilter.readability),
    hints: ProcessingHints(
      filterStrength: 0.5,
      minAreaFraction: 0.2,
      maxElongation: 2.6,
    ),
  );

  /// Thermal paper: faint print, so a sensitive black and white threshold;
  /// long narrow strips, so small and very elongated outlines are accepted.
  static const ScanModePreset receipt = ScanModePreset._(
    mode: ScanMode.receipt,
    adjustments: ImageAdjustments(filter: ScanFilter.blackAndWhite),
    hints: ProcessingHints(
      filterStrength: 1,
      minAreaFraction: 0.06,
      maxElongation: 10,
    ),
  );

  /// Bound pages: stronger whitening to absorb the shadow of the gutter and
  /// the tint of the paper. Proportions are left exactly as measured.
  static const ScanModePreset book = ScanModePreset._(
    mode: ScanMode.book,
    adjustments: ImageAdjustments(filter: ScanFilter.readability),
    hints: ProcessingHints(
      filterStrength: 0.85,
      minAreaFraction: 0.2,
      maxElongation: 2.6,
    ),
  );

  /// Glossy boards: full illumination normalization (glare, uneven room
  /// lighting) and vivid marker colours; boards are often very wide.
  static const ScanModePreset whiteboard = ScanModePreset._(
    mode: ScanMode.whiteboard,
    adjustments: ImageAdjustments(filter: ScanFilter.noShadow, saturation: 0.4),
    hints: ProcessingHints(
      filterStrength: 1,
      minAreaFraction: 0.15,
      maxElongation: 4,
    ),
  );

  /// Cards: natural colours (photo, holograms), small in the frame, and
  /// rectified to the exact ID-1 proportions.
  static const ScanModePreset idCard = ScanModePreset._(
    mode: ScanMode.idCard,
    adjustments: ImageAdjustments(filter: ScanFilter.enhanced),
    hints: ProcessingHints(
      filterStrength: 0.5,
      minAreaFraction: 0.06,
      maxElongation: 2.2,
      aspectRatio: id1AspectRatio,
    ),
  );

  final ScanMode mode;

  /// Adjustments a new page of this mode starts with.
  final ImageAdjustments adjustments;

  final ProcessingHints hints;

  @override
  List<Object?> get props => [mode, adjustments, hints];
}
