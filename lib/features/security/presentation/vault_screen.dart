import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/security/pin_service.dart';
import 'package:md_scanner/core/security/vault_lock.dart';
import 'package:md_scanner/core/security/vault_service.dart';
import 'package:md_scanner/core/services/platform_bridge.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/dialogs.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/progress.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/document_vault/presentation/document_actions.dart';
import 'package:md_scanner/features/security/l10n/generated/security_localizations.dart';
import 'package:md_scanner/features/security/presentation/app_lock_gate.dart';
import 'package:md_scanner/shared/models/document_entity.dart';
import 'package:md_scanner/shared/providers/document_providers.dart';
import 'package:pdfrx/pdfrx.dart';

const DocumentQuery _vaultQuery = DocumentQuery(inVault: true);

enum _VaultMenu { biometrics, lockApp, removePin }

enum _DocumentAction { open, remove }

/// The encrypted vault: PIN creation, lock screen, then the protected
/// documents. The window is protected against screenshots while it is shown,
/// and the vault locks as soon as the app goes to the background.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with WidgetsBindingObserver {
  late final VaultLockController _lock = ref.read(vaultLockProvider.notifier);
  late final PlatformBridge _bridge = ref.read(platformBridgeProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridge.setSecureWindow(secure: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bridge.setSecureWindow(secure: false);
    _lock.lock();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _lock.lock();
  }

  Future<void> _removePin(int vaultCount) async {
    final l10n = SecurityLocalizations.of(context);
    if (vaultCount > 0) {
      context.showMessage(l10n.vaultRemovePinBlocked);
      return;
    }
    final pin = await showTextInputDialog(
      context,
      title: l10n.vaultRemovePinConfirm,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 8,
    );
    if (pin == null || !mounted) return;
    final result = await _lock.removePin(pin);
    if (!mounted) return;
    final failure = result.failureOrNull;
    failure == null
        ? context.showMessage(l10n.vaultPinRemoved)
        : context.showFailure(failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = SecurityLocalizations.of(context);
    final lock = ref.watch(vaultLockProvider);
    final state = lock.value;
    final vaultCount = ref
        .watch(documentListProvider(_vaultQuery))
        .value
        ?.length;
    final lockWholeApp = ref.watch(appLockSettingProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vaultTitle),
        actions: state == null || !state.unlocked
            ? null
            : [
                IconButton(
                  tooltip: l10n.vaultLockNow,
                  icon: const Icon(Icons.lock_outline),
                  onPressed: _lock.lock,
                ),
                PopupMenuButton<_VaultMenu>(
                  tooltip: context.coreL10n.actionMore,
                  onSelected: (choice) async {
                    switch (choice) {
                      case _VaultMenu.biometrics:
                        if (!state.biometricAvailable) {
                          context.showMessage(l10n.vaultBiometricUnavailable);
                        } else {
                          await _lock.setBiometricEnabled(
                            enabled: !state.biometricEnabled,
                          );
                        }
                      case _VaultMenu.lockApp:
                        await ref
                            .read(appLockSettingProvider.notifier)
                            .set(enabled: !lockWholeApp);
                      case _VaultMenu.removePin:
                        await _removePin(vaultCount ?? 1);
                    }
                  },
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: _VaultMenu.biometrics,
                      checked: state.canUseBiometrics,
                      child: Text(l10n.vaultBiometricSetting),
                    ),
                    CheckedPopupMenuItem(
                      value: _VaultMenu.lockApp,
                      checked: lockWholeApp,
                      child: Text(l10n.appLockSetting),
                    ),
                    PopupMenuItem(
                      value: _VaultMenu.removePin,
                      child: Text(l10n.vaultRemovePin),
                    ),
                  ],
                ),
              ],
      ),
      floatingActionButton: state != null && state.unlocked
          ? FloatingActionButton.extended(
              onPressed: () => _addDocument(context, ref),
              icon: const Icon(Icons.enhanced_encryption_outlined),
              label: Text(l10n.vaultAdd),
            )
          : null,
      body: AsyncValueView<VaultLockState>(
        value: lock,
        onRetry: () => ref.invalidate(vaultLockProvider),
        data: (value) => !value.hasPin
            ? const _PinSetup()
            : !value.unlocked
            ? _LockedView(state: value)
            : const _VaultContent(),
      ),
    );
  }
}

Future<void> _addDocument(BuildContext context, WidgetRef ref) async {
  final l10n = SecurityLocalizations.of(context);
  final document = await showModalBottomSheet<DocumentEntity>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LibraryPicker(title: l10n.vaultChoose),
  );
  if (document == null || !context.mounted) return;
  final result = await runWithProgress(
    context,
    message: l10n.vaultEncrypting,
    task: (progress) => ref
        .read(vaultServiceProvider)
        .moveToVault(document, onProgress: progress.report),
  );
  if (!context.mounted) return;
  switch (result) {
    case Success():
      context.showMessage(l10n.vaultAdded);
    case Err(:final failure):
      context.showFailure(failure);
  }
}

