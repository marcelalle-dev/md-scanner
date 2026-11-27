import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'core_localizations_en.dart';
import 'core_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of CoreLocalizations
/// returned by `CoreLocalizations.of(context)`.
///
/// Applications need to include `CoreLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/core_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: CoreLocalizations.localizationsDelegates,
///   supportedLocales: CoreLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the CoreLocalizations.supportedLocales
/// property.
abstract class CoreLocalizations {
  CoreLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static CoreLocalizations of(BuildContext context) {
    return Localizations.of<CoreLocalizations>(context, CoreLocalizations)!;
  }

  static const LocalizationsDelegate<CoreLocalizations> delegate =
      _CoreLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appName.
  ///
  /// In fr, this message translates to:
  /// **'MD SCANNER'**
  String get appName;

  /// No description provided for @actionOk.
  ///
  /// In fr, this message translates to:
  /// **'OK'**
  String get actionOk;

  /// No description provided for @actionCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get actionSave;

  /// No description provided for @actionDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get actionDelete;

  /// No description provided for @actionShare.
  ///
  /// In fr, this message translates to:
  /// **'Partager'**
  String get actionShare;

  /// No description provided for @actionRetry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get actionRetry;

  /// No description provided for @actionClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get actionClose;

  /// No description provided for @actionContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get actionContinue;

  /// No description provided for @actionBack.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get actionBack;

  /// No description provided for @actionDone.
  ///
  /// In fr, this message translates to:
  /// **'Terminer'**
  String get actionDone;

  /// No description provided for @actionEdit.
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get actionEdit;

  /// No description provided for @actionRename.
  ///
  /// In fr, this message translates to:
  /// **'Renommer'**
  String get actionRename;

  /// No description provided for @actionCopy.
  ///
  /// In fr, this message translates to:
  /// **'Copier'**
  String get actionCopy;

  /// No description provided for @actionExport.
  ///
  /// In fr, this message translates to:
  /// **'Exporter'**
  String get actionExport;

  /// No description provided for @actionImport.
  ///
  /// In fr, this message translates to:
  /// **'Importer'**
  String get actionImport;

  /// No description provided for @actionOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get actionOpen;

  /// No description provided for @actionSearch.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get actionSearch;

  /// No description provided for @actionConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get actionConfirm;

  /// No description provided for @actionAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get actionAdd;

  /// No description provided for @actionNext.
  ///
  /// In fr, this message translates to:
  /// **'Suivant'**
  String get actionNext;

  /// No description provided for @actionSkip.
  ///
  /// In fr, this message translates to:
  /// **'Passer'**
  String get actionSkip;

  /// No description provided for @actionYes.
  ///
  /// In fr, this message translates to:
  /// **'Oui'**
  String get actionYes;

  /// No description provided for @actionNo.
  ///
  /// In fr, this message translates to:
  /// **'Non'**
  String get actionNo;

  /// No description provided for @actionPrint.
  ///
  /// In fr, this message translates to:
  /// **'Imprimer'**
  String get actionPrint;

  /// No description provided for @actionMore.
  ///
  /// In fr, this message translates to:
  /// **'Plus d\'options'**
  String get actionMore;

  /// No description provided for @actionSelectAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout sélectionner'**
  String get actionSelectAll;

  /// No description provided for @actionOpenSettings.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir les réglages'**
  String get actionOpenSettings;

  /// No description provided for @actionUnlockPremium.
  ///
  /// In fr, this message translates to:
  /// **'Passer à Premium'**
  String get actionUnlockPremium;

  /// No description provided for @actionShowPassword.
  ///
  /// In fr, this message translates to:
  /// **'Afficher le mot de passe'**
  String get actionShowPassword;

  /// No description provided for @actionHidePassword.
  ///
  /// In fr, this message translates to:
  /// **'Masquer le mot de passe'**
  String get actionHidePassword;

  /// No description provided for @labelLoading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement…'**
  String get labelLoading;

  /// No description provided for @labelProcessing.
  ///
  /// In fr, this message translates to:
  /// **'Traitement en cours…'**
  String get labelProcessing;

  /// No description provided for @labelPremium.
  ///
  /// In fr, this message translates to:
  /// **'Premium'**
  String get labelPremium;

  /// No description provided for @labelOffline.
  ///
  /// In fr, this message translates to:
  /// **'Hors connexion'**
  String get labelOffline;

  /// No description provided for @copiedToClipboard.
  ///
  /// In fr, this message translates to:
  /// **'Copié dans le presse-papiers'**
  String get copiedToClipboard;

