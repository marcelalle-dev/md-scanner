import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';

void main() {
  test('defaults leave the image untouched', () {
    expect(ImageAdjustments.none.isIdentity, isTrue);
    expect(const ImageAdjustments(quarterTurns: 4).isIdentity, isTrue);
    expect(const ImageAdjustments(brightness: 0.1).isIdentity, isFalse);
    expect(
      const ImageAdjustments(filter: ScanFilter.grayscale).isIdentity,
      isFalse,
    );
  });

  test('normalized clamps sliders and wraps rotation', () {
    const wild = ImageAdjustments(
      quarterTurns: -1,
      brightness: 3,
      contrast: -7,
      saturation: double.nan,
    );
    expect(
      wild.normalized(),
      const ImageAdjustments(quarterTurns: 3, brightness: 1, contrast: -1),
    );
    expect(
      const ImageAdjustments(quarterTurns: 6).normalized().quarterTurns,
      2,
    );
  });

  test('rotation helpers turn by a quarter and wrap around', () {
    var adjustments = ImageAdjustments.none;
    final seen = <int>[];
    for (var i = 0; i < 4; i++) {
      adjustments = adjustments.rotatedClockwise();
      seen.add(adjustments.quarterTurns);
    }
    expect(seen, [1, 2, 3, 0]);
    expect(ImageAdjustments.none.rotatedCounterClockwise().quarterTurns, 3);
    expect(const ImageAdjustments(quarterTurns: 1).swapsDimensions, isTrue);
    expect(const ImageAdjustments(quarterTurns: 2).swapsDimensions, isFalse);
  });

  test('JSON round trip keeps every field', () {
    const adjustments = ImageAdjustments(
      quarterTurns: 3,
      brightness: 0.25,
      contrast: -0.5,
      saturation: 0.75,
      filter: ScanFilter.noShadow,
    );
    expect(ImageAdjustments.fromJson(adjustments.toJson()), adjustments);
  });

  test('fromJson falls back to neutral values on damaged data', () {
    final parsed = ImageAdjustments.fromJson(const {
      'quarterTurns': 9,
      'brightness': 'bright',
      'contrast': 12,
      'filter': 'sepia',
    });
    expect(parsed, const ImageAdjustments(quarterTurns: 1, contrast: 1));
    expect(ImageAdjustments.fromJson(const {}), ImageAdjustments.none);
    expect(
      ImageAdjustments.fromJson(const {'filter': 42}),
      ImageAdjustments.none,
    );
  });

  test('only grayscale and black and white are monochrome', () {
    expect(ScanFilter.values.where((f) => f.isMonochrome), [
      ScanFilter.grayscale,
      ScanFilter.blackAndWhite,
    ]);
    expect(ScanFilter.fromName('readability'), ScanFilter.readability);
    expect(ScanFilter.fromName(null), ScanFilter.original);
  });
}
