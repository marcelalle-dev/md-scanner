import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'qr_localizations_en.dart';
import 'qr_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of QrLocalizations
/// returned by `QrLocalizations.of(context)`.
///
/// Applications need to include `QrLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/qr_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: QrLocalizations.localizationsDelegates,
///   supportedLocales: QrLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the QrLocalizations.supportedLocales
/// property.
abstract class QrLocalizations {
  QrLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static QrLocalizations of(BuildContext context) {
    return Localizations.of<QrLocalizations>(context, QrLocalizations)!;
  }

  static const LocalizationsDelegate<QrLocalizations> delegate =
      _QrLocalizationsDelegate();

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

  /// No description provided for @qrScanTitle.
  ///
  /// In fr, this message translates to:
  /// **'Scanner un QR code'**
  String get qrScanTitle;

  /// No description provided for @barcodeScanTitle.
  ///
  /// In fr, this message translates to:
  /// **'Scanner un code-barres'**
  String get barcodeScanTitle;

  /// No description provided for @qrScanHint.
  ///
  /// In fr, this message translates to:
  /// **'Lire un QR code, Data Matrix, Aztec ou PDF417'**
  String get qrScanHint;

  /// No description provided for @barcodeScanHint.
  ///
  /// In fr, this message translates to:
  /// **'Lire un code EAN, UPC, Code 128 ou Code 39'**
  String get barcodeScanHint;

  /// No description provided for @qrHistoryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique des codes'**
  String get qrHistoryTitle;

  /// No description provided for @qrHistoryHint.
  ///
  /// In fr, this message translates to:
  /// **'Codes lus et codes créés'**
  String get qrHistoryHint;

  /// No description provided for @qrGeneratorTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer un QR code'**
  String get qrGeneratorTitle;

  /// No description provided for @qrGeneratorHint.
  ///
  /// In fr, this message translates to:
  /// **'Texte, lien, Wi-Fi, contact…'**
  String get qrGeneratorHint;

  /// No description provided for @barcodeGeneratorTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer un code-barres'**
  String get barcodeGeneratorTitle;

  /// No description provided for @barcodeGeneratorHint.
  ///
  /// In fr, this message translates to:
  /// **'EAN, UPC, Code 128, Code 39, Data Matrix…'**
  String get barcodeGeneratorHint;

  /// No description provided for @qrTorch.
  ///
  /// In fr, this message translates to:
  /// **'Lampe'**
  String get qrTorch;

  /// No description provided for @qrImport.
  ///
  /// In fr, this message translates to:
  /// **'Lire depuis une image'**
  String get qrImport;

  /// No description provided for @qrNoCodeInImage.
  ///
  /// In fr, this message translates to:
  /// **'Aucun code lisible dans cette image.'**
  String get qrNoCodeInImage;

  /// No description provided for @qrPermissionDenied.
  ///
  /// In fr, this message translates to:
  /// **'L\'accès à l\'appareil photo est nécessaire pour lire un code.'**
  String get qrPermissionDenied;

  /// No description provided for @qrCameraError.
  ///
  /// In fr, this message translates to:
  /// **'L\'appareil photo n\'a pas pu démarrer.'**
  String get qrCameraError;

  /// No description provided for @qrZoom.
  ///
  /// In fr, this message translates to:
  /// **'Zoom'**
  String get qrZoom;

  /// No description provided for @qrResultTitle.
  ///
  /// In fr, this message translates to:
  /// **'Code lu'**
  String get qrResultTitle;

  /// No description provided for @qrFormat.
  ///
  /// In fr, this message translates to:
  /// **'Format : {format}'**
  String qrFormat(String format);

  /// No description provided for @qrOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get qrOpen;

  /// No description provided for @qrOpenConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir ce lien ?'**
  String get qrOpenConfirmTitle;

  /// No description provided for @qrOpenFailed.
  ///
  /// In fr, this message translates to:
  /// **'Aucune application ne peut ouvrir ce contenu.'**
  String get qrOpenFailed;

  /// No description provided for @qrBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Ce type de lien est bloqué par sécurité et ne peut pas être ouvert.'**
  String get qrBlocked;

  /// No description provided for @qrSafe.
  ///
  /// In fr, this message translates to:
  /// **'Aucun signe suspect détecté. Vérifiez tout de même l\'adresse.'**
  String get qrSafe;

  /// No description provided for @qrCaution.
  ///
  /// In fr, this message translates to:
  /// **'Prudence :'**
  String get qrCaution;

  /// No description provided for @qrDangerous.
  ///
  /// In fr, this message translates to:
  /// **'Lien potentiellement dangereux :'**
  String get qrDangerous;

  /// No description provided for @riskNoTls.
  ///
  /// In fr, this message translates to:
  /// **'connexion non chiffrée (http)'**
  String get riskNoTls;

  /// No description provided for @riskIpHost.
  ///
  /// In fr, this message translates to:
  /// **'adresse IP à la place d\'un nom de site'**
  String get riskIpHost;

  /// No description provided for @riskPunycode.
  ///
  /// In fr, this message translates to:
  /// **'nom de site avec caractères trompeurs'**
  String get riskPunycode;

  /// No description provided for @riskUserInfo.
  ///
  /// In fr, this message translates to:
  /// **'identifiant caché avant le « @ »'**
  String get riskUserInfo;

  /// No description provided for @riskManySubdomains.
  ///
  /// In fr, this message translates to:
  /// **'trop de sous-domaines'**
  String get riskManySubdomains;

