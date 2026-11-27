import 'package:flutter/material.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/l10n/failure_messages.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';

extension FeedbackContext on BuildContext {
  CoreLocalizations get coreL10n => CoreLocalizations.of(this);

  /// Shows a transient message, replacing the one currently displayed.
  void showMessage(String message, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.maybeOf(this);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  /// Shows the localized message of [failure]. Cancellations stay silent.
  void showFailure(Failure failure) {
    if (failure is CancelledFailure) return;
    showMessage(failureMessage(this, failure));
  }
}

/// Converts an error caught by the UI (typically from an `AsyncValue`) into
/// a [Failure] so it can be displayed with `failureMessage`.
Failure failureOf(Object error) => switch (error) {
  final Failure failure => failure,
  _ => failureFromError(error),
};