  /// No description provided for @savedToLibrary.
  ///
  /// In fr, this message translates to:
  /// **'Enregistré dans vos documents'**
  String get savedToLibrary;

  /// No description provided for @premiumRequiredTitle.
  ///
  /// In fr, this message translates to:
  /// **'Fonction Premium'**
  String get premiumRequiredTitle;

  /// No description provided for @premiumRequiredMessage.
  ///
  /// In fr, this message translates to:
  /// **'Cette fonction est réservée aux abonnés Premium.'**
  String get premiumRequiredMessage;

  /// No description provided for @pageCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucune page} =1{1 page} other{{count} pages}}'**
  String pageCount(int count);

  /// No description provided for @fileSizeBytes.
  ///
  /// In fr, this message translates to:
  /// **'{value} o'**
  String fileSizeBytes(String value);

  /// No description provided for @fileSizeKilobytes.
  ///
  /// In fr, this message translates to:
  /// **'{value} Ko'**
  String fileSizeKilobytes(String value);

  /// No description provided for @fileSizeMegabytes.
  ///
  /// In fr, this message translates to:
  /// **'{value} Mo'**
  String fileSizeMegabytes(String value);

  /// No description provided for @fileSizeGigabytes.
  ///
  /// In fr, this message translates to:
  /// **'{value} Go'**
  String fileSizeGigabytes(String value);

  /// No description provided for @errorStorageNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Fichier introuvable. Il a peut-être été déplacé ou supprimé.'**
  String get errorStorageNotFound;

  /// No description provided for @errorStorageInsufficientSpace.
  ///
  /// In fr, this message translates to:
  /// **'Espace de stockage insuffisant. Libérez de l\'espace puis réessayez.'**
  String get errorStorageInsufficientSpace;

  /// No description provided for @errorStorageRead.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de lire ce fichier.'**
  String get errorStorageRead;

  /// No description provided for @errorStorageWrite.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'enregistrer le fichier.'**
  String get errorStorageWrite;

  /// No description provided for @errorStorageCorrupted.
  ///
  /// In fr, this message translates to:
  /// **'Ce fichier est endommagé et ne peut pas être ouvert.'**
  String get errorStorageCorrupted;

  /// No description provided for @errorStorageAlreadyExists.
  ///
  /// In fr, this message translates to:
  /// **'Un élément portant ce nom existe déjà.'**
  String get errorStorageAlreadyExists;

  /// No description provided for @errorPermissionCamera.
  ///
  /// In fr, this message translates to:
  /// **'L\'accès à l\'appareil photo est nécessaire pour numériser.'**
  String get errorPermissionCamera;

  /// No description provided for @errorPermissionCameraPermanent.
  ///
  /// In fr, this message translates to:
  /// **'L\'accès à l\'appareil photo est désactivé. Activez-le dans les réglages de l\'application.'**
  String get errorPermissionCameraPermanent;

  /// No description provided for @errorPermissionPhotos.
  ///
  /// In fr, this message translates to:
  /// **'L\'accès aux photos a été refusé.'**
  String get errorPermissionPhotos;

  /// No description provided for @errorPermissionBiometrics.
  ///
  /// In fr, this message translates to:
  /// **'L\'authentification biométrique n\'est pas autorisée.'**
  String get errorPermissionBiometrics;

  /// No description provided for @errorPermissionNotifications.
  ///
  /// In fr, this message translates to:
  /// **'Les notifications sont désactivées.'**
  String get errorPermissionNotifications;

  /// No description provided for @errorCameraUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Aucun appareil photo disponible sur cet appareil.'**
  String get errorCameraUnavailable;

  /// No description provided for @errorCameraInit.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de démarrer l\'appareil photo.'**
  String get errorCameraInit;

  /// No description provided for @errorCameraCapture.
  ///
  /// In fr, this message translates to:
  /// **'La capture a échoué. Réessayez.'**
  String get errorCameraCapture;

  /// No description provided for @errorImageDecode.
  ///
  /// In fr, this message translates to:
  /// **'Cette image est illisible ou endommagée.'**
  String get errorImageDecode;

  /// No description provided for @errorImageUnsupported.
  ///
  /// In fr, this message translates to:
  /// **'Ce format d\'image n\'est pas pris en charge.'**
  String get errorImageUnsupported;

  /// No description provided for @errorImageTooLarge.
  ///
  /// In fr, this message translates to:
  /// **'Cette image est trop volumineuse pour être traitée.'**
  String get errorImageTooLarge;

