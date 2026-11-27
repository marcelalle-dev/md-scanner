import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'id_scanner_localizations_en.dart';
import 'id_scanner_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of IdScannerLocalizations
/// returned by `IdScannerLocalizations.of(context)`.
///
/// Applications need to include `IdScannerLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/id_scanner_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: IdScannerLocalizations.localizationsDelegates,
///   supportedLocales: IdScannerLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the IdScannerLocalizations.supportedLocales
/// property.
abstract class IdScannerLocalizations {
  IdScannerLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static IdScannerLocalizations of(BuildContext context) {
    return Localizations.of<IdScannerLocalizations>(
      context,
      IdScannerLocalizations,
    )!;
  }

  static const LocalizationsDelegate<IdScannerLocalizations> delegate =
      _IdScannerLocalizationsDelegate();

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

  /// No description provided for @idTitle.
  ///
  /// In fr, this message translates to:
  /// **'Pièce d\'identité'**
  String get idTitle;

  /// No description provided for @idHint.
  ///
  /// In fr, this message translates to:
  /// **'Numériser recto et verso, repérer les informations'**
  String get idHint;

  /// No description provided for @idFront.
  ///
  /// In fr, this message translates to:
  /// **'Recto'**
  String get idFront;

  /// No description provided for @idBack.
  ///
  /// In fr, this message translates to:
  /// **'Verso (facultatif)'**
  String get idBack;

  /// No description provided for @idCapture.
  ///
  /// In fr, this message translates to:
  /// **'Photographier'**
  String get idCapture;

  /// No description provided for @idImport.
  ///
  /// In fr, this message translates to:
  /// **'Importer'**
  String get idImport;

  /// No description provided for @idRemove.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get idRemove;

  /// No description provided for @idAnalyze.
  ///
  /// In fr, this message translates to:
  /// **'Lire les informations'**
  String get idAnalyze;

  /// No description provided for @idAnalyzing.
  ///
  /// In fr, this message translates to:
  /// **'Lecture du document…'**
  String get idAnalyzing;

  /// No description provided for @idFields.
  ///
  /// In fr, this message translates to:
  /// **'Informations repérées'**
  String get idFields;

  /// No description provided for @idNoFields.
  ///
  /// In fr, this message translates to:
  /// **'Aucune information n\'a pu être repérée automatiquement.'**
  String get idNoFields;

  /// No description provided for @idSurname.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get idSurname;

  /// No description provided for @idGivenNames.
  ///
  /// In fr, this message translates to:
  /// **'Prénoms'**
  String get idGivenNames;

  /// No description provided for @idNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numéro du document'**
  String get idNumber;

  /// No description provided for @idBirth.
  ///
  /// In fr, this message translates to:
  /// **'Date de naissance'**
  String get idBirth;

  /// No description provided for @idExpiry.
  ///
  /// In fr, this message translates to:
  /// **'Date d\'expiration'**
  String get idExpiry;

  /// No description provided for @idNationality.
  ///
  /// In fr, this message translates to:
  /// **'Nationalité'**
  String get idNationality;

  /// No description provided for @idSex.
  ///
  /// In fr, this message translates to:
  /// **'Sexe'**
  String get idSex;

  /// No description provided for @idDates.
  ///
  /// In fr, this message translates to:
  /// **'Autres dates'**
  String get idDates;

  /// No description provided for @idNumbers.
  ///
  /// In fr, this message translates to:
  /// **'Autres numéros'**
  String get idNumbers;

  /// No description provided for @idMrzValid.
  ///
  /// In fr, this message translates to:
  /// **'Zone de lecture automatique lue, clés de contrôle valides.'**
  String get idMrzValid;

  /// No description provided for @idMrzInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Zone de lecture automatique lue, mais une clé de contrôle ne correspond pas : vérifiez les valeurs.'**
  String get idMrzInvalid;

  /// No description provided for @idDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'Ces informations sont lues automatiquement et peuvent contenir des erreurs. MD SCANNER ne vérifie pas l\'authenticité d\'un document.'**
  String get idDisclaimer;

  /// No description provided for @idPrivacy.
  ///
  /// In fr, this message translates to:
  /// **'Rien n\'est conservé tant que vous n\'enregistrez pas. Pour ce type de document, pensez au coffre-fort.'**
  String get idPrivacy;

  /// No description provided for @idSavePdf.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer en PDF'**
  String get idSavePdf;

  /// No description provided for @idSaved.
  ///
  /// In fr, this message translates to:
  /// **'Document enregistré dans vos documents'**
  String get idSaved;

  /// No description provided for @idDefaultName.
  ///
  /// In fr, this message translates to:
  /// **'Pièce d\'identité'**
  String get idDefaultName;
}

class _IdScannerLocalizationsDelegate
    extends LocalizationsDelegate<IdScannerLocalizations> {
  const _IdScannerLocalizationsDelegate();

  @override
  Future<IdScannerLocalizations> load(Locale locale) {
    return SynchronousFuture<IdScannerLocalizations>(
      lookupIdScannerLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_IdScannerLocalizationsDelegate old) => false;
}

IdScannerLocalizations lookupIdScannerLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return IdScannerLocalizationsEn();
    case 'fr':
      return IdScannerLocalizationsFr();
  }

  throw FlutterError(
    'IdScannerLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
