import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/qr_scanner/data/code_history_repository.dart';
import 'package:md_scanner/features/qr_scanner/domain/code_content.dart';
import 'package:md_scanner/features/qr_scanner/l10n/generated/qr_localizations.dart';
import 'package:md_scanner/features/qr_scanner/presentation/code_result_sheet.dart';

class CodeHistoryScreen extends ConsumerStatefulWidget {
  const CodeHistoryScreen({super.key});

  @override
  ConsumerState<CodeHistoryScreen> createState() => _CodeHistoryScreenState();
}

class _CodeHistoryScreenState extends ConsumerState<CodeHistoryScreen> {
  CodeHistoryKind? _kind;

  @override
  Widget build(BuildContext context) {
    final l10n = QrLocalizations.of(context);
    final core = context.coreL10n;
    final provider = codeHistoryProvider(_kind);
    final entries = ref.watch(provider);
    final repository = ref.read(codeHistoryRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.qrHistoryTitle),
        actions: [
          if (entries.value?.isNotEmpty ?? false)
            IconButton(
              tooltip: l10n.historyClear,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: l10n.historyClearConfirm,
                  confirmLabel: core.actionDelete,
                  destructive: true,
                );
                if (confirmed) await repository.clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: SegmentedButton<CodeHistoryKind?>(
              segments: [
                ButtonSegment(value: null, label: Text(l10n.historyAll)),
                ButtonSegment(
                  value: CodeHistoryKind.scanned,
                  label: Text(l10n.historyScanned),
                ),
                ButtonSegment(
                  value: CodeHistoryKind.generated,
                  label: Text(l10n.historyGenerated),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _kind = value.first),
            ),
          ),
          Expanded(
            child: AsyncValueView<List<CodeHistoryEntry>>(
              value: entries,
              onRetry: () => ref.invalidate(provider),
              data: (items) => items.isEmpty
                  ? EmptyState(icon: Icons.history, title: l10n.historyEmpty)
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final entry = items[index];
                        final type = CodeContentParser.parse(
                          entry.content,
                        ).type;
                        return Dismissible(
                          key: ValueKey(entry.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: AlignmentDirectional.centerEnd,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                            ),
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: const Icon(Icons.delete_outline),
                          ),
                          onDismissed: (_) => repository.delete(entry.id),
                          child: ListTile(
                            leading: Icon(
                              entry.kind == CodeHistoryKind.generated
                                  ? Icons.qr_code_2
                                  : codeTypeIcon(type),
                            ),
                            title: Text(
                              entry.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${entry.format} · ${formatDateTime(core.localeName, entry.date)}',
                            ),
                            onTap: () => showCodeResultSheet(
                              context,
                              rawValue: entry.content,
                              format: entry.format,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
