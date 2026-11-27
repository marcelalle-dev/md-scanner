// Draws the MD SCANNER logo and writes the brand images used by
// flutter_launcher_icons and flutter_native_splash.
//
// The logo is geometric and fully described here: a white page with a folded
// corner, framed by four viewfinder brackets and crossed by a scan line.
//
// Usage:
//   dart run tool/generate_brand_assets.dart
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
import 'dart:io';

import 'package:image/image.dart' as img;

const String _outputDirectory = 'assets/brand';

/// Shapes are rasterized at this multiple of the target size, then averaged
/// down, which gives smooth edges without an anti-aliasing rasterizer.
const int _supersampling = 4;

typedef _Rgb = (int r, int g, int b);

const _Rgb _nightBlue = (0x0B, 0x1F, 0x3A);
const _Rgb _nightBlueSoft = (0x16, 0x30, 0x5A);
const _Rgb _electricBlue = (0x1F, 0x6B, 0xFF);
const _Rgb _paper = (0xFF, 0xFF, 0xFF);
const _Rgb _paperShade = (0xBF, 0xD0, 0xF5);

class _Canvas {
  _Canvas(this.size)
    : image = img.Image(width: size, height: size, numChannels: 4);

  final int size;
  final img.Image image;

  void fillVerticalGradient(_Rgb top, _Rgb bottom) {
    for (var y = 0; y < size; y++) {
      final t = y / (size - 1);
      final r = (top.$1 + (bottom.$1 - top.$1) * t).round();
      final g = (top.$2 + (bottom.$2 - top.$2) * t).round();
      final b = (top.$3 + (bottom.$3 - top.$3) * t).round();
      for (var x = 0; x < size; x++) {
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }
  }

  /// Fills (or clears, when [color] is null) a rounded rectangle given in
  /// fractions of the canvas size.
  void roundRect(
    double left,
    double top,
    double right,
    double bottom,
    double radius, {
    required _Rgb? color,
  }) {
    final x1 = (left * size).round();
    final y1 = (top * size).round();
    final x2 = (right * size).round();
    final y2 = (bottom * size).round();
    final r = radius * size;
    for (var y = y1; y < y2; y++) {
      for (var x = x1; x < x2; x++) {
        final dx = x < x1 + r ? x1 + r - x : (x > x2 - r ? x - (x2 - r) : 0.0);
        final dy = y < y1 + r ? y1 + r - y : (y > y2 - r ? y - (y2 - r) : 0.0);
        if (dx * dx + dy * dy > r * r) continue;
        _paint(x, y, color);
      }
    }
  }

  /// Fills (or clears) the right triangle whose right angle sits at
  /// ([cornerX], [cornerY]) with legs of length [leg] going left and down
  /// when [towardCorner] is true, i.e. the part cut off a page corner.
  void cornerTriangle(
    double cornerX,
    double cornerY,
    double leg, {
    required bool towardCorner,
    required _Rgb? color,
  }) {
    final x0 = ((cornerX - leg) * size).round();
    final y0 = (cornerY * size).round();
    final length = (leg * size).round();
    for (var dy = 0; dy < length; dy++) {
      for (var dx = 0; dx < length; dx++) {
        final outside = dx > dy;
        if (outside != towardCorner) continue;
        _paint(x0 + dx, y0 + dy, color);
      }
    }
  }

  void _paint(int x, int y, _Rgb? color) {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    if (color == null) {
      image.setPixelRgba(x, y, 0, 0, 0, 0);
    } else {
      image.setPixelRgba(x, y, color.$1, color.$2, color.$3, 255);
    }
  }

  img.Image downsampled(int targetSize) => img.copyResize(
    image,
    width: targetSize,
    height: targetSize,
    interpolation: img.Interpolation.average,
  );
}

/// Draws the logo. [scale] grows it around the centre; [monochrome] renders a
/// single-colour silhouette (details become holes) for Android themed icons.
void _drawLogo(_Canvas canvas, {double scale = 1, bool monochrome = false}) {
  double at(double value) => 0.5 + (value - 0.5) * scale;
  double len(double value) => value * scale;

  final accent = monochrome ? _paper : _electricBlue;

  const pageLeft = 0.36, pageRight = 0.64, pageTop = 0.31, pageBottom = 0.69;
  canvas.roundRect(
    at(pageLeft),
    at(pageTop),
    at(pageRight),
    at(pageBottom),
    len(0.026),
    color: _paper,
  );

  const fold = 0.085;
  canvas.cornerTriangle(
    at(pageRight),
    at(pageTop),
    len(fold),
    towardCorner: true,
    color: null,
  );
  canvas.cornerTriangle(
    at(pageRight),
    at(pageTop),
    len(fold),
    towardCorner: false,
    color: monochrome ? null : _paperShade,
  );

  const lineHeight = 0.017;
  for (final (y, right) in [(0.415, 0.545), (0.585, 0.60), (0.632, 0.53)]) {
    canvas.roundRect(
      at(0.40),
      at(y),
      at(right),
      at(y + lineHeight),
      len(lineHeight / 2),
      color: monochrome ? null : _paperShade,
    );
  }

  const scanHeight = 0.028;
  if (monochrome) {
    canvas.roundRect(
      at(pageLeft),
      at(0.5 - scanHeight),
      at(pageRight),
      at(0.5 + scanHeight),
      0,
      color: null,
    );
  }
  canvas.roundRect(
    at(0.27),
    at(0.5 - scanHeight / 2),
    at(0.73),
    at(0.5 + scanHeight / 2),
    len(scanHeight / 2),
    color: accent,
  );

  const boxLeft = 0.25, boxRight = 0.75, boxTop = 0.22, boxBottom = 0.78;
  const arm = 0.10, stroke = 0.028;
  for (final (x, y, dx, dy) in [
    (boxLeft, boxTop, 1, 1),
    (boxRight, boxTop, -1, 1),
    (boxLeft, boxBottom, 1, -1),
    (boxRight, boxBottom, -1, -1),
  ]) {
    final horizontalEnd = x + dx * arm;
    final verticalEnd = y + dy * arm;
    final strokeX = x + dx * stroke;
    final strokeY = y + dy * stroke;
    canvas.roundRect(
      at(x < horizontalEnd ? x : horizontalEnd),
      at(y < strokeY ? y : strokeY),
      at(x < horizontalEnd ? horizontalEnd : x),
      at(y < strokeY ? strokeY : y),
      len(stroke / 2),
      color: accent,
    );
    canvas.roundRect(
      at(x < strokeX ? x : strokeX),
      at(y < verticalEnd ? y : verticalEnd),
      at(x < strokeX ? strokeX : x),
      at(y < verticalEnd ? verticalEnd : y),
      len(stroke / 2),
      color: accent,
    );
  }
}

void _write(String name, img.Image image) {
  final file = File('$_outputDirectory/$name');
  file.writeAsBytesSync(img.encodePng(image, level: 9));
  stdout.writeln('${file.path}  ${image.width}x${image.height}');
}

void main() {
  Directory(_outputDirectory).createSync(recursive: true);

  // Full icon: legacy launcher icon and Google Play listing icon.
  final icon = _Canvas(1024 * _supersampling)
    ..fillVerticalGradient(_nightBlueSoft, _nightBlue);
  _drawLogo(icon, scale: 1.22);
  final iconImage = icon.downsampled(1024);
  _write('icon.png', iconImage);
  _write(
    'play_store_icon.png',
    img.copyResize(
      iconImage,
      width: 512,
      height: 512,
      interpolation: img.Interpolation.average,
    ),
  );

  // Adaptive icon layers: content stays inside the central 66 % safe zone.
  final foreground = _Canvas(1024 * _supersampling);
  _drawLogo(foreground);
  _write('icon_foreground.png', foreground.downsampled(1024));

  final monochrome = _Canvas(1024 * _supersampling);
  _drawLogo(monochrome, monochrome: true);
  _write('icon_monochrome.png', monochrome.downsampled(1024));

  // Splash logo: transparent, shown on the night-blue / deep-black background.
  final splash = _Canvas(1152 * _supersampling);
  _drawLogo(splash);
  _write('splash_logo.png', splash.downsampled(1152));
}
