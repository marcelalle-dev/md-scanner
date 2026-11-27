import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:md_scanner/app/routes.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/progress.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/ai_assistant/domain/ai_assistant.dart';
import 'package:md_scanner/features/ai_assistant/l10n/generated/ai_localizations.dart';
import 'package:md_scanner/features/document_vault/presentation/document_actions.dart';
import 'package:md_scanner/features/ocr/domain/ocr_service.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';

/// Text already extracted from a document, or null when OCR was never run.
final _documentTextProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, documentId) async {
      final result = await ref.watch(ocrServiceProvider).savedText(documentId);
      return switch (result) {
        Success(:final value) => value,
        Err(:final failure) => throw FailureException(failure),
      };
    });

class AiAssistantScreen extends ConsumerWidget {
  const AiAssistantScreen({this.documentId, super.key});

  final String? documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AiLocalizations.of(context);
    final id = documentId;

    if (id == null) {
      final provider = documentListProvider(const DocumentQuery());
      return Scaffold(
        appBar: AppBar(title: Text(l10n.aiChooseDocument)),
        body: AsyncValueView<List<DocumentEntity>>(
          value: ref.watch(provider),
          onRetry: () => ref.invalidate(provider),
          data: (items) => items.isEmpty
              ? EmptyState(
                  icon: Icons.auto_awesome_outlined,
                  title: l10n.aiNoDocument,
                  message: l10n.aiNoDocumentHint,
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) => DocumentTile(
                    document: items[index],
                    onTap: () => context.push(
                      AppRoutes.withDocument(
                        AppRoutes.aiAssistant,
                        items[index].id,
                      ),
                    ),
                  ),
                ),
        ),
      );
    }

    final text = ref.watch(_documentTextProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTitle)),
      body: AsyncValueView<String?>(
        value: text,
        onRetry: () => ref.invalidate(_documentTextProvider(id)),
        data: (value) => value == null || value.trim().isEmpty
            ? EmptyState(
                icon: Icons.text_snippet_outlined,
                title: l10n.aiNeedsText,
                action: FilledButton(
                  onPressed: () async {
                    await context.push(
                      AppRoutes.withDocument(AppRoutes.ocr, id),
                    );
                    ref.invalidate(_documentTextProvider(id));
                  },
                  child: Text(l10n.aiRunOcr),
                ),
              )
            : _AssistantBody(text: value),
      ),
    );
  }
}

class _AssistantBody extends ConsumerStatefulWidget {
  const _AssistantBody({required this.text});

  final String text;

  @override
  ConsumerState<_AssistantBody> createState() => _AssistantBodyState();
}

class _AssistantBodyState extends ConsumerState<_AssistantBody> {
  AiAnswer? _answer;

  static const Map<String, String> _targetLanguages = {
    'fr': 'Français',
    'en': 'English',
    'es': 'Español',
    'de': 'Deutsch',
  };

  Future<bool> _ensureConsent(AiAssistantService service) async {
    if (await service.hasConsent) return true;
    if (!mounted) return false;
    final l10n = AiLocalizations.of(context);
    final accepted = await showConfirmDialog(
      context,
      title: l10n.aiConsentTitle,
      message: l10n.aiConsentMessage,
      confirmLabel: l10n.aiConsentAccept,
    );
    if (accepted) await service.recordConsent();
    return accepted;
  }

  Future<void> _run(AiTask task) async {
    final l10n = AiLocalizations.of(context);
    final service = ref.read(aiAssistantServiceProvider);
    final language = Localizations.localeOf(context).languageCode;

    String? question;
    String? target;
    if (task == AiTask.qa) {
      question = await showTextInputDialog(
        context,
        title: l10n.aiQuestion,
        validator: (value) => value.isEmpty ? l10n.aiQuestionRequired : null,
      );
      if (question == null) return;
    }
    if (task == AiTask.translate) {
      if (!mounted) return;
      target = await showActionSheet<String>(
        context,
        title: l10n.aiTargetLanguage,
        actions: [
          for (final entry in _targetLanguages.entries)
            SheetAction(
              value: entry.key,
              label: entry.value,
              icon: Icons.translate,
            ),
        ],
      );
      if (target == null) return;
    }
    if (!await _ensureConsent(service) || !mounted) return;

    final result = await runWithProgress(
      context,
      message: l10n.aiRunning,
      task: (_) => service.run(
        task: task,
        documentText: widget.text,
        outputLanguage: language == 'fr' ? 'fr' : 'en',
        question: question,
        targetLanguage: target,
      ),
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() => _answer = value);
      case Err(:final failure):
        failure is ValidationFailure && failure.code == 'document_too_long'
            ? context.showMessage(l10n.aiTooLong)
            : context.showFailure(failure);
    }
  }

  String _taskLabel(AiLocalizations l10n, AiTask task) => switch (task) {
    AiTask.summary => l10n.aiTaskSummary,
    AiTask.sectionSummary => l10n.aiTaskSections,
    AiTask.qa => l10n.aiTaskQa,
    AiTask.extract => l10n.aiTaskExtract,
    AiTask.translate => l10n.aiTaskTranslate,
    AiTask.flashcards => l10n.aiTaskFlashcards,
    AiTask.adminAnalysis => l10n.aiTaskAdmin,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AiLocalizations.of(context);
    final theme = Theme.of(context);
    final service = ref.watch(aiAssistantServiceProvider);
    final premium = ref.watch(
      hasPremiumFeatureProvider(PremiumFeature.aiAssistant),
    );
    final findings = LocalExtractor.extract(widget.text);
    final answer = _answer;

    return ListView(
      padding: AppSpacing.screen,
      children: [
        SectionHeader(title: l10n.aiLocalTitle),
        Text(l10n.aiLocalHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        if (findings.isEmpty)
          Text(l10n.aiLocalNone)
        else ...[
          if (findings.dates.isNotEmpty)
            _Chips(title: l10n.aiLocalDates, values: findings.dates),
          if (findings.amounts.isNotEmpty)
            _Chips(title: l10n.aiLocalAmounts, values: findings.amounts),
        ],
        SectionHeader(title: l10n.aiCloudTitle),
        if (!service.isConfigured)
          InfoBanner(message: l10n.aiNotConfigured)
        else if (!premium)
          InfoBanner(
            message: l10n.aiPremiumOnly,
            action: TextButton(
              onPressed: () => context.push(AppRoutes.premium),
              child: Text(context.coreL10n.actionUnlockPremium),
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final task in AiTask.values)
                ActionChip(
                  label: Text(_taskLabel(l10n, task)),
                  onPressed: () => _run(task),
                ),
            ],
          ),
        if (answer != null) ...[
          SectionHeader(
            title: l10n.aiResult,
            trailing: IconButton(
              tooltip: context.coreL10n.actionCopy,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: answer.text));
                if (context.mounted) {
                  context.showMessage(context.coreL10n.copiedToClipboard);
                }
              },
            ),
          ),
          SelectableText(answer.text),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.aiDisclaimer, style: theme.textTheme.bodySmall),
          if (answer.remainingToday != null)
            Text(
              l10n.aiQuota(answer.remainingToday!),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [for (final value in values) Chip(label: Text(value))],
        ),
      ],
    ),
  );
}
