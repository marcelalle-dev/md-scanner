import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/document_vault/presentation/document_actions.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';

enum _TrashAction { restore, delete }

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  static const DocumentQuery _query = DocumentQuery(inTrash: true);

  Future<bool> _confirm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showConfirmDialog(
      context,
      title: l10n.trashConfirmTitle,
      message: l10n.trashConfirmMessage,
      confirmLabel: context.coreL10n.actionDelete,
      destructive: true,
    );
  }

  void _report(BuildContext context, Result<void> result) {
    final failure = result.failureOrNull;
    if (failure != null && context.mounted) context.showFailure(failure);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = documentListProvider(_query);
    final documents = ref.watch(provider);
    final repository = ref.read(documentRepositoryProvider);
    final hasItems = documents.value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trashTitle),
        actions: [
          if (hasItems)
            IconButton(
              tooltip: l10n.trashEmptyAll,
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () async {
                if (!await _confirm(context)) return;
                final result = await repository.emptyTrash();
                if (context.mounted) _report(context, result);
              },
            ),
        ],
      ),
      body: AsyncValueView<List<DocumentEntity>>(
        value: documents,
        onRetry: () => ref.invalidate(provider),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.delete_outline,
              title: l10n.trashEmpty,
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(indent: 76),
            itemBuilder: (context, index) {
              final document = items[index];
              return DocumentTile(
                document: document,
                trailing: PopupMenuButton<_TrashAction>(
                  tooltip: context.coreL10n.actionMore,
                  onSelected: (action) async {
                    switch (action) {
                      case _TrashAction.restore:
                        final result = await repository.restoreFromTrash([
                          document.id,
                        ]);
                        if (context.mounted) _report(context, result);
                      case _TrashAction.delete:
                        if (!await _confirm(context)) return;
                        final result = await repository.deletePermanently([
                          document.id,
                        ]);
                        if (context.mounted) _report(context, result);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _TrashAction.restore,
                      child: Text(l10n.trashRestore),
                    ),
                    PopupMenuItem(
                      value: _TrashAction.delete,
                      child: Text(l10n.trashDeleteForever),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