  /// No description provided for @riskShortener.
  ///
  /// In fr, this message translates to:
  /// **'lien raccourci masquant la destination'**
  String get riskShortener;

  /// No description provided for @riskPort.
  ///
  /// In fr, this message translates to:
  /// **'port inhabituel'**
  String get riskPort;

  /// No description provided for @riskLong.
  ///
  /// In fr, this message translates to:
  /// **'adresse anormalement longue'**
  String get riskLong;

  /// No description provided for @riskExecutable.
  ///
  /// In fr, this message translates to:
  /// **'téléchargement d\'un programme'**
  String get riskExecutable;

  /// No description provided for @typeUrl.
  ///
  /// In fr, this message translates to:
  /// **'Lien'**
  String get typeUrl;

  /// No description provided for @typeWifi.
  ///
  /// In fr, this message translates to:
  /// **'Réseau Wi-Fi'**
  String get typeWifi;

  /// No description provided for @typeEmail.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get typeEmail;

  /// No description provided for @typePhone.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get typePhone;

  /// No description provided for @typeSms.
  ///
  /// In fr, this message translates to:
  /// **'SMS'**
  String get typeSms;

  /// No description provided for @typeGeo.
  ///
  /// In fr, this message translates to:
  /// **'Position'**
  String get typeGeo;

  /// No description provided for @typeContact.
  ///
  /// In fr, this message translates to:
  /// **'Contact'**
  String get typeContact;

  /// No description provided for @typeEvent.
  ///
  /// In fr, this message translates to:
  /// **'Événement'**
  String get typeEvent;

  /// No description provided for @typeProduct.
  ///
  /// In fr, this message translates to:
  /// **'Code produit'**
  String get typeProduct;

  /// No description provided for @typeText.
  ///
  /// In fr, this message translates to:
  /// **'Texte'**
  String get typeText;

  /// No description provided for @wifiNetwork.
  ///
  /// In fr, this message translates to:
  /// **'Réseau : {name}'**
  String wifiNetwork(String name);

  /// No description provided for @wifiPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe : {password}'**
  String wifiPassword(String password);

  /// No description provided for @wifiCopyPassword.
  ///
  /// In fr, this message translates to:
  /// **'Copier le mot de passe'**
  String get wifiCopyPassword;

  /// No description provided for @productSearch.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher ce produit sur le Web'**
  String get productSearch;

  /// No description provided for @historyEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucun code pour l\'instant'**
  String get historyEmpty;

  /// No description provided for @historyClear.
  ///
  /// In fr, this message translates to:
  /// **'Effacer l\'historique'**
  String get historyClear;

  /// No description provided for @historyClearConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Effacer tout l\'historique ?'**
  String get historyClearConfirm;

  /// No description provided for @historyScanned.
  ///
  /// In fr, this message translates to:
  /// **'Lus'**
  String get historyScanned;

  /// No description provided for @historyGenerated.
  ///
  /// In fr, this message translates to:
  /// **'Créés'**
  String get historyGenerated;

  /// No description provided for @historyAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get historyAll;

  /// No description provided for @genFormat.
  ///
  /// In fr, this message translates to:
  /// **'Format'**
  String get genFormat;

  /// No description provided for @genContent.
  ///
  /// In fr, this message translates to:
  /// **'Contenu du code'**
  String get genContent;

  /// No description provided for @genInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Ce contenu n\'est pas valide pour le format {format}.'**
  String genInvalid(String format);

  /// No description provided for @genEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le contenu du code.'**
  String get genEmpty;

  /// No description provided for @genColor.
  ///
  /// In fr, this message translates to:
  /// **'Couleur'**
  String get genColor;

  /// No description provided for @genLowContrast.
  ///
  /// In fr, this message translates to:
  /// **'Contraste faible : ce code risque de ne pas être lisible.'**
  String get genLowContrast;

  /// No description provided for @genSave.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer en PNG'**
  String get genSave;

  /// No description provided for @genSaved.
  ///
  /// In fr, this message translates to:
  /// **'Image enregistrée dans vos documents'**
  String get genSaved;

  /// No description provided for @genTemplateText.
  ///
  /// In fr, this message translates to:
  /// **'Texte'**
  String get genTemplateText;

  /// No description provided for @genTemplateUrl.
  ///
  /// In fr, this message translates to:
  /// **'Lien'**
  String get genTemplateUrl;

  /// No description provided for @genTemplateWifi.
  ///
  /// In fr, this message translates to:
  /// **'Wi-Fi'**
  String get genTemplateWifi;

  /// No description provided for @genTemplateEmail.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get genTemplateEmail;

  /// No description provided for @genTemplatePhone.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get genTemplatePhone;

  /// No description provided for @genWifiName.
  ///
  /// In fr, this message translates to:
  /// **'Nom du réseau'**
  String get genWifiName;

  /// No description provided for @genWifiPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe du réseau'**
  String get genWifiPassword;
}

class _QrLocalizationsDelegate extends LocalizationsDelegate<QrLocalizations> {
  const _QrLocalizationsDelegate();

  @override
  Future<QrLocalizations> load(Locale locale) {
    return SynchronousFuture<QrLocalizations>(lookupQrLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_QrLocalizationsDelegate old) => false;
}

QrLocalizations lookupQrLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return QrLocalizationsEn();
    case 'fr':
      return QrLocalizationsFr();
  }

  throw FlutterError(
    'QrLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
