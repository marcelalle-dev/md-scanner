// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class CoreLocalizationsEn extends CoreLocalizations {
  CoreLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'MD SCANNER';

  @override
  String get actionOk => 'OK';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionShare => 'Share';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionClose => 'Close';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionBack => 'Back';

  @override
  String get actionDone => 'Done';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionRename => 'Rename';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionExport => 'Export';

  @override
  String get actionImport => 'Import';

  @override
  String get actionOpen => 'Open';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionNext => 'Next';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionYes => 'Yes';

  @override
  String get actionNo => 'No';

  @override
  String get actionPrint => 'Print';

  @override
  String get actionMore => 'More options';

  @override
  String get actionSelectAll => 'Select all';

  @override
  String get actionOpenSettings => 'Open settings';

  @override
  String get actionUnlockPremium => 'Go Premium';

  @override
  String get labelLoading => 'Loading…';

  @override
  String get labelProcessing => 'Processing…';

  @override
  String get labelPremium => 'Premium';

  @override
  String get labelOffline => 'Offline';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get savedToLibrary => 'Saved to your documents';

  @override
  String get premiumRequiredTitle => 'Premium feature';

  @override
  String get premiumRequiredMessage =>
      'This feature is reserved for Premium subscribers.';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
      zero: 'No pages',
    );
    return '$_temp0';
  }

  @override
  String fileSizeBytes(String value) {
    return '$value B';
  }

  @override
  String fileSizeKilobytes(String value) {
    return '$value KB';
  }

  @override
  String fileSizeMegabytes(String value) {
    return '$value MB';
  }

  @override
  String fileSizeGigabytes(String value) {
    return '$value GB';
  }

  @override
  String get errorStorageNotFound =>
      'File not found. It may have been moved or deleted.';

  @override
  String get errorStorageInsufficientSpace =>
      'Not enough storage space. Free up some space and try again.';

  @override
  String get errorStorageRead => 'This file could not be read.';

  @override
  String get errorStorageWrite => 'The file could not be saved.';

  @override
  String get errorStorageCorrupted =>
      'This file is damaged and cannot be opened.';

  @override
  String get errorStorageAlreadyExists =>
      'An item with this name already exists.';

  @override
  String get errorPermissionCamera => 'Camera access is required to scan.';

  @override
  String get errorPermissionCameraPermanent =>
      'Camera access is turned off. Enable it in the app settings.';

  @override
  String get errorPermissionPhotos => 'Access to photos was denied.';

  @override
  String get errorPermissionBiometrics =>
      'Biometric authentication is not allowed.';

  @override
  String get errorPermissionNotifications => 'Notifications are turned off.';

  @override
  String get errorCameraUnavailable => 'No camera is available on this device.';

  @override
  String get errorCameraInit => 'The camera could not be started.';

  @override
  String get errorCameraCapture => 'Capture failed. Please try again.';

  @override
  String get errorImageDecode => 'This image is unreadable or damaged.';

  @override
  String get errorImageUnsupported => 'This image format is not supported.';

  @override
  String get errorImageTooLarge => 'This image is too large to be processed.';

  @override
  String get errorImageProcessing => 'Image processing failed.';

  @override
  String get errorPdfPasswordRequired => 'This PDF is password protected.';

  @override
  String get errorPdfWrongPassword => 'Incorrect password.';

  @override
  String get errorPdfCorrupted => 'This PDF is damaged and cannot be opened.';

  @override
  String get errorPdfUnsupported => 'This PDF uses an unsupported feature.';

  @override
  String get errorPdfEmpty => 'This document has no pages.';

  @override
  String get errorPdfInvalidRange => 'The page selection is not valid.';

  @override
  String get errorPdfEngineUnavailable =>
      'The PDF engine is not available on this device.';

  @override
  String get errorPdfOperationFailed => 'The PDF operation failed.';

  @override
  String get errorOcrNoText => 'No text was detected.';

  @override
  String get errorOcrEngineUnavailable =>
      'Text recognition is not available on this device.';

  @override
  String get errorOcrModelUnavailable =>
      'The recognition model is not available yet. Connect to the Internet once, then try again.';

  @override
  String get errorOcrFailed => 'Text recognition failed.';

  @override
  String get errorScanUnavailable =>
      'The scanner is not available on this device.';

  @override
  String get errorScanNoDocument => 'No document detected.';

  @override
  String get errorScanSessionNotFound => 'This scan session no longer exists.';

  @override
  String get errorScanFailed => 'Scanning failed.';

  @override
  String get errorSecurityWrongPin => 'Incorrect PIN.';

  @override
  String errorSecurityLockedOut(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get errorSecurityPinNotSet => 'No PIN has been set.';

  @override
  String get errorSecurityBiometricUnavailable =>
      'Biometrics are not available on this device.';

  @override
  String get errorSecurityBiometricNotEnrolled =>
      'No fingerprint or face is enrolled on this device.';

  @override
  String get errorSecurityBiometricFailed => 'Biometric authentication failed.';

  @override
  String get errorSecurityKeyUnavailable =>
      'The encryption key is unavailable. The vault cannot be opened.';

  @override
  String get errorSecurityDecryption => 'This file could not be decrypted.';

  @override
  String get errorSecurityEncryption => 'This file could not be encrypted.';

  @override
  String get errorNetworkOffline => 'No Internet connection.';

  @override
  String get errorNetworkTimeout => 'The server is taking too long to respond.';

  @override
  String get errorNetworkServer => 'The service is temporarily unavailable.';

  @override
  String get errorNetworkUnauthorized => 'Access was denied by the service.';

  @override
  String get errorNetworkQuota =>
      'You have reached your quota for this period.';

  @override
  String get errorNetworkRateLimited =>
      'Too many requests. Please wait a moment.';

  @override
  String get errorNetworkNotConfigured => 'This service is not configured.';

  @override
  String get errorNetworkInvalidResponse =>
      'Unexpected response from the service.';

  @override
  String get errorBillingStoreUnavailable =>
      'Google Play is not available. Check your connection and account.';

  @override
  String get errorBillingProductNotFound =>
      'This offer is not available right now.';

  @override
  String get errorBillingPending => 'Your purchase is pending approval.';

  @override
  String get errorBillingAlreadyOwned => 'You already own this offer.';

  @override
  String get errorBillingVerificationFailed =>
      'The purchase could not be verified.';

  @override
  String get errorBillingPurchaseFailed => 'The purchase did not go through.';

  @override
  String get errorAdNotConfigured => 'Ads are not configured.';

  @override
  String get errorAdLoadFailed => 'No ad is available right now.';

  @override
  String get errorAdShowFailed => 'The ad could not be shown.';

  @override
  String get errorAdConsentRequired => 'Your privacy choice is required.';

  @override
  String get errorValidation => 'The value entered is not valid.';

  @override
  String get errorCancelled => 'Operation cancelled.';

  @override
  String get errorUnexpected => 'An unexpected error occurred.';
}
