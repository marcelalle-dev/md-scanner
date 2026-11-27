import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/ads/presentation/ad_banner_slot.dart';
import 'package:md_scanner/features/document_vault/presentation/document_actions.dart';
import 'package:md_scanner/features/document_vault/presentation/documents_screen.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const DocumentQuery _recentQuery = DocumentQuery(limit: 5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = documentListProvider(_recentQuery);
    final recent = ref.watch(provider);

    return Scaffold(
      bottomNavigationBar: const AdBannerSlot(),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/brand/icon_foreground.png',
                  width: 56,
                  height: 56,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.coreL10n.appName,
                        style: theme.textTheme.headlineSmall,
                      ),
                      Text(l10n.homeTagline, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: ToolCard(
                    icon: Icons.document_scanner_outlined,
                    title: l10n.homeScan,
                    onTap: () => context.go(AppRoutes.scanner),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: ToolCard(
                    icon: Icons.upload_file_outlined,
                    title: l10n.homeImport,
                    onTap: () => importDocument(context, ref),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: ToolCard(
                    icon: Icons.picture_as_pdf_outlined,
                    title: l10n.homePdfTools,
                    onTap: () => context.go(AppRoutes.tools),
                  ),
                ),
              ],
            ),
            SectionHeader(
              title: l10n.homeRecent,
              trailing: TextButton(
                onPressed: () => context.go(AppRoutes.documents),
                child: Text(l10n.homeSeeAll),
              ),
            ),
            SizedBox(
              height: recent.value?.isEmpty ?? true ? 280 : null,
              child: AsyncValueView<List<DocumentEntity>>(
                value: recent,
                onRetry: () => ref.invalidate(provider),
                data: (items) => items.isEmpty
                    ? EmptyState(
                        icon: Icons.description_outlined,
                        title: l10n.homeEmptyTitle,
                        message: l10n.homeEmptyMessage,
                        action: FilledButton.icon(
                          onPressed: () => context.go(AppRoutes.scanner),
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: Text(l10n.homeScan),
                        ),
                      )
                    : Card(
                        child: Column(
                          children: [
                            for (final document in items)
                              DocumentTile(
                                document: document,
                                onTap: () => context.push(
                                  AppRoutes.documentDetails(document.id),
                                ),
                              ),
                          ],
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
