import 'package:equatable/equatable.dart';

/// Typed description of everything that can go wrong in the app.
///
/// Repositories and services never let raw exceptions cross a layer boundary:
/// they return a [Failure] wrapped in a `Result`. The presentation layer maps
/// a failure to a localized message with `failureMessage(context, failure)`.
///
/// [debugMessage] is for technical logs only. It must never contain document
/// content, OCR text, file names chosen by the user or any personal data.
sealed class Failure extends Equatable {
  const Failure({this.debugMessage});

  final String? debugMessage;

  @override
  List<Object?> get props => [runtimeType, debugMessage];
}

enum StorageFailureKind {
  notFound,
  insufficientSpace,
  readError,
  writeError,
  corrupted,
  alreadyExists,
}

final class StorageFailure extends Failure {
  const StorageFailure(this.kind, {super.debugMessage});

  final StorageFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

enum AppPermission { camera, photos, biometrics, notifications }

final class PermissionFailure extends Failure {
  const PermissionFailure(
    this.permission, {
    this.permanentlyDenied = false,
    super.debugMessage,
  });

  final AppPermission permission;
  final bool permanentlyDenied;

  @override
  List<Object?> get props => [permission, permanentlyDenied, debugMessage];
}

enum CameraFailureKind { unavailable, initializationFailed, captureFailed }

final class CameraFailure extends Failure {
  const CameraFailure(this.kind, {super.debugMessage});

  final CameraFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

enum ImageFailureKind {
  decodeFailed,
  unsupportedFormat,
  tooLarge,
  processingFailed,
}

final class ImageFailure extends Failure {
  const ImageFailure(this.kind, {super.debugMessage});

  final ImageFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

enum PdfFailureKind {
  passwordRequired,
  wrongPassword,
  corrupted,
  unsupported,
  emptyDocument,
  invalidPageRange,
  engineUnavailable,
  operationFailed,
}

final class PdfFailure extends Failure {
  const PdfFailure(this.kind, {super.debugMessage});

  final PdfFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

enum OcrFailureKind {
  noTextFound,
  engineUnavailable,
  modelUnavailable,
  recognitionFailed,
}

final class OcrFailure extends Failure {
  const OcrFailure(this.kind, {super.debugMessage});

  final OcrFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

enum ScanFailureKind {
  scannerUnavailable,
  noDocumentDetected,
  sessionNotFound,
  failed,
}

final class ScanFailure extends Failure {
  const ScanFailure(this.kind, {super.debugMessage});

  final ScanFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

enum SecurityFailureKind {
  wrongPin,
  lockedOut,
  pinNotSet,
  biometricUnavailable,
  biometricNotEnrolled,
  biometricFailed,
  keyUnavailable,
  decryptionFailed,
  encryptionFailed,
}

final class SecurityFailure extends Failure {
  const SecurityFailure(this.kind, {this.retryAfter, super.debugMessage});

  final SecurityFailureKind kind;

  /// Remaining lock-out delay when [kind] is [SecurityFailureKind.lockedOut].
  final Duration? retryAfter;

  @override
  List<Object?> get props => [kind, retryAfter, debugMessage];
}

enum NetworkFailureKind {
  offline,
  timeout,
  serverError,
  unauthorized,
  quotaExceeded,
  rateLimited,
  notConfigured,
  invalidResponse,
}

final class NetworkFailure extends Failure {
  const NetworkFailure(this.kind, {this.statusCode, super.debugMessage});

  final NetworkFailureKind kind;
  final int? statusCode;

  @override
  List<Object?> get props => [kind, statusCode, debugMessage];
}

enum BillingFailureKind {
  storeUnavailable,
  productNotFound,
  userCancelled,
  pending,
  alreadyOwned,
  verificationFailed,
  purchaseFailed,
}

final class BillingFailure extends Failure {
  const BillingFailure(this.kind, {super.debugMessage});

  final BillingFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

enum AdFailureKind { notConfigured, loadFailed, showFailed, consentRequired }

final class AdFailure extends Failure {
  const AdFailure(this.kind, {super.debugMessage});

  final AdFailureKind kind;

  @override
  List<Object?> get props => [kind, debugMessage];
}

/// Invalid user input. [code] is a stable identifier mapped to a localized
/// message by the feature that raised it (for example `ean13_checksum`).
final class ValidationFailure extends Failure {
  const ValidationFailure(this.code, {super.debugMessage});

  final String code;

  @override
  List<Object?> get props => [code, debugMessage];
}

/// The user (or the app lifecycle) cancelled the operation. Not an error to
/// display: callers usually just return to the previous state.
final class CancelledFailure extends Failure {
  const CancelledFailure({super.debugMessage});
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({super.debugMessage});
}