  /// No description provided for @errorImageProcessing.
  ///
  /// In fr, this message translates to:
  /// **'Le traitement de l\'image a échoué.'**
  String get errorImageProcessing;

  /// No description provided for @errorPdfPasswordRequired.
  ///
  /// In fr, this message translates to:
  /// **'Ce PDF est protégé par mot de passe.'**
  String get errorPdfPasswordRequired;

  /// No description provided for @errorPdfWrongPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe incorrect.'**
  String get errorPdfWrongPassword;

  /// No description provided for @errorPdfCorrupted.
  ///
  /// In fr, this message translates to:
  /// **'Ce PDF est endommagé et ne peut pas être ouvert.'**
  String get errorPdfCorrupted;

  /// No description provided for @errorPdfUnsupported.
  ///
  /// In fr, this message translates to:
  /// **'Ce PDF utilise une fonctionnalité non prise en charge.'**
  String get errorPdfUnsupported;

  /// No description provided for @errorPdfEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Ce document ne contient aucune page.'**
  String get errorPdfEmpty;

  /// No description provided for @errorPdfInvalidRange.
  ///
  /// In fr, this message translates to:
  /// **'La sélection de pages n\'est pas valide.'**
  String get errorPdfInvalidRange;

  /// No description provided for @errorPdfEngineUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Le moteur PDF n\'est pas disponible sur cet appareil.'**
  String get errorPdfEngineUnavailable;

  /// No description provided for @errorPdfOperationFailed.
  ///
  /// In fr, this message translates to:
  /// **'L\'opération sur le PDF a échoué.'**
  String get errorPdfOperationFailed;

  /// No description provided for @errorOcrNoText.
  ///
  /// In fr, this message translates to:
  /// **'Aucun texte n\'a été détecté.'**
  String get errorOcrNoText;

  /// No description provided for @errorOcrEngineUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'La reconnaissance de texte n\'est pas disponible sur cet appareil.'**
  String get errorOcrEngineUnavailable;

  /// No description provided for @errorOcrModelUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Le modèle de reconnaissance n\'est pas encore disponible. Connectez-vous à Internet une première fois puis réessayez.'**
  String get errorOcrModelUnavailable;

  /// No description provided for @errorOcrFailed.
  ///
  /// In fr, this message translates to:
  /// **'La reconnaissance de texte a échoué.'**
  String get errorOcrFailed;

  /// No description provided for @errorScanUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Le scanner n\'est pas disponible sur cet appareil.'**
  String get errorScanUnavailable;

  /// No description provided for @errorScanNoDocument.
  ///
  /// In fr, this message translates to:
  /// **'Aucun document détecté.'**
  String get errorScanNoDocument;

  /// No description provided for @errorScanSessionNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Cette session de numérisation n\'existe plus.'**
  String get errorScanSessionNotFound;

  /// No description provided for @errorScanFailed.
  ///
  /// In fr, this message translates to:
  /// **'La numérisation a échoué.'**
  String get errorScanFailed;

  /// No description provided for @errorSecurityWrongPin.
  ///
  /// In fr, this message translates to:
  /// **'Code PIN incorrect.'**
  String get errorSecurityWrongPin;

  /// No description provided for @errorSecurityLockedOut.
  ///
  /// In fr, this message translates to:
  /// **'Trop de tentatives. Réessayez dans {seconds} s.'**
  String errorSecurityLockedOut(int seconds);

  /// No description provided for @errorSecurityPinNotSet.
  ///
  /// In fr, this message translates to:
  /// **'Aucun code PIN n\'est défini.'**
  String get errorSecurityPinNotSet;

  /// No description provided for @errorSecurityBiometricUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'La biométrie n\'est pas disponible sur cet appareil.'**
  String get errorSecurityBiometricUnavailable;

  /// No description provided for @errorSecurityBiometricNotEnrolled.
  ///
  /// In fr, this message translates to:
  /// **'Aucune empreinte ni visage n\'est enregistré sur cet appareil.'**
  String get errorSecurityBiometricNotEnrolled;

  /// No description provided for @errorSecurityBiometricFailed.
  ///
  /// In fr, this message translates to:
  /// **'L\'authentification biométrique a échoué.'**
  String get errorSecurityBiometricFailed;

  /// No description provided for @errorSecurityKeyUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'La clé de chiffrement est indisponible. Le coffre-fort ne peut pas être ouvert.'**
  String get errorSecurityKeyUnavailable;

  /// No description provided for @errorSecurityDecryption.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de déchiffrer ce fichier.'**
  String get errorSecurityDecryption;

