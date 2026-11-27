import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/document_vault/presentation/document_actions.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:pdfrx/pdfrx.dart';

enum _Menu { rename, trash }

/// Preview of one document with its actions.
class DocumentDetailsScreen extends ConsumerWidget {
  const DocumentDetailsScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final core = context.coreL10n;
    final provider = documentByIdProvider(documentId);
    final document = ref.watch(provider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          document?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: document == null
            ? null
            : [
                IconButton(
                  tooltip: document.isFavorite
                      ? l10n.documentUnfavorite
                      : l10n.documentFavorite,
                  icon: Icon(
                    document.isFavorite ? Icons.star : Icons.star_outline,
                  ),
                  onPressed: () => toggleFavorite(context, ref, document),
                ),
                IconButton(
                  tooltip: core.actionShare,
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => shareDocument(context, ref, document),
                ),
                PopupMenuButton<_Menu>(
                  tooltip: core.actionMore,
                  onSelected: (choice) async {
                    switch (choice) {
                      case _Menu.rename:
                        await renameDocument(context, ref, document);
                      case _Menu.trash:
                        final moved = await trashDocument(
                          context,
                          ref,
                          document,
                        );
                        if (moved && context.mounted) context.pop();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _Menu.rename,
                      child: Text(l10n.documentRename),
                    ),
                    PopupMenuItem(
                      value: _Menu.trash,
                      child: Text(l10n.documentMoveToTrash),
                    ),
                  ],
                ),
              ],
      ),
      body: AsyncValueView<DocumentEntity>(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        data: (value) => Column(
          children: [
            Expanded(child: _Preview(document: value)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  [
                    value.fileType.extension.toUpperCase(),
                    formatFileSize(core, value.fileSize),
                    if (value.pageCount != null)
                      core.pageCount(value.pageCount!),
                    formatDateTime(core.localeName, value.updatedAt),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.document});

  final DocumentEntity document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final file = ref.watch(fileStorageProvider).file(document.filePath);
    return switch (document.fileType) {
      // The key forces a fresh viewer when the file behind the row changes.
      DocumentFileType.pdf => PdfViewer.file(
        file.path,
        key: ValueKey('${document.filePath}:${document.updatedAt}'),
      ),
      DocumentFileType.jpg || DocumentFileType.png => InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(
            file,
            errorBuilder: (_, _, _) =>
                ErrorState(message: context.coreL10n.errorImageDecode),
          ),
        ),
      ),
      DocumentFileType.txt => FutureBuilder<String>(
        future: _readText(file),
        builder: (context, snapshot) => snapshot.hasData
            ? SingleChildScrollView(
                padding: AppSpacing.screen,
                child: SelectableText(snapshot.data!),
              )
            : snapshot.hasError
            ? ErrorState(message: context.coreL10n.errorStorageRead)
            : const LoadingState(),
      ),
      DocumentFileType.docx => EmptyState(
        icon: Icons.article_outlined,
        title: l10n.documentPreviewUnavailable,
      ),
    };
  }

  Future<String> _readText(File file) => file.readAsString();
}
