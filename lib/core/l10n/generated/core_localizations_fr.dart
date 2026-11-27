// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class CoreLocalizationsFr extends CoreLocalizations {
  CoreLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'MD SCANNER';

  @override
  String get actionOk => 'OK';

  @override
  String get actionCancel => 'Annuler';

  @override
  String get actionSave => 'Enregistrer';

  @override
  String get actionDelete => 'Supprimer';

  @override
  String get actionShare => 'Partager';

  @override
  String get actionRetry => 'Réessayer';

  @override
  String get actionClose => 'Fermer';

  @override
  String get actionContinue => 'Continuer';

  @override
  String get actionBack => 'Retour';

  @override
  String get actionDone => 'Terminer';

  @override
  String get actionEdit => 'Modifier';

  @override
  String get actionRename => 'Renommer';

  @override
  String get actionCopy => 'Copier';

  @override
  String get actionExport => 'Exporter';

  @override
  String get actionImport => 'Importer';

  @override
  String get actionOpen => 'Ouvrir';

  @override
  String get actionSearch => 'Rechercher';

  @override
  String get actionConfirm => 'Confirmer';

  @override
  String get actionAdd => 'Ajouter';

  @override
  String get actionNext => 'Suivant';

  @override
  String get actionSkip => 'Passer';

  @override
  String get actionYes => 'Oui';

  @override
  String get actionNo => 'Non';

  @override
  String get actionPrint => 'Imprimer';

  @override
  String get actionMore => 'Plus d\'options';

  @override
  String get actionSelectAll => 'Tout sélectionner';

  @override
  String get actionOpenSettings => 'Ouvrir les réglages';

  @override
  String get actionUnlockPremium => 'Passer à Premium';

  @override
  String get actionShowPassword => 'Afficher le mot de passe';

  @override
  String get actionHidePassword => 'Masquer le mot de passe';

  @override
  String get labelLoading => 'Chargement…';

  @override
  String get labelProcessing => 'Traitement en cours…';

  @override
  String get labelPremium => 'Premium';

  @override
  String get labelOffline => 'Hors connexion';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get savedToLibrary => 'Enregistré dans vos documents';

  @override
  String get premiumRequiredTitle => 'Fonction Premium';

  @override
  String get premiumRequiredMessage =>
      'Cette fonction est réservée aux abonnés Premium.';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
      zero: 'Aucune page',
    );
    return '$_temp0';
  }

  @override
  String fileSizeBytes(String value) {
    return '$value o';
  }

  @override
  String fileSizeKilobytes(String value) {
    return '$value Ko';
  }

  @override
  String fileSizeMegabytes(String value) {
    return '$value Mo';
  }

  @override
  String fileSizeGigabytes(String value) {
    return '$value Go';
  }

  @override
  String get errorStorageNotFound =>
      'Fichier introuvable. Il a peut-être été déplacé ou supprimé.';

  @override
  String get errorStorageInsufficientSpace =>
      'Espace de stockage insuffisant. Libérez de l\'espace puis réessayez.';

  @override
  String get errorStorageRead => 'Impossible de lire ce fichier.';

  @override
  String get errorStorageWrite => 'Impossible d\'enregistrer le fichier.';

  @override
  String get errorStorageCorrupted =>
      'Ce fichier est endommagé et ne peut pas être ouvert.';

  @override
  String get errorStorageAlreadyExists =>
      'Un élément portant ce nom existe déjà.';

  @override
  String get errorPermissionCamera =>
      'L\'accès à l\'appareil photo est nécessaire pour numériser.';

  @override
  String get errorPermissionCameraPermanent =>
      'L\'accès à l\'appareil photo est désactivé. Activez-le dans les réglages de l\'application.';

  @override
  String get errorPermissionPhotos => 'L\'accès aux photos a été refusé.';

  @override
  String get errorPermissionBiometrics =>
      'L\'authentification biométrique n\'est pas autorisée.';

  @override
  String get errorPermissionNotifications =>
      'Les notifications sont désactivées.';

  @override
  String get errorCameraUnavailable =>
      'Aucun appareil photo disponible sur cet appareil.';

  @override
  String get errorCameraInit => 'Impossible de démarrer l\'appareil photo.';

  @override
  String get errorCameraCapture => 'La capture a échoué. Réessayez.';

  @override
  String get errorImageDecode => 'Cette image est illisible ou endommagée.';

  @override
  String get errorImageUnsupported =>
      'Ce format d\'image n\'est pas pris en charge.';

  @override
  String get errorImageTooLarge =>
      'Cette image est trop volumineuse pour être traitée.';

  @override
  String get errorImageProcessing => 'Le traitement de l\'image a échoué.';

  @override
  String get errorPdfPasswordRequired => 'Ce PDF est protégé par mot de passe.';

  @override
  String get errorPdfWrongPassword => 'Mot de passe incorrect.';

  @override
  String get errorPdfCorrupted =>
      'Ce PDF est endommagé et ne peut pas être ouvert.';

  @override
  String get errorPdfUnsupported =>
      'Ce PDF utilise une fonctionnalité non prise en charge.';

  @override
  String get errorPdfEmpty => 'Ce document ne contient aucune page.';

  @override
  String get errorPdfInvalidRange => 'La sélection de pages n\'est pas valide.';

  @override
  String get errorPdfEngineUnavailable =>
      'Le moteur PDF n\'est pas disponible sur cet appareil.';

  @override
  String get errorPdfOperationFailed => 'L\'opération sur le PDF a échoué.';

  @override
  String get errorOcrNoText => 'Aucun texte n\'a été détecté.';

  @override
  String get errorOcrEngineUnavailable =>
      'La reconnaissance de texte n\'est pas disponible sur cet appareil.';

  @override
  String get errorOcrModelUnavailable =>
      'Le modèle de reconnaissance n\'est pas encore disponible. Connectez-vous à Internet une première fois puis réessayez.';

  @override
  String get errorOcrFailed => 'La reconnaissance de texte a échoué.';

  @override
  String get errorScanUnavailable =>
      'Le scanner n\'est pas disponible sur cet appareil.';

  @override
  String get errorScanNoDocument => 'Aucun document détecté.';

  @override
  String get errorScanSessionNotFound =>
      'Cette session de numérisation n\'existe plus.';

  @override
  String get errorScanFailed => 'La numérisation a échoué.';

  @override
  String get errorSecurityWrongPin => 'Code PIN incorrect.';

  @override
  String errorSecurityLockedOut(int seconds) {
    return 'Trop de tentatives. Réessayez dans $seconds s.';
  }

  @override
  String get errorSecurityPinNotSet => 'Aucun code PIN n\'est défini.';

  @override
  String get errorSecurityBiometricUnavailable =>
      'La biométrie n\'est pas disponible sur cet appareil.';

  @override
  String get errorSecurityBiometricNotEnrolled =>
      'Aucune empreinte ni visage n\'est enregistré sur cet appareil.';

  @override
  String get errorSecurityBiometricFailed =>
      'L\'authentification biométrique a échoué.';

  @override
  String get errorSecurityKeyUnavailable =>
      'La clé de chiffrement est indisponible. Le coffre-fort ne peut pas être ouvert.';

  @override
  String get errorSecurityDecryption => 'Impossible de déchiffrer ce fichier.';

  @override
  String get errorSecurityEncryption => 'Impossible de chiffrer ce fichier.';

  @override
  String get errorNetworkOffline => 'Pas de connexion Internet.';

  @override
  String get errorNetworkTimeout => 'Le serveur met trop de temps à répondre.';

  @override
  String get errorNetworkServer => 'Le service est momentanément indisponible.';

  @override
  String get errorNetworkUnauthorized => 'Accès refusé par le service.';

  @override
  String get errorNetworkQuota => 'Votre quota est atteint pour cette période.';

  @override
  String get errorNetworkRateLimited =>
      'Trop de requêtes. Patientez un instant.';

  @override
  String get errorNetworkNotConfigured => 'Ce service n\'est pas configuré.';

  @override
  String get errorNetworkInvalidResponse => 'Réponse inattendue du service.';

  @override
  String get errorBillingStoreUnavailable =>
      'Google Play n\'est pas disponible. Vérifiez votre connexion et votre compte.';

  @override
  String get errorBillingProductNotFound =>
      'Cette offre n\'est pas disponible pour le moment.';

  @override
  String get errorBillingPending => 'Votre achat est en attente de validation.';

  @override
  String get errorBillingAlreadyOwned => 'Vous possédez déjà cette offre.';

  @override
  String get errorBillingVerificationFailed =>
      'L\'achat n\'a pas pu être vérifié.';

  @override
  String get errorBillingPurchaseFailed => 'L\'achat n\'a pas abouti.';

  @override
  String get errorAdNotConfigured => 'Les publicités ne sont pas configurées.';

  @override
  String get errorAdLoadFailed => 'Aucune publicité disponible pour le moment.';

  @override
  String get errorAdShowFailed => 'La publicité n\'a pas pu être affichée.';

  @override
  String get errorAdConsentRequired =>
      'Votre choix de confidentialité est requis.';

  @override
  String get errorValidation => 'La valeur saisie n\'est pas valide.';

  @override
  String get errorCancelled => 'Opération annulée.';

  @override
  String get errorUnexpected => 'Une erreur inattendue s\'est produite.';
}
