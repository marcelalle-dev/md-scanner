import 'package:flutter/material.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';

/// Asks the user to confirm an action. Returns `true` only on confirmation.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l10n = CoreLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel ?? l10n.actionCancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel ?? l10n.actionConfirm),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final l10n = CoreLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionOk),
        ),
      ],
    ),
  );
}

/// Asks for a single line of text (rename, new folder, password…).
///
/// [validator] returns a localized error message, or null when valid.
/// Returns the trimmed text, or null if the user cancelled.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String? label,
  String? hint,
  String? confirmLabel,
  bool obscureText = false,
  int? maxLength,
  TextInputType? keyboardType,
  String? Function(String value)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      hint: hint,
      confirmLabel: confirmLabel,
      obscureText: obscureText,
      maxLength: maxLength,
      keyboardType: keyboardType,
      validator: validator,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    this.initialValue,
    this.label,
    this.hint,
    this.confirmLabel,
    this.obscureText = false,
    this.maxLength,
    this.keyboardType,
    this.validator,
  });

  final String title;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? confirmLabel;
  final bool obscureText;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? Function(String value)? validator;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;
  String? _error;
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = widget.obscureText
        ? _controller.text
        : _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscured,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
          errorMaxLines: 3,
          suffixIcon: widget.obscureText
              ? IconButton(
                  tooltip: _obscured
                      ? l10n.actionShowPassword
                      : l10n.actionHidePassword,
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel ?? l10n.actionOk),
        ),
      ],
    );
  }
}

/// One entry of [showActionSheet].
class SheetAction<T> {
  const SheetAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.enabled = true,
    this.subtitle,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
  final bool enabled;
  final String? subtitle;
}

/// Bottom sheet listing contextual actions. Returns the chosen value.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required List<SheetAction<T>> actions,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (final action in actions)
                ListTile(
                  enabled: action.enabled,
                  leading: Icon(
                    action.icon,
                    color: action.destructive ? theme.colorScheme.error : null,
                  ),
                  title: Text(
                    action.label,
                    style: action.destructive
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                  subtitle: action.subtitle == null
                      ? null
                      : Text(action.subtitle!),
                  onTap: () => Navigator.of(context).pop(action.value),
                ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      );
    },
  );
}
