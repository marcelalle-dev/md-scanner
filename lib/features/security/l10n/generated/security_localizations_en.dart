// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'security_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SecurityLocalizationsEn extends SecurityLocalizations {
  SecurityLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get vaultTitle => 'Vault';

  @override
  String get vaultHint => 'Encrypted documents, protected by a PIN';

  @override
  String get vaultSetupTitle => 'Create your PIN';

  @override
  String get vaultSetupMessage =>
      'The vault encrypts your sensitive documents on this device. Choose a code of 4 to 8 digits. This code cannot be recovered: if you forget it, the documents in the vault are lost.';

  @override
  String get vaultPin => 'PIN';

  @override
  String get vaultPinConfirm => 'Confirm the PIN';

  @override
  String get vaultPinInvalid => 'The code must be 4 to 8 digits long.';

  @override
  String get vaultPinMismatch => 'The two codes do not match.';

  @override
  String get vaultCreate => 'Create the vault';

  @override
  String get vaultLockedTitle => 'Vault locked';

  @override
  String get vaultUnlock => 'Unlock';

  @override
  String get vaultUseBiometrics => 'Use biometrics';

  @override
  String get vaultBiometricReason => 'Unlock your MD SCANNER vault';

  @override
  String get vaultEmpty => 'The vault is empty';

  @override
  String get vaultEmptyHint =>
      'Add a document: it is encrypted and removed from the library.';

  @override
  String get vaultAdd => 'Add a document';

  @override
  String get vaultChoose => 'Choose a document to protect';

  @override
  String get vaultNothingToAdd => 'No document in the library.';

  @override
  String get vaultEncrypting => 'Encrypting document…';

  @override
  String get vaultDecrypting => 'Decrypting document…';

  @override
  String get vaultAdded => 'Document encrypted and moved to the vault';

  @override
  String get vaultRemoved => 'Document moved back to the library';

  @override
  String get vaultOpen => 'Open';

  @override
  String get vaultRemove => 'Remove from vault';

  @override
  String get vaultLockNow => 'Lock';

  @override
  String get vaultBiometricSetting => 'Biometric unlock';

  @override
  String get vaultBiometricUnavailable =>
      'No biometrics are set up on this device.';

  @override
  String get vaultRemovePin => 'Remove the PIN';

  @override
  String get vaultRemovePinBlocked =>
      'Take every document out of the vault first.';

  @override
  String get vaultRemovePinConfirm => 'Enter your PIN to remove it';

  @override
  String get vaultPinRemoved => 'PIN removed';

  @override
  String get vaultMoveHere => 'Move to vault';

  @override
  String get vaultPreviewUnavailable =>
      'This file type cannot be displayed here. Remove it from the vault to open it.';
}
