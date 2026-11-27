import 'package:flutter/material.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';

/// Handle given to a long-running task so it can report progress and
/// observe cancellation.
class ProgressController {
  /// Fraction in `[0, 1]`, or null while the amount of work is unknown.
  final ValueNotifier<double?> fraction = ValueNotifier<double?>(null);

  /// Optional detail shown under the main message ("Page 3 / 20").
  final ValueNotifier<String?> detail = ValueNotifier<String?>(null);

  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void report(double? value, {String? detail}) {
    fraction.value = value?.clamp(0.0, 1.0).toDouble();
    if (detail != null) this.detail.value = detail;
  }

  void cancel() => _cancelled = true;

  /// Call between two units of work: aborts the task with a
  /// [CancelledFailure] once the user pressed "Cancel".
  void throwIfCancelled() {
    if (_cancelled) throw const FailureException(CancelledFailure());
  }

  void dispose() {
    fraction.dispose();
    detail.dispose();
  }
}

/// Runs [task] behind a modal progress dialog.
///
/// The dialog blocks interaction, which also prevents the action from being
/// triggered twice. With [cancellable], a button lets the user request
/// cancellation; the task must poll [ProgressController.throwIfCancelled].
Future<Result<T>> runWithProgress<T>(
  BuildContext context, {
  required String message,
  required Future<Result<T>> Function(ProgressController progress) task,
  bool cancellable = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final controller = ProgressController();
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ProgressDialog(
      message: message,
      controller: controller,
      cancellable: cancellable,
    ),
  );
  // The dialog stays open until the task settles; its future is not awaited.
  // ignore: unawaited_futures
  navigator.push(route);
  try {
    return await guard(() async {
      final result = await task(controller);
      return switch (result) {
        Success<T>(:final value) => value,
        Err<T>(:final failure) => throw FailureException(failure),
      };
    });
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    controller.dispose();
  }
}

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({
    required this.message,
    required this.controller,
    required this.cancellable,
  });

  final String message;
  final ProgressController controller;
  final bool cancellable;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  bool _cancelRequested = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = CoreLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            ValueListenableBuilder<double?>(
              valueListenable: widget.controller.fraction,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(value: value, minHeight: 6),
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: widget.controller.detail,
              builder: (context, value, _) => value == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(value, style: theme.textTheme.bodySmall),
                    ),
            ),
          ],
        ),
        actions: widget.cancellable
            ? [
                TextButton(
                  onPressed: _cancelRequested
                      ? null
                      : () {
                          widget.controller.cancel();
                          setState(() => _cancelRequested = true);
                        },
                  child: Text(l10n.actionCancel),
                ),
              ]
            : null,
      ),
    );
  }
}
