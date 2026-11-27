import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/l10n/failure_messages.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/progress.dart';
import 'package:md_scanner/features/ads/data/ads_service.dart';
import 'package:md_scanner/features/document_scanner/presentation/scan_session_controller.dart';
import 'package:md_scanner/features/document_scanner/presentation/scanner_screen.dart';
import 'package:md_scanner/features/image_editor/domain/image_adjustments.dart';
import 'package:md_scanner/features/image_editor/domain/image_models.dart';
import 'package:md_scanner/features/image_editor/domain/image_processor.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';
import 'package:md_scanner/features/image_editor/presentation/adjustments_sheet.dart';
import 'package:md_scanner/features/image_editor/presentation/crop_screen.dart';

String scanFilterLabel(AppLocalizations l10n, ScanFilter filter) =>
    switch (filter) {
      ScanFilter.original => l10n.filterOriginal,
      ScanFilter.enhanced => l10n.filterEnhanced,
      ScanFilter.grayscale => l10n.filterGrayscale,
      ScanFilter.blackAndWhite => l10n.filterBlackAndWhite,
      ScanFilter.readability => l10n.filterReadability,
      ScanFilter.noShadow => l10n.filterNoShadow,
    };

/// Multi-page management before saving: reorder, rotate, filter, duplicate,
/// delete, add pages, then export as a PDF or as images.
class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({super.key});

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  final TextEditingController _name = TextEditingController();
  final Map<ScanPage, Future<Result<Uint8List>>> _previews = {};
  bool _nameInitialized = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<Result<Uint8List>> _preview(ScanPage page, ScanMode mode) {
    return _previews.putIfAbsent(
      page,
      () => ref
          .read(imageProcessorProvider)
          .preview(
            ImagePreviewRequest(
              sourcePath: page.sourcePath,
              quad: page.quad,
              adjustments: page.adjustments,
              mode: mode,
              maxLongEdge: 720,
            ),
          ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.reviewDiscardTitle,
      message: l10n.reviewDiscardMessage,
      confirmLabel: l10n.reviewDiscard,
      destructive: true,
    );
    if (confirmed) await ref.read(scanSessionProvider.notifier).discard();
    return confirmed;
  }

  Future<void> _addPages(ScanMode mode, {required bool fromCamera}) =>
      startCapture(context, ref, mode: mode, fromCamera: fromCamera);

  Future<void> _export({required bool asPdf}) async {
    final l10n = AppLocalizations.of(context);
    final core = context.coreL10n;
    final controller = ref.read(scanSessionProvider.notifier);
    final name = _name.text.trim();
    final total = ref.read(scanSessionProvider)?.pages.length ?? 0;

    void report(ProgressController progress, int done, int count) =>
        progress.report(done / count, detail: '$done / $count');

    if (asPdf) {
      final result = await runWithProgress(
        context,
        message: l10n.reviewExporting,
        task: (progress) => controller.exportPdf(
          name,
          onProgress: (done, count) => report(progress, done, count),
        ),
      );
      if (!mounted) return;
      switch (result) {
        case Success(:final value):
          context.showMessage(core.savedToLibrary);
          ref.read(adsServiceProvider).taskCompleted();
          context.go(AppRoutes.documents);
          await context.push(AppRoutes.documentDetails(value.id));
        case Err(:final failure):
          context.showFailure(failure);
      }
      return;
    }

    final result = await runWithProgress(
      context,
      message: l10n.reviewExporting,
      task: (progress) => controller.exportImages(
        name,
        onProgress: (done, count) => report(progress, done, count),
      ),
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        context.showMessage(l10n.reviewImagesSaved(total));
        context.go(AppRoutes.documents);
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(scanSessionProvider);

    if (session == null || session.pages.isEmpty) {
      // The session ended (saved, discarded, or last page removed).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.canPop()) context.pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    if (!_nameInitialized) {
      _nameInitialized = true;
      _name.text = l10n.reviewDefaultName(
        DateFormat('yyyy-MM-dd HH.mm').format(DateTime.now()),
      );
    }
    _previews.removeWhere((page, _) => !session.pages.contains(page));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && navigator.canPop()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.reviewTitle),
          actions: [
            IconButton(
              tooltip: l10n.reviewAddCamera,
              icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: () => _addPages(session.mode, fromCamera: true),
            ),
            IconButton(
              tooltip: l10n.reviewAddGallery,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () => _addPages(session.mode, fromCamera: false),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.reviewName,
                  counterText: '',
                  prefixIcon: Icon(scanModeIcon(session.mode)),
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: session.pages.length,
                onReorderItem: (oldIndex, newIndex) => ref
                    .read(scanSessionProvider.notifier)
                    .reorder(oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final page = session.pages[index];
                  return _PageCard(
                    key: ValueKey(page.id),
                    index: index,
                    page: page,
                    preview: _preview(page, session.mode),
                    mode: session.mode,
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _export(asPdf: false),
                        child: Text(
                          l10n.reviewExportImages,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _export(asPdf: true),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          l10n.reviewExportPdf,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageCard extends ConsumerWidget {
  const _PageCard({
    required this.index,
    required this.page,
    required this.preview,
    required this.mode,
    super.key,
  });

  final int index;
  final ScanPage page;
  final Future<Result<Uint8List>> preview;
  final ScanMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(scanSessionProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.control,
                child: SizedBox(
                  width: 96,
                  height: 128,
                  child: FutureBuilder<Result<Uint8List>>(
                    future: preview,
                    builder: (context, snapshot) {
                      final result = snapshot.data;
                      if (result == null) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      return switch (result) {
                        Success(:final value) => Image.memory(
                          value,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                        Err(:final failure) => Tooltip(
                          message: failureMessage(context, failure),
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      };
                    },
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reviewPage(index + 1),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (page.cropAttempted)
                      Text(
                        page.quad == null
                            ? l10n.reviewCropNone
                            : l10n.reviewCropAuto,
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: AppSpacing.xxs),
                    PopupMenuButton<ScanFilter>(
                      tooltip: l10n.reviewFilter,
                      initialValue: page.adjustments.filter,
                      onSelected: (filter) =>
                          controller.setFilter(page.id, filter),
                      itemBuilder: (context) => [
                        for (final filter in ScanFilter.values)
                          PopupMenuItem(
                            value: filter,
                            child: Text(scanFilterLabel(l10n, filter)),
                          ),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.auto_fix_high, size: 16),
                        label: Text(
                          scanFilterLabel(l10n, page.adjustments.filter),
                        ),
                      ),
                    ),
                    Wrap(
                      children: [
                        IconButton(
                          tooltip: l10n.reviewRotate,
                          icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                          onPressed: () => controller.rotate(page.id),
                        ),
                        IconButton(
                          tooltip: l10n.reviewAdjust,
                          icon: const Icon(Icons.tune),
                          onPressed: () async {
                            final adjusted = await showAdjustmentsSheet(
                              context,
                              sourcePath: page.sourcePath,
                              initial: page.adjustments,
                              mode: mode,
                              quad: page.quad,
                            );
                            if (adjusted != null) {
                              controller.setAdjustments(page.id, adjusted);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: l10n.reviewCrop,
                          icon: const Icon(Icons.crop),
                          onPressed: () async {
                            final result = await showCropScreen(
                              context,
                              sourcePath: page.sourcePath,
                              initial: page.quad,
                            );
                            if (result != null) {
                              controller.setQuad(page.id, result.quad);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: l10n.reviewDuplicate,
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () => controller.duplicate(page.id),
                        ),
                        IconButton(
                          tooltip: l10n.reviewDeletePage,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => controller.remove(page.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
