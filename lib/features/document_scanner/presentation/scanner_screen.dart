import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/features/document_scanner/presentation/scan_session_controller.dart';
import 'package:md_scanner/features/image_editor/domain/scan_mode.dart';

String scanModeLabel(AppLocalizations l10n, ScanMode mode) => switch (mode) {
  ScanMode.document => l10n.modeDocument,
  ScanMode.receipt => l10n.modeReceipt,
  ScanMode.book => l10n.modeBook,
  ScanMode.whiteboard => l10n.modeWhiteboard,
  ScanMode.idCard => l10n.modeIdCard,
};

IconData scanModeIcon(ScanMode mode) => switch (mode) {
  ScanMode.document => Icons.description_outlined,
  ScanMode.receipt => Icons.receipt_long_outlined,
  ScanMode.book => Icons.menu_book_outlined,
  ScanMode.whiteboard => Icons.co_present_outlined,
  ScanMode.idCard => Icons.badge_outlined,
};

/// Starts a capture and reports the outcome. Shared by the scanner tab, the
/// home shortcuts and the "add pages" actions of the review screen.
Future<bool> startCapture(
  BuildContext context,
  WidgetRef ref, {
  required ScanMode mode,
  required bool fromCamera,
}) async {
  final controller = ref.read(scanSessionProvider.notifier);
  final result = fromCamera
      ? await controller.addFromCamera(mode)
      : await controller.addFromGallery(mode);
  if (!context.mounted) return false;
  switch (result) {
    case Success():
      return true;
    case Err(:final failure):
      context.showFailure(failure);
      return false;
  }
}

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  ScanMode _mode = ScanMode.document;
  bool _busy = false;

  Future<void> _capture({required bool fromCamera}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final added = await startCapture(
      context,
      ref,
      mode: _mode,
      fromCamera: fromCamera,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (added) await context.push(AppRoutes.scanPages);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scannerTitle)),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          SectionHeader(title: l10n.scannerMode),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final mode in ScanMode.values)
                ChoiceChip(
                  avatar: Icon(scanModeIcon(mode), size: 18),
                  label: Text(scanModeLabel(l10n, mode)),
                  selected: _mode == mode,
                  showCheckmark: false,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _mode = mode),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _busy ? null : () => _capture(fromCamera: true),
            icon: const Icon(Icons.document_scanner_outlined),
            label: Text(l10n.scannerStart),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _capture(fromCamera: false),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(l10n.scannerImport),
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.lg),
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.scannerPreparing, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.lg),
          InfoBanner(message: l10n.scannerHint),
        ],
      ),
    );
  }
}
