import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

/// Shares a document through the system sheet.
///
/// Files are stored under UUID names, so a copy carrying the name chosen by
/// the user is placed in the `exports` area (purged automatically) first.
Future<void> shareDocument(
  BuildContext context,
  WidgetRef ref,
  DocumentEntity document,
) async {
  final storage = ref.read(fileStorageProvider);
  final result = await guard(() async {
    final folder = Directory(
      p.join(storage.directoryOf(StorageArea.exports).path, const Uuid().v4()),
    );
    await folder.create(recursive: true);
    final target = p.join(
      folder.path,
      '${sanitizeFileName(document.name)}.${document.fileType.extension}',
    );
    await storage.file(document.filePath).copy(target);
    return target;
  });
  if (!context.mounted) return;
  switch (result) {
    case Success(:final value):
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(value, mimeType: document.fileType.mimeType)],
          subject: document.name,
        ),
      );
    case Err(:final failure):
      context.showFailure(failure);
  }
}

Future<void> renameDocument(
  BuildContext context,
  WidgetRef ref,
  DocumentEntity document,
) async {
  final l10n = AppLocalizations.of(context);
  final name = await showTextInputDialog(
    context,
    title: l10n.documentRename,
    initialValue: document.name,
    maxLength: 80,
    validator: (value) => value.isEmpty ? l10n.documentNameEmpty : null,
  );
  if (name == null || name == document.name || !context.mounted) return;
  final result = await ref
      .read(documentRepositoryProvider)
      .rename(document.id, name);
  if (context.mounted && result.failureOrNull != null) {
    context.showFailure(result.failureOrNull!);
  }
}

Future<void> toggleFavorite(
  BuildContext context,
  WidgetRef ref,
  DocumentEntity document,
) async {
  final result = await ref
      .read(documentRepositoryProvider)
      .setFavorite(document.id, favorite: !document.isFavorite);
  if (context.mounted && result.failureOrNull != null) {
    context.showFailure(result.failureOrNull!);
  }
}

/// Moves the document to the trash. Returns true when it was moved.
Future<bool> trashDocument(
  BuildContext context,
  WidgetRef ref,
  DocumentEntity document,
) async {
  final l10n = AppLocalizations.of(context);
  final result = await ref.read(documentRepositoryProvider).moveToTrash([
    document.id,
  ]);
  if (!context.mounted) return result.isSuccess;
  switch (result) {
    case Success():
      context.showMessage(l10n.documentMovedToTrash);
      return true;
    case Err(:final failure):
      context.showFailure(failure);
      return false;
  }
}

IconData documentIcon(DocumentFileType type) => switch (type) {
  DocumentFileType.pdf => Icons.picture_as_pdf_outlined,
  DocumentFileType.jpg || DocumentFileType.png => Icons.image_outlined,
  DocumentFileType.txt => Icons.notes_outlined,
  DocumentFileType.docx => Icons.article_outlined,
};

/// List row for a document: thumbnail, name, type, size and date.
class DocumentTile extends ConsumerWidget {
  const DocumentTile({
    required this.document,
    this.onTap,
    this.trailing,
    super.key,
  });

  final DocumentEntity document;

  /// Null makes the row non-interactive (trash list).
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = context.coreL10n;
    final theme = Theme.of(context);
    final storage = ref.watch(fileStorageProvider);
    final thumbnail = document.thumbnailPath;
    final details = [
      document.fileType.extension.toUpperCase(),
      formatFileSize(core, document.fileSize),
      if (document.pageCount != null && document.pageCount! > 1)
        core.pageCount(document.pageCount!),
      formatDate(core.localeName, document.updatedAt),
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 56,
          child: thumbnail == null
              ? ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(documentIcon(document.fileType)),
                )
              : Image.file(
                  storage.file(thumbnail),
                  fit: BoxFit.cover,
                  cacheWidth: 132,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(documentIcon(document.fileType)),
                  ),
                ),
        ),
      ),
      title: Text(document.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ??
          (document.isFavorite
              ? Icon(Icons.star, color: theme.colorScheme.secondary, size: 20)
              : null),
    );
  }
}
