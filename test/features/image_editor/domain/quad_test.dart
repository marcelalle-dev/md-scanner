import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';

void main() {
  const tilted = Quad(
    topLeft: NormalizedPoint(0.1, 0.2),
    topRight: NormalizedPoint(0.9, 0.1),
    bottomRight: NormalizedPoint(0.8, 0.9),
    bottomLeft: NormalizedPoint(0.2, 0.8),
  );

  group('NormalizedPoint', () {
    test('clamps into the image and measures distances', () {
      expect(
        const NormalizedPoint(-0.2, 1.4).clamped(),
        const NormalizedPoint(0, 1),
      );
      expect(
        const NormalizedPoint(0, 0).distanceTo(const NormalizedPoint(0.3, 0.4)),
        closeTo(0.5, 1e-12),
      );
    });

    test('survives a JSON round trip and tolerates garbage', () {
      const point = NormalizedPoint(0.25, 0.75);
      expect(NormalizedPoint.fromJson(point.toJson()), point);
      expect(
        NormalizedPoint.fromJson(const {'x': 'oops', 'y': double.nan}),
        const NormalizedPoint(0, 0),
      );
    });
  });

  group('Quad', () {
    test('full covers the whole image', () {
      expect(Quad.full.area, closeTo(1, 1e-12));
      expect(Quad.full.isConvex, isTrue);
      expect(Quad.full.isRenderable, isTrue);
      expect(Quad.full.corners, hasLength(4));
    });

    test('area follows the shoelace formula', () {
      const half = Quad(
        topLeft: NormalizedPoint(0.25, 0.25),
        topRight: NormalizedPoint(0.75, 0.25),
        bottomRight: NormalizedPoint(0.75, 0.75),
        bottomLeft: NormalizedPoint(0.25, 0.75),
      );
      expect(half.area, closeTo(0.25, 1e-12));
      expect(tilted.area, closeTo(0.49, 1e-12));
      expect(tilted.isConvex, isTrue);
    });

    test('a crossed quad is not convex', () {
      final crossed = tilted.copyWith(
        topRight: tilted.bottomRight,
        bottomRight: tilted.topRight,
      );
      expect(crossed.isConvex, isFalse);
      expect(crossed.isRenderable, isFalse);
    });

    test('a mirrored quad is not convex', () {
      final mirrored = Quad.fromCorners(tilted.corners.reversed.toList());
      expect(mirrored.area, closeTo(tilted.area, 1e-12));
      expect(mirrored.isConvex, isFalse);
    });

    test('three aligned corners are not convex', () {
      const flat = Quad(
        topLeft: NormalizedPoint(0.1, 0.1),
        topRight: NormalizedPoint(0.5, 0.1),
        bottomRight: NormalizedPoint(0.9, 0.1),
        bottomLeft: NormalizedPoint(0.5, 0.8),
      );
      expect(flat.isConvex, isFalse);
    });

    test('a concave quad is not convex', () {
      final dented = tilted.copyWith(
        bottomRight: const NormalizedPoint(0.45, 0.45),
      );
      expect(dented.isConvex, isFalse);
    });

    test('a vanishing quad is convex but not renderable', () {
      const speck = Quad(
        topLeft: NormalizedPoint(0.5, 0.5),
        topRight: NormalizedPoint(0.505, 0.5),
        bottomRight: NormalizedPoint(0.505, 0.505),
        bottomLeft: NormalizedPoint(0.5, 0.505),
      );
      expect(speck.isConvex, isTrue);
      expect(speck.area, lessThan(Quad.minRenderableArea));
      expect(speck.isRenderable, isFalse);
    });

    test('clamped brings every corner back inside', () {
      const outside = Quad(
        topLeft: NormalizedPoint(-0.1, -0.3),
        topRight: NormalizedPoint(1.2, 0),
        bottomRight: NormalizedPoint(1, 1.5),
        bottomLeft: NormalizedPoint(0, 1),
      );
      expect(outside.clamped(), Quad.full);
    });

    test('equality, copyWith and JSON round trip', () {
      expect(tilted.copyWith(), tilted);
      expect(
        tilted.copyWith(topLeft: const NormalizedPoint(0, 0)),
        isNot(tilted),
      );
      expect(Quad.fromJson(tilted.toJson()), tilted);
    });

    test('fromJson degrades to the whole image on damaged data', () {
      expect(Quad.fromJson(const {}), Quad.full);
      expect(
        Quad.fromJson({'topLeft': tilted.topLeft.toJson(), 'topRight': 3}),
        Quad.full,
      );
    });

    test('fromCorners requires exactly four points', () {
      expect(
        () => Quad.fromCorners(const [NormalizedPoint(0, 0)]),
        throwsArgumentError,
      );
    });
  });
}
