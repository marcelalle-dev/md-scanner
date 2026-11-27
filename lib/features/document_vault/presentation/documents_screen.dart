import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/ads/presentation/ad_banner_slot.dart';
import 'package:md_scanner/features/document_vault/presentation/document_actions.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';

enum _SortOption {
  newest(DocumentSort(DocumentSortField.date)),
  oldest(DocumentSort(DocumentSortField.date, ascending: true)),
  name(DocumentSort(DocumentSortField.name, ascending: true)),
  size(DocumentSort(DocumentSortField.size));

  const _SortOption(this.sort);

  final DocumentSort sort;
}

enum _FolderAction { rename, delete }

/// Lets the user pick supported files and adds them to the library,
/// optionally straight into [folderId].
Future<void> importDocument(
  BuildContext context,
  WidgetRef ref, {
  String? folderId,
}) async {
  final l10n = AppLocalizations.of(context);
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'txt', 'docx'],
  );
  if (!context.mounted) return;
  final repository = ref.read(documentRepositoryProvider);
  var imported = 0;
  for (final file in picked) {
    final path = file.path;
    if (path == null) continue;
    final result = await repository.importExternalFile(
      path,
      folderId: folderId,
    );
    if (!context.mounted) return;
    switch (result) {
      case Success():
        imported++;
      case Err(:final failure):
        context.showFailure(failure);
    }
  }
  if (imported > 0 && context.mounted) {
    context.showMessage(l10n.documentsImported);
  }
}

final _folderProvider = FutureProvider.autoDispose
    .family<FolderEntity?, String>((ref, id) async {
      final result = await ref.watch(documentRepositoryProvider).getFolder(id);
      return result.valueOrNull;
    });

/// The library. Without a search it shows the folders and documents of the
/// current folder; a search or the favorites filter spans every folder.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({this.folderId, super.key});

  /// Null for the root of the library.
  final String? folderId;

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final TextEditingController _search = TextEditingController();
  _SortOption _sort = _SortOption.newest;
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _sortLabel(AppLocalizations l10n, _SortOption option) =>
      switch (option) {
        _SortOption.newest => l10n.sortNewest,
        _SortOption.oldest => l10n.sortOldest,
        _SortOption.name => l10n.sortName,
        _SortOption.size => l10n.sortSize,
      };

  void _report(Result<Object?> result) {
    final failure = result.failureOrNull;
    if (failure != null && mounted) context.showFailure(failure);
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    final name = await showTextInputDialog(
      context,
      title: l10n.folderNew,
      label: l10n.folderName,
      maxLength: 60,
      validator: (value) => value.isEmpty ? l10n.documentNameEmpty : null,
    );
    if (name == null) return;
    _report(
      await ref
          .read(documentRepositoryProvider)
          .createFolder(name, parentId: widget.folderId),
    );
  }

  Future<void> _renameFolder(FolderEntity folder) async {
    final l10n = AppLocalizations.of(context);
    final name = await showTextInputDialog(
      context,
      title: l10n.documentRename,
      initialValue: folder.name,
      maxLength: 60,
      validator: (value) => value.isEmpty ? l10n.documentNameEmpty : null,
    );
    if (name == null || name == folder.name) return;
    _report(
      await ref.read(documentRepositoryProvider).renameFolder(folder.id, name),
    );
  }

  Future<void> _deleteFolder(FolderEntity folder) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.folderDeleteConfirm(folder.name),
      message: l10n.folderDeleteMessage,
      confirmLabel: context.coreL10n.actionDelete,
      destructive: true,
    );
    if (!confirmed) return;
    _report(await ref.read(documentRepositoryProvider).deleteFolder(folder.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final folderId = widget.folderId;
    final query = _search.text.trim();
    final filtered = query.isNotEmpty || _favoritesOnly;
    final provider = documentListProvider(
      DocumentQuery(
        search: query.isEmpty ? null : query,
        favoritesOnly: _favoritesOnly,
        sort: _sort.sort,
        restrictToFolder: !filtered,
        folderId: filtered ? null : folderId,
      ),
    );
    final documents = ref.watch(provider);
    final folders = filtered
        ? const <FolderEntity>[]
        : ref.watch(folderListProvider(folderId)).value ?? const [];
    final current = folderId == null
        ? null
        : ref.watch(_folderProvider(folderId)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(current?.name ?? l10n.documentsTitle),
        actions: [
          IconButton(
            tooltip: l10n.folderNew,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _createFolder,
          ),
          PopupMenuButton<_SortOption>(
            tooltip: l10n.documentsSort,
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (option) => setState(() => _sort = option),
            itemBuilder: (context) => [
              for (final option in _SortOption.values)
                PopupMenuItem(
                  value: option,
                  child: Text(_sortLabel(l10n, option)),
                ),
            ],
          ),
          if (folderId == null)
            IconButton(
              tooltip: l10n.documentsTrash,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => context.push(AppRoutes.trash),
            ),
        ],
      ),
      bottomNavigationBar: folderId == null ? const AdBannerSlot() : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => importDocument(context, ref, folderId: folderId),
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(l10n.documentsImport),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.documentsSearch,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.coreL10n.actionClose,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: FilterChip(
                avatar: const Icon(Icons.star_outline, size: 18),
                label: Text(l10n.documentsFavoritesOnly),
                selected: _favoritesOnly,
                onSelected: (value) => setState(() => _favoritesOnly = value),
              ),
            ),
          ),
          Expanded(
            child: AsyncValueView<List<DocumentEntity>>(
              value: documents,
              onRetry: () => ref.invalidate(provider),
              data: (items) {
                if (items.isEmpty && folders.isEmpty) {
                  return filtered
                      ? EmptyState(
                          icon: Icons.search_off,
                          title: l10n.documentsNoResult,
                        )
                      : folderId != null
                      ? EmptyState(
                          icon: Icons.folder_open,
                          title: l10n.folderEmpty,
                        )
                      : EmptyState(
                          icon: Icons.folder_open,
                          title: l10n.documentsEmptyTitle,
                          message: l10n.documentsEmptyMessage,
                        );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: folders.length + items.length,
                  itemBuilder: (context, index) {
                    if (index < folders.length) {
                      final folder = folders[index];
                      return ListTile(
                        leading: const SizedBox(
                          width: 44,
                          child: Icon(Icons.folder_outlined, size: 32),
                        ),
                        title: Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${folder.documentCount} · ${l10n.documentsTitle}',
                        ),
                        onTap: () => context.push(AppRoutes.folder(folder.id)),
                        trailing: PopupMenuButton<_FolderAction>(
                          tooltip: context.coreL10n.actionMore,
                          onSelected: (action) => switch (action) {
                            _FolderAction.rename => _renameFolder(folder),
                            _FolderAction.delete => _deleteFolder(folder),
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _FolderAction.rename,
                              child: Text(l10n.documentRename),
                            ),
                            PopupMenuItem(
                              value: _FolderAction.delete,
                              child: Text(l10n.folderDelete),
                            ),
                          ],
                        ),
                      );
                    }
                    final document = items[index - folders.length];
                    return DocumentTile(
                      document: document,
                      onTap: () =>
                          context.push(AppRoutes.documentDetails(document.id)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
