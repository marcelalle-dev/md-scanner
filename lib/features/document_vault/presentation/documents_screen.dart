import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/l10n/generated/app_localizations.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
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

/// Lets the user pick one supported file and adds it to the library.
Future<void> importDocument(BuildContext context, WidgetRef ref) async {
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
    final result = await repository.importExternalFile(path);
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

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _search.text.trim();
    final filtered = query.isNotEmpty || _favoritesOnly;
    final provider = documentListProvider(
      DocumentQuery(
        search: query.isEmpty ? null : query,
        favoritesOnly: _favoritesOnly,
        sort: _sort.sort,
      ),
    );
    final documents = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.documentsTitle),
        actions: [
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
          IconButton(
            tooltip: l10n.documentsTrash,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => context.push(AppRoutes.trash),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => importDocument(context, ref),
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
                if (items.isEmpty) {
                  return filtered
                      ? EmptyState(
                          icon: Icons.search_off,
                          title: l10n.documentsNoResult,
                        )
                      : EmptyState(
                          icon: Icons.folder_open,
                          title: l10n.documentsEmptyTitle,
                          message: l10n.documentsEmptyMessage,
                        );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(indent: 76),
                  itemBuilder: (context, index) => DocumentTile(
                    document: items[index],
                    onTap: () => context.push(
                      AppRoutes.documentDetails(items[index].id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
