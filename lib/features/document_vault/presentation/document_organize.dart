import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/file_storage.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';
import 'package:printing/printing.dart';

/// A folder with its full path ("Administratif / Impôts"), for pickers.
typedef FolderPath = ({String id, String path});

/// Every folder of the library, depth first, with readable paths.
Future<List<FolderPath>> listFolderPaths(DocumentRepository repository) async {
  final paths = <FolderPath>[];
  Future<void> visit(String? parentId, String prefix) async {
    final children =
        (await repository.folders(parentId: parentId)).valueOrNull ?? const [];
    for (final folder in children) {
      final path = prefix.isEmpty ? folder.name : '$prefix / ${folder.name}';
      paths.add((id: folder.id, path: path));
      await visit(folder.id, path);
    }
  }

  await visit(null, '');
  return paths;
}

/// Parses "factures, 2026 ,, Impôts" into distinct, trimmed tag names.
List<String> parseTagInput(String input) {
  final seen = <String>{};
  return [
    for (final part in input.split(','))
      if (part.trim().isNotEmpty && seen.add(part.trim().toLowerCase()))
        part.trim(),
  ];
}

/// Asks for a destination folder and moves the document there.
Future<void> moveDocument(
  BuildContext context,
  WidgetRef ref,
  DocumentEntity document,
) async {
  final l10n = AppLocalizations.of(context);
  final repository = ref.read(documentRepositoryProvider);
  final folders = await listFolderPaths(repository);
  if (!context.mounted) return;
  // An empty string stands for the root, so that "cancel" stays null.
  final target = await showActionSheet<String>(
    context,
    title: l10n.documentMove,
    actions: [
      SheetAction(
        value: '',
        label: l10n.folderRoot,
        icon: Icons.home_outlined,
        enabled: document.folderId != null,
      ),
      for (final folder in folders)
        SheetAction(
          value: folder.id,
          label: folder.path,
          icon: Icons.folder_outlined,
          enabled: folder.id != document.folderId,
        ),
    ],
  );
  if (target == null || !context.mounted) return;
  final result = await repository.moveToFolder([
    document.id,
  ], target.isEmpty ? null : target);
  if (!context.mounted) return;
  switch (result) {
    case Success():
      context.showMessage(l10n.documentMoved);
    case Err(:final failure):
      context.showFailure(failure);
  }
}

/// Edits the tags of a document as a comma-separated list.
Future<void> editDocumentTags(
  BuildContext context,
  WidgetRef ref,
  DocumentEntity document,
) async {
  final l10n = AppLocalizations.of(context);
  final repository = ref.read(documentRepositoryProvider);
  final current =
      (await repository.tagsOf(document.id)).valueOrNull ?? const [];
  if (!context.mounted) return;
  final input = await showTextInputDialog(
    context,
    title: l10n.tagsLabel,
    hint: l10n.tagsHint,
    initialValue: current.map((tag) => tag.name).join(', '),
    maxLength: 200,
  );
  if (input == null || !context.mounted) return;
  final result = await repository.setTags(document.id, parseTagInput(input));
  if (context.mounted && result.failureOrNull != null) {
    context.showFailure(result.failureOrNull!);
  }
}

/// Sends a PDF document to the system print dialog.
Future<void> printDocument(
  BuildContext context,
  WidgetRef ref,
  DocumentEntity document,
) async {
  final l10n = AppLocalizations.of(context);
  final file = ref.read(fileStorageProvider).file(document.filePath);
  final result = await guard(
    () => Printing.layoutPdf(
      name: document.name,
      onLayout: (_) => file.readAsBytes(),
    ),
  );
  if (context.mounted && result.isFailure) {
    context.showMessage(l10n.printFailed);
  }
}
