import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/progress.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/ads/data/ads_service.dart';
import 'package:md_scanner/features/document_vault/presentation/document_actions.dart';
import 'package:md_scanner/features/ocr/domain/ocr_service.dart';
import 'package:md_scanner/features/ocr/domain/text_recognition.dart';
import 'package:md_scanner/features/ocr/l10n/generated/ocr_localizations.dart';
import 'package:md_scanner/features/premium/l10n/generated/premium_localizations.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';
import 'package:md_scanner/shared/repositories/document_repository.dart';

const DocumentQuery _ocrSources = DocumentQuery(
  types: {DocumentFileType.pdf, DocumentFileType.jpg, DocumentFileType.png},
);

/// Text recognition on a library document. Without [documentId] the screen
/// first lets the user choose a document or import an image.
class OcrScreen extends ConsumerWidget {
  const OcrScreen({this.documentId, super.key});

  final String? documentId;

  Future<void> _importImage(BuildContext context, WidgetRef ref) async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !context.mounted) return;
    final result = await ref
        .read(documentRepositoryProvider)
        .importExternalFile(image.path);
    if (!context.mounted) return;
    switch (result) {
      case Success(:final value):
        await context.push(AppRoutes.withDocument(AppRoutes.ocr, value.id));
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = OcrLocalizations.of(context);
    final id = documentId;
    if (id != null) {
      final document = ref.watch(documentByIdProvider(id));
      return Scaffold(
        appBar: AppBar(title: Text(l10n.ocrTitle)),
        body: AsyncValueView<DocumentEntity>(
          value: document,
          onRetry: () => ref.invalidate(documentByIdProvider(id)),
          data: (value) => _OcrEditor(document: value),
        ),
      );
    }

    final provider = documentListProvider(_ocrSources);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ocrChooseDocument)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _importImage(context, ref),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(l10n.ocrImportImage),
      ),
      body: AsyncValueView<List<DocumentEntity>>(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.text_snippet_outlined,
                title: l10n.ocrNoDocument,
                message: l10n.ocrNoDocumentHint,
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(indent: 76),
                itemBuilder: (context, index) => DocumentTile(
                  document: items[index],
                  onTap: () => context.push(
                    AppRoutes.withDocument(AppRoutes.ocr, items[index].id),
                  ),
                ),
              ),
      ),
    );
  }
}

class _OcrEditor extends ConsumerStatefulWidget {
  const _OcrEditor({required this.document});

  final DocumentEntity document;

  @override
  ConsumerState<_OcrEditor> createState() => _OcrEditorState();
}

