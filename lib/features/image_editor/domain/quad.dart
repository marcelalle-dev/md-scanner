import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A position expressed as fractions of the upright image: (0, 0) is its
/// top-left corner and (1, 1) its bottom-right corner.
///
/// Resolution independent on purpose: the same point is valid on the camera
/// preview, on the low-resolution editor preview and on the full-size render.
class NormalizedPoint extends Equatable {
  const NormalizedPoint(this.x, this.y);

  factory NormalizedPoint.fromJson(Map<String, Object?> json) =>
      NormalizedPoint(_readDouble(json['x']), _readDouble(json['y']));

  final double x;
  final double y;

  NormalizedPoint clamped() => NormalizedPoint(
    x.clamp(0.0, 1.0).toDouble(),
    y.clamp(0.0, 1.0).toDouble(),
  );

  double distanceTo(NormalizedPoint other) {
    final dx = other.x - x;
    final dy = other.y - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  NormalizedPoint copyWith({double? x, double? y}) =>
      NormalizedPoint(x ?? this.x, y ?? this.y);

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  @override
  List<Object?> get props => [x, y];

  static double _readDouble(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : 0.0;
}

/// The outline of a document inside an image, one corner per document corner.
///
/// Corners are named after their position in the upright image and are listed
/// clockwise: top-left, top-right, bottom-right, bottom-left.
class Quad extends Equatable {
  const Quad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Builds a quad from [corners] given clockwise from the top-left one.
  factory Quad.fromCorners(List<NormalizedPoint> corners) {
    if (corners.length != 4) {
      throw ArgumentError.value(corners.length, 'corners', 'expected 4 points');
    }
    return Quad(
      topLeft: corners[0],
      topRight: corners[1],
      bottomRight: corners[2],
      bottomLeft: corners[3],
    );
  }

  /// Returns [full] when [json] does not hold four corners, so a damaged
  /// saved session degrades to "no crop" instead of failing to open.
  factory Quad.fromJson(Map<String, Object?> json) {
    NormalizedPoint? read(String key) {
      final value = json[key];
      return value is Map
          ? NormalizedPoint.fromJson(value.cast<String, Object?>())
          : null;
    }

    final topLeft = read('topLeft');
    final topRight = read('topRight');
    final bottomRight = read('bottomRight');
    final bottomLeft = read('bottomLeft');
    if (topLeft == null ||
        topRight == null ||
        bottomRight == null ||
        bottomLeft == null) {
      return full;
    }
    return Quad(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    );
  }

  /// The whole image: what the editor starts from when no document outline
  /// was detected.
  static const Quad full = Quad(
    topLeft: NormalizedPoint(0, 0),
    topRight: NormalizedPoint(1, 0),
    bottomRight: NormalizedPoint(1, 1),
    bottomLeft: NormalizedPoint(0, 1),
  );

  /// Smallest [area] a quad may have to be rendered (0.01 % of the image).
  static const double minRenderableArea = 1e-4;

  final NormalizedPoint topLeft;
  final NormalizedPoint topRight;
  final NormalizedPoint bottomRight;
  final NormalizedPoint bottomLeft;

  /// Clockwise from the top-left corner.
  List<NormalizedPoint> get corners => [
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ];

  /// True when the four corners, in order, form a strictly convex outline
  /// wound clockwise.
  ///
  /// False for a crossed ("bow-tie") quad, for three aligned corners and for
  /// a mirrored quad (corners dragged past each other): none of them can be
  /// rectified into a readable page.
  bool get isConvex {
    final points = corners;
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final b = points[(i + 1) % 4];
      final c = points[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (!(cross > _minTurn)) return false;
    }
    return true;
  }

  /// Surface as a fraction of the image (1.0 for [full]). Meaningful for a
  /// convex quad; a crossed quad yields the difference of its two lobes.
  double get area {
    final points = corners;
    var twice = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final b = points[(i + 1) % 4];
      twice += a.x * b.y - b.x * a.y;
    }
    return twice.abs() / 2;
  }

  /// True when the quad can be rectified: convex and not vanishingly small.
  bool get isRenderable => isConvex && area >= minRenderableArea;

  /// The same quad with every corner brought back inside the image.
  Quad clamped() => Quad(
    topLeft: topLeft.clamped(),
    topRight: topRight.clamped(),
    bottomRight: bottomRight.clamped(),
    bottomLeft: bottomLeft.clamped(),
  );

  Quad copyWith({
    NormalizedPoint? topLeft,
    NormalizedPoint? topRight,
    NormalizedPoint? bottomRight,
    NormalizedPoint? bottomLeft,
  }) => Quad(
    topLeft: topLeft ?? this.topLeft,
    topRight: topRight ?? this.topRight,
    bottomRight: bottomRight ?? this.bottomRight,
    bottomLeft: bottomLeft ?? this.bottomLeft,
  );

  Map<String, Object?> toJson() => {
    'topLeft': topLeft.toJson(),
    'topRight': topRight.toJson(),
    'bottomRight': bottomRight.toJson(),
    'bottomLeft': bottomLeft.toJson(),
  };

  @override
  List<Object?> get props => [topLeft, topRight, bottomRight, bottomLeft];

  /// Cross products below this are treated as "aligned": it rejects quads
  /// whose corner angle is too flat to define a stable perspective.
  static const double _minTurn = 1e-9;
}
