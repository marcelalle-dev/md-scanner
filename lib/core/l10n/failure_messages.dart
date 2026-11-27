import 'package:flutter/widgets.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/l10n/generated/core_localizations.dart';

/// Localized, user-facing message for a [Failure].
///
/// The switch is exhaustive over the sealed [Failure] hierarchy: adding a new
/// failure type or kind is a compile error here until it gets a message.
String failureMessage(BuildContext context, Failure failure) =>
    failureMessageFor(CoreLocalizations.of(context), failure);

String failureMessageFor(CoreLocalizations l10n, Failure failure) {
  return switch (failure) {
    StorageFailure(:final kind) => switch (kind) {
      StorageFailureKind.notFound => l10n.errorStorageNotFound,
      StorageFailureKind.insufficientSpace =>
        l10n.errorStorageInsufficientSpace,
      StorageFailureKind.readError => l10n.errorStorageRead,
      StorageFailureKind.writeError => l10n.errorStorageWrite,
      StorageFailureKind.corrupted => l10n.errorStorageCorrupted,
      StorageFailureKind.alreadyExists => l10n.errorStorageAlreadyExists,
    },
    PermissionFailure(:final permission, :final permanentlyDenied) =>
      switch (permission) {
        AppPermission.camera =>
          permanentlyDenied
              ? l10n.errorPermissionCameraPermanent
              : l10n.errorPermissionCamera,
        AppPermission.photos => l10n.errorPermissionPhotos,
        AppPermission.biometrics => l10n.errorPermissionBiometrics,
        AppPermission.notifications => l10n.errorPermissionNotifications,
      },
    CameraFailure(:final kind) => switch (kind) {
      CameraFailureKind.unavailable => l10n.errorCameraUnavailable,
      CameraFailureKind.initializationFailed => l10n.errorCameraInit,
      CameraFailureKind.captureFailed => l10n.errorCameraCapture,
    },
    ImageFailure(:final kind) => switch (kind) {
      ImageFailureKind.decodeFailed => l10n.errorImageDecode,
      ImageFailureKind.unsupportedFormat => l10n.errorImageUnsupported,
      ImageFailureKind.tooLarge => l10n.errorImageTooLarge,
      ImageFailureKind.processingFailed => l10n.errorImageProcessing,
    },
    PdfFailure(:final kind) => switch (kind) {
      PdfFailureKind.passwordRequired => l10n.errorPdfPasswordRequired,
      PdfFailureKind.wrongPassword => l10n.errorPdfWrongPassword,
      PdfFailureKind.corrupted => l10n.errorPdfCorrupted,
      PdfFailureKind.unsupported => l10n.errorPdfUnsupported,
      PdfFailureKind.emptyDocument => l10n.errorPdfEmpty,
      PdfFailureKind.invalidPageRange => l10n.errorPdfInvalidRange,
      PdfFailureKind.engineUnavailable => l10n.errorPdfEngineUnavailable,
      PdfFailureKind.operationFailed => l10n.errorPdfOperationFailed,
    },
    OcrFailure(:final kind) => switch (kind) {
      OcrFailureKind.noTextFound => l10n.errorOcrNoText,
      OcrFailureKind.engineUnavailable => l10n.errorOcrEngineUnavailable,
      OcrFailureKind.modelUnavailable => l10n.errorOcrModelUnavailable,
      OcrFailureKind.recognitionFailed => l10n.errorOcrFailed,
    },
    ScanFailure(:final kind) => switch (kind) {
      ScanFailureKind.scannerUnavailable => l10n.errorScanUnavailable,
      ScanFailureKind.noDocumentDetected => l10n.errorScanNoDocument,
      ScanFailureKind.sessionNotFound => l10n.errorScanSessionNotFound,
      ScanFailureKind.failed => l10n.errorScanFailed,
    },
    SecurityFailure(:final kind, :final retryAfter) => switch (kind) {
      SecurityFailureKind.wrongPin => l10n.errorSecurityWrongPin,
      SecurityFailureKind.lockedOut => l10n.errorSecurityLockedOut(
        retryAfter == null ? 0 : (retryAfter.inMilliseconds / 1000).ceil(),
      ),
      SecurityFailureKind.pinNotSet => l10n.errorSecurityPinNotSet,
      SecurityFailureKind.biometricUnavailable =>
        l10n.errorSecurityBiometricUnavailable,
      SecurityFailureKind.biometricNotEnrolled =>
        l10n.errorSecurityBiometricNotEnrolled,
      SecurityFailureKind.biometricFailed => l10n.errorSecurityBiometricFailed,
      SecurityFailureKind.keyUnavailable => l10n.errorSecurityKeyUnavailable,
      SecurityFailureKind.decryptionFailed => l10n.errorSecurityDecryption,
      SecurityFailureKind.encryptionFailed => l10n.errorSecurityEncryption,
    },
    NetworkFailure(:final kind) => switch (kind) {
      NetworkFailureKind.offline => l10n.errorNetworkOffline,
      NetworkFailureKind.timeout => l10n.errorNetworkTimeout,
      NetworkFailureKind.serverError => l10n.errorNetworkServer,
      NetworkFailureKind.unauthorized => l10n.errorNetworkUnauthorized,
      NetworkFailureKind.quotaExceeded => l10n.errorNetworkQuota,
      NetworkFailureKind.rateLimited => l10n.errorNetworkRateLimited,
      NetworkFailureKind.notConfigured => l10n.errorNetworkNotConfigured,
      NetworkFailureKind.invalidResponse => l10n.errorNetworkInvalidResponse,
    },
    BillingFailure(:final kind) => switch (kind) {
      BillingFailureKind.storeUnavailable => l10n.errorBillingStoreUnavailable,
      BillingFailureKind.productNotFound => l10n.errorBillingProductNotFound,
      BillingFailureKind.userCancelled => l10n.errorCancelled,
      BillingFailureKind.pending => l10n.errorBillingPending,
      BillingFailureKind.alreadyOwned => l10n.errorBillingAlreadyOwned,
      BillingFailureKind.verificationFailed =>
        l10n.errorBillingVerificationFailed,
      BillingFailureKind.purchaseFailed => l10n.errorBillingPurchaseFailed,
    },
    AdFailure(:final kind) => switch (kind) {
      AdFailureKind.notConfigured => l10n.errorAdNotConfigured,
      AdFailureKind.loadFailed => l10n.errorAdLoadFailed,
      AdFailureKind.showFailed => l10n.errorAdShowFailed,
      AdFailureKind.consentRequired => l10n.errorAdConsentRequired,
    },
    ValidationFailure() => l10n.errorValidation,
    CancelledFailure() => l10n.errorCancelled,
    UnexpectedFailure() => l10n.errorUnexpected,
  };
}
