import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/pdf_tools/domain/pdf_models.dart';
import 'package:pdf_cos/pdf_cos.dart'
    show
        CosParseException,
        CosPasswordException,
        UnsupportedEncryptionException,
        UnsupportedFilterException;
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfium;

/// Runs [task] on [argument] in a short-lived isolate.
///
/// Declared at top level on purpose: the closure sent to the isolate then
/// captures [task] and [argument] only, never an engine instance.
Future<R> runInIsolate<A, R>(R Function(A argument) task, A argument) =>
    Isolate.run(() => task(argument));

/// Like [runInIsolate], but the isolate is killed as soon as [isCancelled]
/// returns true; the call then fails with `CancelledFailure`. The caller
/// removes whatever the task had started to write.
Future<R> runCancellable<A, R>(
  R Function(A argument) task,
  A argument,
  PdfCancellationCheck? isCancelled,
) async {
  if (isCancelled == null) return runInIsolate(task, argument);
  throwIfCancelled(isCancelled);
  final port = ReceivePort();
  final isolate = await Isolate.spawn<_IsolateJob<dynamic, dynamic>>(
    _runJob,
    _IsolateJob<A, R>(task, argument, port.sendPort),
    onExit: port.sendPort,
  );
  final watcher = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (isCancelled()) isolate.kill(priority: Isolate.immediate);
  });
  try {
    final Object? message = await port.first;
    if (message is _IsolateJobDone) return message.value as R;
    // The isolate ended without a result: killed above, or it crashed.
    throwIfCancelled(isCancelled);
    throw FailureException(
      PdfFailure(
        PdfFailureKind.operationFailed,
        debugMessage: message is String ? message : 'isolate_exit',
      ),
    );
  } finally {
    watcher.cancel();
  }
}

class _IsolateJob<A, R> {
  const _IsolateJob(this.task, this.argument, this.reply);

  final R Function(A argument) task;
  final A argument;
  final SendPort reply;

  void run() {
    final Object? message;
    try {
      message = _IsolateJobDone(task(argument));
    } catch (error) {
      Isolate.exit(reply, error.runtimeType.toString());
    }
    Isolate.exit(reply, message);
  }
}

class _IsolateJobDone {
  const _IsolateJobDone(this.value);

  final Object? value;
}

void _runJob(_IsolateJob<dynamic, dynamic> job) => job.run();

/// Aborts the current operation when the caller asked for it.
void throwIfCancelled(PdfCancellationCheck? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const FailureException(CancelledFailure());
  }
}

/// Where an output is written before being renamed to its final path.
String partialPathOf(String outputPath) => '$outputPath.part';

/// Deletes [path] if it exists; a file that cannot be removed is left to the
/// periodic purge of the temporary area.
Future<void> deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Nothing more can be done here.
  }
}

/// Promotes a finished partial file to [outputPath], replacing any previous
/// file, and returns its size.
Future<int> commitPartial(String outputPath) async {
  final target = File(outputPath);
  if (await target.exists()) await target.delete();
  final committed = await File(partialPathOf(outputPath)).rename(outputPath);
  return committed.length();
}

/// Writes [bytes] to [outputPath] through a partial file, so readers never
/// see a half-written document.
Future<void> writeAtomically(String outputPath, List<int> bytes) async {
  final partial = File(partialPathOf(outputPath));
  try {
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(bytes, flush: true);
    await commitPartial(outputPath);
  } catch (_) {
    await deleteQuietly(partial.path);
    rethrow;
  }
}

/// Maps the exceptions of the PDF libraries to failures. Exception messages
/// may embed file names, so only types and numeric codes are kept.
Failure? mapPdfError(Object error, StackTrace stackTrace) => switch (error) {
  FailureException() || FileSystemException() => null,
  pdfium.PdfPasswordException() ||
  CosPasswordException() => const PdfFailure(PdfFailureKind.passwordRequired),
  pdfium.PdfException(:final errorCode) => PdfFailure(
    PdfFailureKind.operationFailed,
    debugMessage: 'pdfium(code=$errorCode)',
  ),
  CosParseException() => const PdfFailure(PdfFailureKind.corrupted),
  UnsupportedEncryptionException() ||
  UnsupportedFilterException() => const PdfFailure(PdfFailureKind.unsupported),
  _ => PdfFailure(
    PdfFailureKind.operationFailed,
    debugMessage: error.runtimeType.toString(),
  ),
};

/// [guard] with the PDF error mapping.
Future<Result<T>> guardPdf<T>(Future<T> Function() body) =>
    guard(body, onError: mapPdfError);

/// Unwraps a result inside a [guardPdf] body.
T valueOrThrow<T>(Result<T> result) => switch (result) {
  Success<T>(:final value) => value,
  Err<T>(:final failure) => throw FailureException(failure),
};
