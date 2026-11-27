import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

void main() {
  test('every mode has its own preset', () {
    final presets = [for (final mode in ScanMode.values) mode.preset];
    for (var i = 0; i < presets.length; i++) {
      expect(presets[i].mode, ScanMode.values[i]);
      for (var j = i + 1; j < presets.length; j++) {
        // Two modes may share a filter, never the whole recipe.
        expect(
          [presets[i].adjustments, presets[i].hints],
          isNot([presets[j].adjustments, presets[j].hints]),
          reason: '${presets[i].mode} vs ${presets[j].mode}',
        );
      }
    }
  });

  test('presets follow the product definition of each mode', () {
    expect(ScanModePreset.document.adjustments.filter, ScanFilter.readability);

    const receipt = ScanModePreset.receipt;
    expect(receipt.adjustments.filter, ScanFilter.blackAndWhite);
    expect(receipt.hints.filterStrength, 1);
    expect(
      receipt.hints.maxElongation,
      greaterThan(ScanModePreset.document.hints.maxElongation),
    );
    expect(
      receipt.hints.minAreaFraction,
      lessThan(ScanModePreset.document.hints.minAreaFraction),
    );

    const book = ScanModePreset.book;
    expect(book.adjustments.filter, ScanFilter.readability);
    expect(book.hints.aspectRatio, isNull);
    expect(
      book.hints.filterStrength,
      greaterThan(ScanModePreset.document.hints.filterStrength),
    );

    const whiteboard = ScanModePreset.whiteboard;
    expect(whiteboard.adjustments.filter, ScanFilter.noShadow);
    expect(whiteboard.adjustments.saturation, greaterThan(0));
    expect(whiteboard.hints.filterStrength, 1);

    const idCard = ScanModePreset.idCard;
    expect(idCard.adjustments.filter, ScanFilter.enhanced);
    expect(idCard.hints.aspectRatio, closeTo(85.6 / 54, 1e-12));
  });

  test('only the card mode forces proportions', () {
    for (final mode in ScanMode.values) {
      expect(
        mode.preset.hints.aspectRatio == null,
        mode != ScanMode.idCard,
        reason: '$mode',
      );
    }
  });

  test('resolveAspect snaps close measurements and leaves the others', () {
    final hints = ScanModePreset.idCard.hints;
    const id1 = ScanModePreset.id1AspectRatio;
    expect(hints.resolveAspect(1.55), id1);
    expect(hints.resolveAspect(1.66), id1);
    // A passport data page (125 x 88 mm) must not become a card.
    expect(hints.resolveAspect(125 / 88), 125 / 88);
    expect(hints.resolveAspect(1), 1);
    expect(hints.resolveAspect(double.nan).isNaN, isTrue);
    expect(ScanModePreset.document.hints.resolveAspect(1.58), 1.58);
  });

  test('mode names are parsed leniently', () {
    expect(ScanMode.fromName('whiteboard'), ScanMode.whiteboard);
    expect(ScanMode.fromName('hologram'), ScanMode.document);
    expect(ScanMode.fromName(null), ScanMode.document);
  });

  test('output format helpers', () {
    expect(
      OutputFormat.recommendedFor(ScanFilter.blackAndWhite),
      OutputFormat.png,
    );
    for (final filter in ScanFilter.values) {
      if (filter == ScanFilter.blackAndWhite) continue;
      expect(OutputFormat.recommendedFor(filter), OutputFormat.jpg);
    }
    expect(OutputFormat.fromPath('/a/b/page.PNG'), OutputFormat.png);
    expect(OutputFormat.fromPath('/a/b/page.jpeg'), OutputFormat.jpg);
    expect(OutputFormat.fromPath('/a/b/page'), OutputFormat.jpg);
    expect(OutputFormat.png.mimeType, 'image/png');
    expect(OutputFormat.jpg.extension, 'jpg');
  });

  test('requests compare by value and copy selectively', () {
    const request = ImageRenderRequest(sourcePath: 'in', outputPath: 'out');
    expect(request.jpegQuality, 88);
    expect(request.maxLongEdge, 2600);
    expect(request.quad, isNull);
    expect(request.copyWith(), request);
    expect(request.copyWith(mode: ScanMode.receipt), isNot(request));
    expect(request.copyWith(quad: () => null).quad, isNull);

    const preview = ImagePreviewRequest(sourcePath: 'in');
    expect(preview.maxLongEdge, 1280);
    expect(preview.copyWith(maxLongEdge: 640).maxLongEdge, 640);
    expect(preview.copyWith(), preview);

    const info = ImageInfo(width: 400, height: 300, byteSize: 10);
    expect(info.pixelCount, 120000);
    expect(info.aspectRatio, closeTo(4 / 3, 1e-12));
    expect(info.isLandscape, isTrue);
  });
}