  /// No description provided for @errorSecurityEncryption.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de chiffrer ce fichier.'**
  String get errorSecurityEncryption;

  /// No description provided for @errorNetworkOffline.
  ///
  /// In fr, this message translates to:
  /// **'Pas de connexion Internet.'**
  String get errorNetworkOffline;

  /// No description provided for @errorNetworkTimeout.
  ///
  /// In fr, this message translates to:
  /// **'Le serveur met trop de temps à répondre.'**
  String get errorNetworkTimeout;

  /// No description provided for @errorNetworkServer.
  ///
  /// In fr, this message translates to:
  /// **'Le service est momentanément indisponible.'**
  String get errorNetworkServer;

  /// No description provided for @errorNetworkUnauthorized.
  ///
  /// In fr, this message translates to:
  /// **'Accès refusé par le service.'**
  String get errorNetworkUnauthorized;

  /// No description provided for @errorNetworkQuota.
  ///
  /// In fr, this message translates to:
  /// **'Votre quota est atteint pour cette période.'**
  String get errorNetworkQuota;

  /// No description provided for @errorNetworkRateLimited.
  ///
  /// In fr, this message translates to:
  /// **'Trop de requêtes. Patientez un instant.'**
  String get errorNetworkRateLimited;

  /// No description provided for @errorNetworkNotConfigured.
  ///
  /// In fr, this message translates to:
  /// **'Ce service n\'est pas configuré.'**
  String get errorNetworkNotConfigured;

  /// No description provided for @errorNetworkInvalidResponse.
  ///
  /// In fr, this message translates to:
  /// **'Réponse inattendue du service.'**
  String get errorNetworkInvalidResponse;

  /// No description provided for @errorBillingStoreUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Google Play n\'est pas disponible. Vérifiez votre connexion et votre compte.'**
  String get errorBillingStoreUnavailable;

  /// No description provided for @errorBillingProductNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Cette offre n\'est pas disponible pour le moment.'**
  String get errorBillingProductNotFound;

  /// No description provided for @errorBillingPending.
  ///
  /// In fr, this message translates to:
  /// **'Votre achat est en attente de validation.'**
  String get errorBillingPending;

  /// No description provided for @errorBillingAlreadyOwned.
  ///
  /// In fr, this message translates to:
  /// **'Vous possédez déjà cette offre.'**
  String get errorBillingAlreadyOwned;

  /// No description provided for @errorBillingVerificationFailed.
  ///
  /// In fr, this message translates to:
  /// **'L\'achat n\'a pas pu être vérifié.'**
  String get errorBillingVerificationFailed;

  /// No description provided for @errorBillingPurchaseFailed.
  ///
  /// In fr, this message translates to:
  /// **'L\'achat n\'a pas abouti.'**
  String get errorBillingPurchaseFailed;

  /// No description provided for @errorAdNotConfigured.
  ///
  /// In fr, this message translates to:
  /// **'Les publicités ne sont pas configurées.'**
  String get errorAdNotConfigured;

  /// No description provided for @errorAdLoadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Aucune publicité disponible pour le moment.'**
  String get errorAdLoadFailed;

  /// No description provided for @errorAdShowFailed.
  ///
  /// In fr, this message translates to:
  /// **'La publicité n\'a pas pu être affichée.'**
  String get errorAdShowFailed;

  /// No description provided for @errorAdConsentRequired.
  ///
  /// In fr, this message translates to:
  /// **'Votre choix de confidentialité est requis.'**
  String get errorAdConsentRequired;

  /// No description provided for @errorValidation.
  ///
  /// In fr, this message translates to:
  /// **'La valeur saisie n\'est pas valide.'**
  String get errorValidation;

  /// No description provided for @errorCancelled.
  ///
  /// In fr, this message translates to:
  /// **'Opération annulée.'**
  String get errorCancelled;

  /// No description provided for @errorUnexpected.
  ///
  /// In fr, this message translates to:
  /// **'Une erreur inattendue s\'est produite.'**
  String get errorUnexpected;
}

class _CoreLocalizationsDelegate
    extends LocalizationsDelegate<CoreLocalizations> {
  const _CoreLocalizationsDelegate();

  @override
  Future<CoreLocalizations> load(Locale locale) {
    return SynchronousFuture<CoreLocalizations>(
      lookupCoreLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_CoreLocalizationsDelegate old) => false;
}

CoreLocalizations lookupCoreLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return CoreLocalizationsEn();
    case 'fr':
      return CoreLocalizationsFr();
  }

  throw FlutterError(
    'CoreLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
