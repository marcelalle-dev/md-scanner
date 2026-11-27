// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'security_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class SecurityLocalizationsFr extends SecurityLocalizations {
  SecurityLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get vaultTitle => 'Coffre-fort';

  @override
  String get vaultHint => 'Documents chiffrés, protégés par code PIN';

  @override
  String get vaultSetupTitle => 'Créez votre code PIN';

  @override
  String get vaultSetupMessage =>
      'Le coffre-fort chiffre vos documents sensibles sur cet appareil. Choisissez un code de 4 à 8 chiffres. Ce code ne peut pas être récupéré : si vous l\'oubliez, les documents du coffre seront perdus.';

  @override
  String get vaultPin => 'Code PIN';

  @override
  String get vaultPinConfirm => 'Confirmez le code PIN';

  @override
  String get vaultPinInvalid => 'Le code doit comporter 4 à 8 chiffres.';

  @override
  String get vaultPinMismatch => 'Les deux codes ne correspondent pas.';

  @override
  String get vaultCreate => 'Créer le coffre-fort';

  @override
  String get vaultLockedTitle => 'Coffre-fort verrouillé';

  @override
  String get vaultUnlock => 'Déverrouiller';

  @override
  String get vaultUseBiometrics => 'Utiliser la biométrie';

  @override
  String get vaultBiometricReason =>
      'Déverrouillez votre coffre-fort MD SCANNER';

  @override
  String get vaultEmpty => 'Le coffre-fort est vide';

  @override
  String get vaultEmptyHint =>
      'Ajoutez un document : il sera chiffré et retiré de la bibliothèque.';

  @override
  String get vaultAdd => 'Ajouter un document';

  @override
  String get vaultChoose => 'Choisir un document à protéger';

  @override
  String get vaultNothingToAdd => 'Aucun document dans la bibliothèque.';

  @override
  String get vaultEncrypting => 'Chiffrement du document…';

  @override
  String get vaultDecrypting => 'Déchiffrement du document…';

  @override
  String get vaultAdded => 'Document chiffré et placé dans le coffre-fort';

  @override
  String get vaultRemoved => 'Document replacé dans la bibliothèque';

  @override
  String get vaultOpen => 'Ouvrir';

  @override
  String get vaultRemove => 'Sortir du coffre-fort';

  @override
  String get vaultLockNow => 'Verrouiller';

  @override
  String get vaultBiometricSetting => 'Déverrouillage biométrique';

  @override
  String get vaultBiometricUnavailable =>
      'Aucune biométrie n\'est configurée sur cet appareil.';

  @override
  String get vaultRemovePin => 'Supprimer le code PIN';

  @override
  String get vaultRemovePinBlocked =>
      'Sortez d\'abord tous les documents du coffre-fort.';

  @override
  String get vaultRemovePinConfirm =>
      'Saisissez votre code PIN pour le supprimer';

  @override
  String get vaultPinRemoved => 'Code PIN supprimé';

  @override
  String get vaultMoveHere => 'Mettre au coffre-fort';

  @override
  String get vaultPreviewUnavailable =>
      'Ce type de fichier ne peut pas être affiché ici. Sortez-le du coffre-fort pour l\'ouvrir.';
}