class _LibraryPicker extends ConsumerWidget {
  const _LibraryPicker({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = SecurityLocalizations.of(context);
    final documents = ref.watch(documentListProvider(const DocumentQuery()));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SectionHeader(title: title),
            ),
            Expanded(
              child: AsyncValueView<List<DocumentEntity>>(
                value: documents,
                data: (items) => items.isEmpty
                    ? EmptyState(
                        icon: Icons.folder_open,
                        title: l10n.vaultNothingToAdd,
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) => DocumentTile(
                          document: items[index],
                          onTap: () => Navigator.of(context).pop(items[index]),
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

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    this.errorText,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final VoidCallback? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(8),
    ],
    onSubmitted: (_) => onSubmitted?.call(),
    decoration: InputDecoration(
      labelText: label,
      errorText: errorText,
      errorMaxLines: 3,
      prefixIcon: const Icon(Icons.pin_outlined),
    ),
  );
}

class _PinSetup extends ConsumerStatefulWidget {
  const _PinSetup();

  @override
  ConsumerState<_PinSetup> createState() => _PinSetupState();
}

class _PinSetupState extends ConsumerState<_PinSetup> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = SecurityLocalizations.of(context);
    if (!PinService.isValidFormat(_pin.text)) {
      setState(() => _error = l10n.vaultPinInvalid);
      return;
    }
    if (_pin.text != _confirmation.text) {
      setState(() => _error = l10n.vaultPinMismatch);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final result = await ref
        .read(vaultLockProvider.notifier)
        .createPin(_pin.text);
    if (!mounted) return;
    setState(() => _busy = false);
    final failure = result.failureOrNull;
    if (failure != null) context.showFailure(failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = SecurityLocalizations.of(context);
    return ListView(
      padding: AppSpacing.screen,
      children: [
        Text(
          l10n.vaultSetupTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        InfoBanner(
          message: l10n.vaultSetupMessage,
          tone: InfoBannerTone.warning,
        ),
        const SizedBox(height: AppSpacing.lg),
        _PinField(controller: _pin, label: l10n.vaultPin, autofocus: true),
        const SizedBox(height: AppSpacing.sm),
        _PinField(
          controller: _confirmation,
          label: l10n.vaultPinConfirm,
          errorText: _error,
          onSubmitted: _create,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(l10n.vaultCreate),
        ),
      ],
    );
  }
}

class _LockedView extends ConsumerStatefulWidget {
  const _LockedView({required this.state});

  final VaultLockState state;

  @override
  ConsumerState<_LockedView> createState() => _LockedViewState();
}

class _LockedViewState extends ConsumerState<_LockedView> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Result<void>> Function() unlock) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await unlock();
    if (!mounted) return;
    setState(() => _busy = false);
    _pin.clear();
    final failure = result.failureOrNull;
    if (failure != null) context.showFailure(failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = SecurityLocalizations.of(context);
    final controller = ref.read(vaultLockProvider.notifier);
    return ListView(
      padding: AppSpacing.screen,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Icon(
          Icons.lock_outline,
          size: 56,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.vaultLockedTitle,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        _PinField(
          controller: _pin,
          label: l10n.vaultPin,
          autofocus: true,
          onSubmitted: () => _run(() => controller.unlockWithPin(_pin.text)),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() => controller.unlockWithPin(_pin.text)),
          child: Text(l10n.vaultUnlock),
        ),
        if (widget.state.canUseBiometrics) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => controller.unlockWithBiometrics(
                      l10n.vaultBiometricReason,
                    ),
                  ),
            icon: const Icon(Icons.fingerprint),
            label: Text(l10n.vaultUseBiometrics),
          ),
        ],
      ],
    );
  }
}

class _VaultContent extends ConsumerWidget {
  const _VaultContent();

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    DocumentEntity document,
  ) async {
    final l10n = SecurityLocalizations.of(context);
    final previewable =
        document.fileType.isImage || document.fileType == DocumentFileType.pdf;
    if (!previewable) {
      context.showMessage(l10n.vaultPreviewUnavailable);
      return;
    }
    final result = await runWithProgress(
      context,
      message: l10n.vaultDecrypting,
      task: (_) => ref.read(vaultServiceProvider).openDecrypted(document),
    );
    if (!context.mounted) return;
    switch (result) {
      case Success(:final value):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(document.name)),
              body: document.fileType == DocumentFileType.pdf
                  ? PdfViewer.file(value)
                  : InteractiveViewer(
                      maxScale: 6,
                      child: Center(child: Image.file(File(value))),
                    ),
            ),
          ),
        );
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    DocumentEntity document,
  ) async {
    final l10n = SecurityLocalizations.of(context);
    final result = await runWithProgress(
      context,
      message: l10n.vaultDecrypting,
      task: (progress) => ref
          .read(vaultServiceProvider)
          .removeFromVault(document, onProgress: progress.report),
    );
    if (!context.mounted) return;
    switch (result) {
      case Success():
        context.showMessage(l10n.vaultRemoved);
      case Err(:final failure):
        context.showFailure(failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = SecurityLocalizations.of(context);
    final provider = documentListProvider(_vaultQuery);
    return AsyncValueView<List<DocumentEntity>>(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      data: (items) => items.isEmpty
          ? EmptyState(
              icon: Icons.shield_outlined,
              title: l10n.vaultEmpty,
              message: l10n.vaultEmptyHint,
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(indent: 76),
              itemBuilder: (context, index) {
                final document = items[index];
                return DocumentTile(
                  document: document,
                  onTap: () => _open(context, ref, document),
                  trailing: PopupMenuButton<_DocumentAction>(
                    tooltip: context.coreL10n.actionMore,
                    onSelected: (action) => switch (action) {
                      _DocumentAction.open => _open(context, ref, document),
                      _DocumentAction.remove => _remove(context, ref, document),
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _DocumentAction.open,
                        child: Text(l10n.vaultOpen),
                      ),
                      PopupMenuItem(
                        value: _DocumentAction.remove,
                        child: Text(l10n.vaultRemove),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
