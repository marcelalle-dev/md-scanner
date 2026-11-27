import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';

/// Result of the crop screen. [quad] null means "keep the whole page".
class CropResult {
  const CropResult(this.quad);

  final Quad? quad;
}

/// Opens the manual crop screen for the image at [sourcePath]. Returns null
/// when the user backs out without confirming.
Future<CropResult?> showCropScreen(
  BuildContext context, {
  required String sourcePath,
  Quad? initial,
}) => Navigator.of(context).push<CropResult>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (context) => CropScreen(sourcePath: sourcePath, initial: initial),
  ),
);

/// Loads a screen-sized rendering of the untouched source image.
final _cropPreviewProvider = FutureProvider.autoDispose
    .family<({Uint8List bytes, double aspectRatio}), String>((ref, path) async {
      final result = await ref
          .watch(imageProcessorProvider)
          .preview(ImagePreviewRequest(sourcePath: path, maxLongEdge: 1280));
      final bytes = switch (result) {
        Success(:final value) => value,
        Err(:final failure) => throw FailureException(failure),
      };
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return (bytes: bytes, aspectRatio: ratio);
    });

/// Manual adjustment of the four corners of the document.
class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({required this.sourcePath, this.initial, super.key});

  final String sourcePath;
  final Quad? initial;

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  /// Corners in order: top-left, top-right, bottom-right, bottom-left.
  late List<NormalizedPoint> _corners = _cornersOf(
    widget.initial ?? _defaultQuad,
  );
  int? _dragged;

  static const Quad _defaultQuad = Quad(
    topLeft: NormalizedPoint(0.08, 0.08),
    topRight: NormalizedPoint(0.92, 0.08),
    bottomRight: NormalizedPoint(0.92, 0.92),
    bottomLeft: NormalizedPoint(0.08, 0.92),
  );

  static List<NormalizedPoint> _cornersOf(Quad quad) => [
    quad.topLeft,
    quad.topRight,
    quad.bottomRight,
    quad.bottomLeft,
  ];

  Quad get _quad => Quad(
    topLeft: _corners[0],
    topRight: _corners[1],
    bottomRight: _corners[2],
    bottomLeft: _corners[3],
  );

  void _startDrag(Offset position, Size size) {
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < _corners.length; i++) {
      final corner = Offset(
        _corners[i].x * size.width,
        _corners[i].y * size.height,
      );
      final distance = (corner - position).distance;
      if (distance < best) {
        best = distance;
        nearest = i;
      }
    }
    _dragged = nearest;
  }

  void _drag(Offset position, Size size) {
    final index = _dragged;
    if (index == null) return;
    setState(() {
      _corners = [..._corners]
        ..[index] = NormalizedPoint(
          position.dx / size.width,
          position.dy / size.height,
        ).clamped();
    });
  }

  void _confirm() {
    final l10n = AppLocalizations.of(context);
    final quad = _quad;
    if (!quad.isConvex) {
      context.showMessage(l10n.cropInvalid);
      return;
    }
    Navigator.of(context).pop(CropResult(quad));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = ref.watch(_cropPreviewProvider(widget.sourcePath));
    final accent = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cropTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(const CropResult(null)),
            child: Text(l10n.cropReset),
          ),
        ],
      ),
      body: AsyncValueView<({Uint8List bytes, double aspectRatio})>(
        value: preview,
        onRetry: () => ref.invalidate(_cropPreviewProvider(widget.sourcePath)),
        data: (value) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(
                l10n.cropHint,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.biggest;
                        return GestureDetector(
                          onPanStart: (details) =>
                              _startDrag(details.localPosition, size),
                          onPanUpdate: (details) =>
                              _drag(details.localPosition, size),
                          onPanEnd: (_) => _dragged = null,
                          child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.none,
                            children: [
                              Image.memory(value.bytes, fit: BoxFit.fill),
                              CustomPaint(
                                painter: _QuadPainter(
                                  corners: _corners,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.crop),
                    label: Text(context.coreL10n.actionConfirm),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  const _QuadPainter({required this.corners, required this.color});

  final List<NormalizedPoint> corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      for (final corner in corners)
        Offset(corner.x * size.width, corner.y * size.height),
    ];
    final outline = Path()..addPolygon(points, true);
    // Dim everything outside the selected area.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        outline,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      outline,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final point in points) {
      canvas
        ..drawCircle(point, 14, Paint()..color = Colors.white)
        ..drawCircle(point, 10, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.color != color;
}
