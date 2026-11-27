import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/features/ai_assistant/l10n/generated/ai_localizations.dart';
import 'package:md_scanner/features/id_scanner/l10n/generated/id_scanner_localizations.dart';
import 'package:md_scanner/features/ocr/l10n/generated/ocr_localizations.dart';
import 'package:md_scanner/features/pdf_tools/presentation/pdf_tool.dart';
import 'package:md_scanner/features/qr_scanner/l10n/generated/qr_localizations.dart';
import 'package:md_scanner/features/security/l10n/generated/security_localizations.dart';

class _ToolEntry {
  const _ToolEntry(this.icon, this.title, this.hint, this.route);

  final IconData icon;
  final String title;
  final String hint;
  final String route;
}

/// Hub listing every tool of the app, grouped by family.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ocr = OcrLocalizations.of(context);
    final qr = QrLocalizations.of(context);
    final ai = AiLocalizations.of(context);
    final id = IdScannerLocalizations.of(context);
    final security = SecurityLocalizations.of(context);

    final sections = <(String, List<_ToolEntry>)>[
      (
        l10n.toolsSectionText,
        [
          _ToolEntry(
            Icons.text_snippet_outlined,
            ocr.ocrTitle,
            ocr.ocrToolHint,
            AppRoutes.ocr,
          ),
          _ToolEntry(
            Icons.badge_outlined,
            id.idTitle,
            id.idHint,
            AppRoutes.idScanner,
          ),
          _ToolEntry(
            Icons.auto_awesome_outlined,
            ai.aiTitle,
            ai.aiHint,
            AppRoutes.aiAssistant,
          ),
        ],
      ),
      (
        l10n.toolsSectionCodes,
        [
          _ToolEntry(
            Icons.qr_code_scanner,
            qr.qrScanTitle,
            qr.qrScanHint,
            AppRoutes.qrScanner,
          ),
          _ToolEntry(
            Icons.barcode_reader,
            qr.barcodeScanTitle,
            qr.barcodeScanHint,
            AppRoutes.barcodeScanner,
          ),
          _ToolEntry(
            Icons.qr_code_2,
            qr.qrGeneratorTitle,
            qr.qrGeneratorHint,
            AppRoutes.qrGenerator,
          ),
          _ToolEntry(
            Icons.view_week_outlined,
            qr.barcodeGeneratorTitle,
            qr.barcodeGeneratorHint,
            AppRoutes.barcodeGenerator,
          ),
          _ToolEntry(
            Icons.history,
            qr.qrHistoryTitle,
            qr.qrHistoryHint,
            AppRoutes.codeHistory,
          ),
        ],
      ),
      (
        l10n.toolsSectionSecurity,
        [
          _ToolEntry(
            Icons.shield_outlined,
            security.vaultTitle,
            security.vaultHint,
            AppRoutes.vault,
          ),
        ],
      ),
      (
        l10n.toolsSectionPdf,
        [
          for (final tool in PdfTool.values)
            _ToolEntry(
              tool.icon,
              tool.title(l10n),
              tool.hint(l10n),
              AppRoutes.pdfTool(tool.id),
            ),
        ],
      ),
    ];

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.toolsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final (title, entries) in sections) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionHeader(title: title),
            ),
            for (final entry in entries)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: Icon(entry.icon, size: 20),
                ),
                title: Text(entry.title),
                subtitle: Text(entry.hint),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(entry.route),
              ),
          ],
        ],
      ),
    );
  }
}
