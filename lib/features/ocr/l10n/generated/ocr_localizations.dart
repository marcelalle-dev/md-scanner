import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'ocr_localizations_en.dart';
import 'ocr_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of OcrLocalizations
/// returned by `OcrLocalizations.of(context)`.
///
/// Applications need to include `OcrLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/ocr_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: OcrLocalizations.localizationsDelegates,
///   supportedLocales: OcrLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the OcrLocalizations.supportedLocales
/// property.
abstract class OcrLocalizations {
  OcrLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static OcrLocalizations of(BuildContext context) {
    return Localizations.of<OcrLocalizations>(context, OcrLocalizations)!;
  }

  static const LocalizationsDelegate<OcrLocalizations> delegate =
      _OcrLocalizationsDelegate();

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

  /// No description provided for @ocrTitle.
  ///
  /// In fr, this message translates to:
  /// **'Reconnaissance de texte'**
  String get ocrTitle;

  /// No description provided for @ocrToolHint.
  ///
  /// In fr, this message translates to:
  /// **'Extraire le texte d\'une image ou d\'un PDF'**
  String get ocrToolHint;

  /// No description provided for @ocrChooseDocument.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un document'**
  String get ocrChooseDocument;

  /// No description provided for @ocrImportImage.
  ///
  /// In fr, this message translates to:
  /// **'Importer une image'**
  String get ocrImportImage;

  /// No description provided for @ocrNoDocument.
  ///
  /// In fr, this message translates to:
  /// **'Aucun document compatible'**
  String get ocrNoDocument;

  /// No description provided for @ocrNoDocumentHint.
  ///
  /// In fr, this message translates to:
  /// **'Numérisez un document ou importez une image pour en extraire le texte.'**
  String get ocrNoDocumentHint;

  /// No description provided for @ocrStart.
  ///
  /// In fr, this message translates to:
  /// **'Extraire le texte'**
  String get ocrStart;

  /// No description provided for @ocrRestart.
  ///
  /// In fr, this message translates to:
  /// **'Relancer la reconnaissance'**
  String get ocrRestart;

  /// No description provided for @ocrRunning.
  ///
  /// In fr, this message translates to:
  /// **'Reconnaissance du texte…'**
  String get ocrRunning;

  /// No description provided for @ocrIntro.
  ///
  /// In fr, this message translates to:
  /// **'La reconnaissance fonctionne sur l\'appareil, sans connexion, pour les textes en alphabet latin (français, anglais…).'**
  String get ocrIntro;

  /// No description provided for @ocrTextLabel.
  ///
  /// In fr, this message translates to:
  /// **'Texte extrait — vous pouvez le corriger'**
  String get ocrTextLabel;

  /// No description provided for @ocrSearch.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher dans le texte'**
  String get ocrSearch;

  /// No description provided for @ocrMatches.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucune occurrence} =1{1 occurrence} other{{count} occurrences}}'**
  String ocrMatches(int count);

  /// No description provided for @ocrNextMatch.
  ///
  /// In fr, this message translates to:
  /// **'Occurrence suivante'**
  String get ocrNextMatch;

  /// No description provided for @ocrSave.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer le texte'**
  String get ocrSave;

  /// No description provided for @ocrSaved.
  ///
  /// In fr, this message translates to:
  /// **'Texte enregistré avec le document'**
  String get ocrSaved;

  /// No description provided for @ocrExportTxt.
  ///
  /// In fr, this message translates to:
  /// **'Exporter en TXT'**
  String get ocrExportTxt;

  /// No description provided for @ocrExportDocx.
  ///
  /// In fr, this message translates to:
  /// **'Exporter en DOCX'**
  String get ocrExportDocx;

  /// No description provided for @ocrExported.
  ///
  /// In fr, this message translates to:
  /// **'Fichier créé dans vos documents'**
  String get ocrExported;

  /// No description provided for @ocrExtractText.
  ///
  /// In fr, this message translates to:
  /// **'Extraire le texte'**
  String get ocrExtractText;
}

class _OcrLocalizationsDelegate
    extends LocalizationsDelegate<OcrLocalizations> {
  const _OcrLocalizationsDelegate();

  @override
  Future<OcrLocalizations> load(Locale locale) {
    return SynchronousFuture<OcrLocalizations>(lookupOcrLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_OcrLocalizationsDelegate old) => false;
}

OcrLocalizations lookupOcrLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return OcrLocalizationsEn();
    case 'fr':
      return OcrLocalizationsFr();
  }

  throw FlutterError(
    'OcrLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