class _OcrEditorState extends ConsumerState<_OcrEditor> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  bool _loaded = false;
  int _matchCursor = -1;

  OcrService get _service => ref.read(ocrServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _text.dispose();
    _search.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final saved = await _service.savedText(widget.document.id);
    if (!mounted) return;
    setState(() {
      _text.text = saved.valueOrNull ?? '';
      _loaded = true;
    });
  }

  Future<void> _recognize() async {
    final l10n = OcrLocalizations.of(context);
    String? password;
    while (true) {
      if (!mounted) return;
      final result = await runWithProgress(
        context,
        message: l10n.ocrRunning,
        task: (progress) => _service.recognize(
          widget.document,
          password: password,
          onProgress: (done, total) =>
              progress.report(done / total, detail: '$done / $total'),
        ),
      );
      if (!mounted) return;
      switch (result) {
        case Success(:final value):
          setState(() => _text.text = value);
          await _service.saveText(widget.document.id, value);
          return;
        case Err(:final failure):
          context.showFailure(failure);
          final needsPassword =
              failure is PdfFailure &&
              (failure.kind == PdfFailureKind.passwordRequired ||
                  failure.kind == PdfFailureKind.wrongPassword);
          if (!needsPassword) return;
          password = await showTextInputDialog(
            context,
            title: context.coreL10n.errorPdfPasswordRequired,
            obscureText: true,
          );
          if (password == null || !mounted) return;
      }
    }
  }

  Future<void> _save() async {
    final l10n = OcrLocalizations.of(context);
    final result = await _service.saveText(widget.document.id, _text.text);
    if (!mounted) return;
    final failure = result.failureOrNull;
    failure == null
        ? context.showMessage(l10n.ocrSaved)
        : context.showFailure(failure);
  }

  Future<void> _export({required bool docx}) async {
    final l10n = OcrLocalizations.of(context);
    // DOCX export is a Premium feature; TXT export is always free. A free
    // user may instead watch a rewarded ad to export this document once.
    if (docx &&
        !ref.read(hasPremiumFeatureProvider(PremiumFeature.docxExport))) {
      final premium = PremiumLocalizations.of(context);
      final choice = await showActionSheet<bool>(
        context,
        title: premium.rewardedMessage,
        actions: [
          SheetAction(
            value: true,
            label: premium.rewardedWatch,
            icon: Icons.smart_display_outlined,
          ),
          SheetAction(
            value: false,
            label: context.coreL10n.actionUnlockPremium,
            icon: Icons.workspace_premium_outlined,
          ),
        ],
      );
      if (choice == null || !mounted) return;
      if (!choice) {
        await context.push(AppRoutes.premium);
        return;
      }
      final earned = await ref.read(adsServiceProvider).showRewarded();
      if (!mounted) return;
      if (!earned) {
        context.showMessage(premium.rewardedUnavailable);
        return;
      }
    }
    final result = docx
        ? await _service.exportDocx(widget.document.name, _text.text)
        : await _service.exportTxt(widget.document.name, _text.text);
    if (!mounted) return;
    switch (result) {
      case Success():
        context.showMessage(l10n.ocrExported);
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  void _nextMatch(List<int> matches) {
    if (matches.isEmpty) return;
    _matchCursor = (_matchCursor + 1) % matches.length;
    final start = matches[_matchCursor];
    _textFocus.requestFocus();
    _text.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + _search.text.trim().length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = OcrLocalizations.of(context);
    final core = context.coreL10n;
    if (!_loaded) return const LoadingState();

    final hasText = _text.text.trim().isNotEmpty;
    if (!hasText) {
      return ListView(
        padding: AppSpacing.screen,
        children: [
          DocumentTile(document: widget.document),
          const SizedBox(height: AppSpacing.md),
          InfoBanner(message: l10n.ocrIntro),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _recognize,
            icon: const Icon(Icons.text_snippet_outlined),
            label: Text(l10n.ocrStart),
          ),
        ],
      );
    }

    final matches = TextSearch.findAll(_text.text, _search.text);
    return Column(
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
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() => _matchCursor = -1),
            onSubmitted: (_) => _nextMatch(matches),
            decoration: InputDecoration(
              hintText: l10n.ocrSearch,
              prefixIcon: const Icon(Icons.search),
              helperText: _search.text.trim().isEmpty
                  ? null
                  : l10n.ocrMatches(matches.length),
              suffixIcon: matches.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.ocrNextMatch,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => _nextMatch(matches),
                    ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _text,
              focusNode: _textFocus,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.ocrTextLabel,
                alignLabelWithHint: true,
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              spacing: AppSpacing.xs,
              children: [
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.ocrSave),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _text.text));
                    if (context.mounted) {
                      context.showMessage(core.copiedToClipboard);
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(core.actionCopy),
                ),
                OutlinedButton(
                  onPressed: () => _export(docx: false),
                  child: Text(l10n.ocrExportTxt),
                ),
                OutlinedButton.icon(
                  onPressed: () => _export(docx: true),
                  icon:
                      ref.watch(
                        hasPremiumFeatureProvider(PremiumFeature.docxExport),
                      )
                      ? const Icon(Icons.article_outlined)
                      : const PremiumBadge(compact: true),
                  label: Text(l10n.ocrExportDocx),
                ),
                TextButton.icon(
                  onPressed: _recognize,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.ocrRestart),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
