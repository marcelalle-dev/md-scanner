import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';

/// Width / height of the drawing area, matched by the stamp placed on the
/// page so the signature is not distorted.
const double kSignatureAspectRatio = 2.2;

const Color _ink = Color(0xFF0B1F3A);

/// Finger-drawing area for a handwritten signature.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key});

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  bool get isEmpty => _strokes.every((stroke) => stroke.length < 2);

  void clear() => setState(_strokes.clear);

  /// Renders the strokes on a transparent background. Returns null when
  /// nothing was drawn.
  Future<Uint8List?> toPng({double pixelRatio = 3}) async {
    if (isEmpty || _size.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _paintStrokes(canvas, _strokes);
    final image = await recorder.endRecording().toImage(
      (_size.width * pixelRatio).round(),
      (_size.height * pixelRatio).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: kSignatureAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.control,
          border: Border.all(color: scheme.outline),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.control,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _size = constraints.biggest;
              return GestureDetector(
                onPanStart: (details) =>
                    setState(() => _strokes.add([details.localPosition])),
                onPanUpdate: (details) =>
                    setState(() => _strokes.last.add(details.localPosition)),
                child: CustomPaint(
                  painter: _SignaturePainter(
                    _strokes,
                    _strokes.fold(0, _count),
                  ),
                  size: Size.infinite,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static int _count(int total, List<Offset> stroke) => total + stroke.length;
}

void _paintStrokes(Canvas canvas, List<List<Offset>> strokes) {
  final paint = Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final stroke in strokes) {
    if (stroke.length < 2) continue;
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final point in stroke.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes, this.pointCount);

  final List<List<Offset>> strokes;

  /// The stroke lists are mutated in place: the count detects new points.
  final int pointCount;

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(canvas, strokes);

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) =>
      oldDelegate.pointCount != pointCount;
}
