import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/quad.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

/// Opens the fine-tuning sheet (brightness, contrast, saturation) for one
/// page. Returns the new adjustments, or null when the user dismisses it.
Future<ImageAdjustments?> showAdjustmentsSheet(
  BuildContext context, {
  required String sourcePath,
  required ImageAdjustments initial,
  required ScanMode mode,
  Quad? quad,
}) => showModalBottomSheet<ImageAdjustments>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _AdjustmentsSheet(
    sourcePath: sourcePath,
    initial: initial,
    mode: mode,
    quad: quad,
  ),
);

class _AdjustmentsSheet extends ConsumerStatefulWidget {
  const _AdjustmentsSheet({
    required this.sourcePath,
    required this.initial,
    required this.mode,
    this.quad,
  });

  final String sourcePath;
  final ImageAdjustments initial;
  final ScanMode mode;
  final Quad? quad;

  @override
  ConsumerState<_AdjustmentsSheet> createState() => _AdjustmentsSheetState();
}

class _AdjustmentsSheetState extends ConsumerState<_AdjustmentsSheet> {
  late ImageAdjustments _value = widget.initial;
  late Future<Result<Uint8List>> _preview = _render();

  /// The preview is recomputed when a slider is released, not on every
  /// frame of the drag: rendering a page takes a moment.
  Future<Result<Uint8List>> _render() => ref
      .read(imageProcessorProvider)
      .preview(
        ImagePreviewRequest(
          sourcePath: widget.sourcePath,
          quad: widget.quad,
          adjustments: _value,
          mode: widget.mode,
          maxLongEdge: 720,
        ),
      );

  void _apply(ImageAdjustments value, {required bool render}) {
    setState(() {
      _value = value;
      if (render) _preview = _render();
    });
  }

  Widget _slider(
    String label,
    IconData icon,
    double current,
    ImageAdjustments Function(double value) update,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 88,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Slider(
            value: current,
            min: -1,
            max: 1,
            divisions: 40,
            label: (current * 100).round().toString(),
            semanticFormatterCallback: (value) =>
                '$label ${(value * 100).round()}',
            onChanged: (value) => _apply(update(value), render: false),
            onChangeEnd: (value) => _apply(update(value), render: true),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final core = context.coreL10n;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 220,
              child: FutureBuilder<Result<Uint8List>>(
                future: _preview,
                builder: (context, snapshot) {
                  final result = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done ||
                      result == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return switch (result) {
                    Success(:final value) => Image.memory(
                      value,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                    Err() => const Center(
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  };
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _slider(
              l10n.adjustBrightness,
              Icons.brightness_6_outlined,
              _value.brightness,
              (value) => _value.copyWith(brightness: value),
            ),
            _slider(
              l10n.adjustContrast,
              Icons.contrast,
              _value.contrast,
              (value) => _value.copyWith(contrast: value),
            ),
            _slider(
              l10n.adjustSaturation,
              Icons.palette_outlined,
              _value.saturation,
              (value) => _value.copyWith(saturation: value),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => _apply(
                    _value.copyWith(brightness: 0, contrast: 0, saturation: 0),
                    render: true,
                  ),
                  child: Text(l10n.adjustReset),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(core.actionCancel),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_value),
                  child: Text(core.actionConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
