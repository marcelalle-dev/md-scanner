import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_engine.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:md_scanner/features/pdf_tools/presentation/signature_pad.dart';

/// Share of the page width taken by a signature.
const double kSignatureWidthFraction = 0.37;

/// Rectangle a signature occupies on a page of the given aspect ratio
/// (width / height), so that the drawing keeps its proportions.
PdfNormalizedRect signatureRect({
  required double left,
  required double top,
  required double pageAspectRatio,
}) {
  final height =
      kSignatureWidthFraction * pageAspectRatio / kSignatureAspectRatio;
  return PdfNormalizedRect(
    left: left.clamp(0.0, 1 - kSignatureWidthFraction).toDouble(),
    top: top.clamp(0.0, 1 - height).toDouble(),
    width: kSignatureWidthFraction,
    height: height,
  );
}

/// Shows the target page and lets the user tap or drag to choose where the
/// signature or the text goes. Reports the position through [onChanged];
/// null means the page could not be shown and the default position applies.
class PagePlacement extends ConsumerStatefulWidget {
  const PagePlacement({
    required this.pdfPath,
    required this.pageNumber,
    required this.forSignature,
    required this.onChanged,
    super.key,
  });

  final String pdfPath;

  /// 1-based; null targets the last page.
  final int? pageNumber;
  final bool forSignature;
  final ValueChanged<PdfNormalizedRect?> onChanged;

  @override
  ConsumerState<PagePlacement> createState() => _PagePlacementState();
}

class _PagePlacementState extends ConsumerState<PagePlacement> {
  late Future<RenderedPage> _page = _render();
  String? _temporaryFile;
  PdfNormalizedRect? _rect;

  @override
  void didUpdateWidget(PagePlacement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath ||
        oldWidget.pageNumber != widget.pageNumber) {
      _rect = null;
      _page = _render();
    }
  }

  @override
  void dispose() {
    _deleteTemporary();
    super.dispose();
  }

  void _deleteTemporary() {
    final path = _temporaryFile;
    _temporaryFile = null;
    if (path != null) ref.read(fileStorageProvider).delete(path);
  }

  Future<RenderedPage> _render() async {
    _deleteTemporary();
    final engine = ref.read(pdfEngineProvider);
    final storage = ref.read(fileStorageProvider);
    T unwrap<T>(Result<T> result) => switch (result) {
      Success<T>(:final value) => value,
      Err<T>(:final failure) => throw FailureException(failure),
    };
    try {
      final info = unwrap(await engine.inspect(widget.pdfPath));
      final number = widget.pageNumber ?? info.pageCount;
      if (number < 1 || number > info.pageCount) {
        throw const FailureException(
          PdfFailure(PdfFailureKind.invalidPageRange),
        );
      }
      final target = storage.allocate(StorageArea.temp, extension: 'jpg');
      _temporaryFile = target;
      final page = unwrap(
        await engine.renderPage(
          path: widget.pdfPath,
          pageIndex: number - 1,
          outputPath: storage.absolutePath(target),
          maxLongEdge: 1000,
        ),
      );
      _report(_initial(page.width / page.height));
      return page;
    } catch (_) {
      _report(null);
      rethrow;
    }
  }

  PdfNormalizedRect _initial(double aspect) => widget.forSignature
      ? signatureRect(left: 0.55, top: 0.82, pageAspectRatio: aspect)
      : const PdfNormalizedRect(left: 0.1, top: 0.88, width: 0.5, height: 0.03);

  void _report(PdfNormalizedRect? rect) {
    _rect = rect;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(rect);
    });
  }

  void _moveTo(Offset position, Size size, double aspect) {
    final current = _rect ?? _initial(aspect);
    final left = position.dx / size.width - current.width / 2;
    final top = position.dy / size.height - current.height / 2;
    final moved = widget.forSignature
        ? signatureRect(left: left, top: top, pageAspectRatio: aspect)
        : PdfNormalizedRect(
            left: left.clamp(0.0, 1 - current.width).toDouble(),
            top: top.clamp(0.0, 1 - current.height).toDouble(),
            width: current.width,
            height: current.height,
          );
    setState(() => _rect = moved);
    widget.onChanged(moved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<RenderedPage>(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return InfoBanner(
            message: l10n.placeUnavailable,
            tone: InfoBannerTone.warning,
          );
        }
        final page = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || page == null) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final aspect = page.width / page.height;
        final rect = _rect ?? _initial(aspect);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.placeHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: AspectRatio(
                aspectRatio: aspect,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    return GestureDetector(
                      onTapDown: (details) =>
                          _moveTo(details.localPosition, size, aspect),
                      onPanUpdate: (details) =>
                          _moveTo(details.localPosition, size, aspect),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.file(
                                File(page.path),
                                fit: BoxFit.fill,
                              ),
                            ),
                            Positioned(
                              left: rect.left * size.width,
                              top: rect.top * size.height,
                              width: rect.width * size.width,
                              height: rect.height * size.height,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.secondary.withValues(
                                    alpha: 0.22,
                                  ),
                                  border: Border.all(
                                    color: scheme.secondary,
                                    width: 2,
                                  ),
                                ),
                                child: widget.forSignature
                                    ? Icon(
                                        Icons.draw_outlined,
                                        size: 16,
                                        color: scheme.secondary,
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
