import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/features/qr_scanner/domain/code_content.dart';
import 'package:md_scanner/features/qr_scanner/l10n/generated/qr_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

String codeTypeLabel(QrLocalizations l10n, CodeContentType type) =>
    switch (type) {
      CodeContentType.url => l10n.typeUrl,
      CodeContentType.wifi => l10n.typeWifi,
      CodeContentType.email => l10n.typeEmail,
      CodeContentType.phone => l10n.typePhone,
      CodeContentType.sms => l10n.typeSms,
      CodeContentType.geo => l10n.typeGeo,
      CodeContentType.contact => l10n.typeContact,
      CodeContentType.event => l10n.typeEvent,
      CodeContentType.product => l10n.typeProduct,
      CodeContentType.text => l10n.typeText,
    };

IconData codeTypeIcon(CodeContentType type) => switch (type) {
  CodeContentType.url => Icons.link,
  CodeContentType.wifi => Icons.wifi,
  CodeContentType.email => Icons.mail_outline,
  CodeContentType.phone => Icons.phone_outlined,
  CodeContentType.sms => Icons.sms_outlined,
  CodeContentType.geo => Icons.place_outlined,
  CodeContentType.contact => Icons.contact_page_outlined,
  CodeContentType.event => Icons.event_outlined,
  CodeContentType.product => Icons.shopping_bag_outlined,
  CodeContentType.text => Icons.notes_outlined,
};

String urlRiskLabel(QrLocalizations l10n, UrlRisk risk) => switch (risk) {
  UrlRisk.noTls => l10n.riskNoTls,
  UrlRisk.ipHost => l10n.riskIpHost,
  UrlRisk.punycode => l10n.riskPunycode,
  UrlRisk.userInfo => l10n.riskUserInfo,
  UrlRisk.manySubdomains => l10n.riskManySubdomains,
  UrlRisk.shortener => l10n.riskShortener,
  UrlRisk.unusualPort => l10n.riskPort,
  UrlRisk.veryLong => l10n.riskLong,
  UrlRisk.executable => l10n.riskExecutable,
};

/// Shows what was read. Nothing is ever opened automatically: a link shows
/// its full address and a safety verdict, and opening needs a second tap.
Future<void> showCodeResultSheet(
  BuildContext context, {
  required String rawValue,
  required String format,
  bool linearBarcode = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CodeResultSheet(
      content: CodeContentParser.parse(rawValue, linearBarcode: linearBarcode),
      format: format,
    ),
  );
}

class _CodeResultSheet extends StatelessWidget {
  const _CodeResultSheet({required this.content, required this.format});

  final CodeContent content;
  final String format;

  Uri? get _openTarget => switch (content.type) {
    CodeContentType.product => Uri.https('www.google.com', '/search', {
      'q': content.raw.trim(),
    }),
    _ => content.uri,
  };

  Future<void> _open(BuildContext context, Uri target) async {
    final l10n = QrLocalizations.of(context);
    final core = context.coreL10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.qrOpenConfirmTitle),
        content: SelectableText(target.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(core.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.qrOpen),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    var opened = false;
    try {
      opened = await launchUrl(target, mode: LaunchMode.externalApplication);
    } on PlatformException {
      opened = false;
    }
    if (!opened && context.mounted) context.showMessage(l10n.qrOpenFailed);
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      context.showMessage(context.coreL10n.copiedToClipboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = QrLocalizations.of(context);
    final core = context.coreL10n;
    final theme = Theme.of(context);
    final target = _openTarget;
    final verdict = target == null ? null : UrlSafetyAnalyzer.analyze(target);
    final canOpen = target != null && verdict!.canOpen;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(codeTypeIcon(content.type)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    codeTypeLabel(l10n, content.type),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(l10n.qrFormat(format), style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: AppRadius.control,
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content.type == CodeContentType.wifi
                      ? [
                          l10n.wifiNetwork(content.wifiName ?? ''),
                          if ((content.wifiPassword ?? '').isNotEmpty)
                            l10n.wifiPassword(content.wifiPassword!),
                        ].join('\n')
                      : content.raw,
                ),
              ),
            ),
            if (content.type == CodeContentType.url && verdict != null) ...[
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(
                tone: switch (verdict.level) {
                  UrlSafetyLevel.safe => InfoBannerTone.info,
                  UrlSafetyLevel.caution => InfoBannerTone.warning,
                  UrlSafetyLevel.dangerous ||
                  UrlSafetyLevel.blocked => InfoBannerTone.danger,
                },
                message: switch (verdict.level) {
                  UrlSafetyLevel.safe => l10n.qrSafe,
                  UrlSafetyLevel.blocked => l10n.qrBlocked,
                  UrlSafetyLevel.caution =>
                    '${l10n.qrCaution} ${verdict.risks.map((r) => urlRiskLabel(l10n, r)).join(', ')}.',
                  UrlSafetyLevel.dangerous =>
                    '${l10n.qrDangerous} ${verdict.risks.map((r) => urlRiskLabel(l10n, r)).join(', ')}.',
                },
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (canOpen)
                  FilledButton.icon(
                    onPressed: () => _open(context, target),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(
                      content.type == CodeContentType.product
                          ? l10n.productSearch
                          : l10n.qrOpen,
                    ),
                  ),
                if (content.type == CodeContentType.wifi &&
                    (content.wifiPassword ?? '').isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _copy(context, content.wifiPassword!),
                    icon: const Icon(Icons.key_outlined),
                    label: Text(l10n.wifiCopyPassword),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _copy(context, content.raw),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(core.actionCopy),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      SharePlus.instance.share(ShareParams(text: content.raw)),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(core.actionShare),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
