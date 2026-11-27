import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'ai_localizations_en.dart';
import 'ai_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AiLocalizations
/// returned by `AiLocalizations.of(context)`.
///
/// Applications need to include `AiLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/ai_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AiLocalizations.localizationsDelegates,
///   supportedLocales: AiLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AiLocalizations.supportedLocales
/// property.
abstract class AiLocalizations {
  AiLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AiLocalizations of(BuildContext context) {
    return Localizations.of<AiLocalizations>(context, AiLocalizations)!;
  }

  static const LocalizationsDelegate<AiLocalizations> delegate =
      _AiLocalizationsDelegate();

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

  /// No description provided for @aiTitle.
  ///
  /// In fr, this message translates to:
  /// **'Assistant documentaire'**
  String get aiTitle;

  /// No description provided for @aiHint.
  ///
  /// In fr, this message translates to:
  /// **'Résumer, interroger, traduire un document'**
  String get aiHint;

  /// No description provided for @aiChooseDocument.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un document'**
  String get aiChooseDocument;

  /// No description provided for @aiNoDocument.
  ///
  /// In fr, this message translates to:
  /// **'Aucun document'**
  String get aiNoDocument;

  /// No description provided for @aiNoDocumentHint.
  ///
  /// In fr, this message translates to:
  /// **'Numérisez ou importez d\'abord un document.'**
  String get aiNoDocumentHint;

  /// No description provided for @aiNeedsText.
  ///
  /// In fr, this message translates to:
  /// **'Ce document n\'a pas encore de texte extrait.'**
  String get aiNeedsText;

  /// No description provided for @aiRunOcr.
  ///
  /// In fr, this message translates to:
  /// **'Extraire le texte'**
  String get aiRunOcr;

  /// No description provided for @aiLocalTitle.
  ///
  /// In fr, this message translates to:
  /// **'Repérage local'**
  String get aiLocalTitle;

  /// No description provided for @aiLocalHint.
  ///
  /// In fr, this message translates to:
  /// **'Dates et montants repérés sur l\'appareil, sans connexion ni IA.'**
  String get aiLocalHint;

  /// No description provided for @aiLocalDates.
  ///
  /// In fr, this message translates to:
  /// **'Dates'**
  String get aiLocalDates;

  /// No description provided for @aiLocalAmounts.
  ///
  /// In fr, this message translates to:
  /// **'Montants'**
  String get aiLocalAmounts;

  /// No description provided for @aiLocalNone.
  ///
  /// In fr, this message translates to:
  /// **'Aucune date ni aucun montant repéré.'**
  String get aiLocalNone;

  /// No description provided for @aiCloudTitle.
  ///
  /// In fr, this message translates to:
  /// **'Assistant IA'**
  String get aiCloudTitle;

  /// No description provided for @aiNotConfigured.
  ///
  /// In fr, this message translates to:
  /// **'L\'assistant IA n\'est pas disponible dans cette version de l\'application.'**
  String get aiNotConfigured;

  /// No description provided for @aiPremiumOnly.
  ///
  /// In fr, this message translates to:
  /// **'L\'assistant IA est une fonction Premium.'**
  String get aiPremiumOnly;

  /// No description provided for @aiConsentTitle.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer le texte à l\'assistant ?'**
  String get aiConsentTitle;

  /// No description provided for @aiConsentMessage.
  ///
  /// In fr, this message translates to:
  /// **'Pour répondre, le texte extrait de ce document est envoyé au serveur de MD SCANNER puis à un fournisseur d\'intelligence artificielle. Il n\'y est pas conservé. Aucun fichier n\'est envoyé. Vous pouvez refuser : le reste de l\'application fonctionne sans cela.'**
  String get aiConsentMessage;

  /// No description provided for @aiConsentAccept.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get aiConsentAccept;

  /// No description provided for @aiTaskSummary.
  ///
  /// In fr, this message translates to:
  /// **'Résumer'**
  String get aiTaskSummary;

  /// No description provided for @aiTaskSections.
  ///
  /// In fr, this message translates to:
  /// **'Résumer par section'**
  String get aiTaskSections;

  /// No description provided for @aiTaskQa.
  ///
  /// In fr, this message translates to:
  /// **'Poser une question'**
  String get aiTaskQa;

  /// No description provided for @aiTaskExtract.
  ///
  /// In fr, this message translates to:
  /// **'Extraire dates, montants, noms'**
  String get aiTaskExtract;

  /// No description provided for @aiTaskTranslate.
  ///
  /// In fr, this message translates to:
  /// **'Traduire'**
  String get aiTaskTranslate;

  /// No description provided for @aiTaskFlashcards.
  ///
  /// In fr, this message translates to:
  /// **'Fiches de révision'**
  String get aiTaskFlashcards;

  /// No description provided for @aiTaskAdmin.
  ///
  /// In fr, this message translates to:
  /// **'Analyser un courrier administratif'**
  String get aiTaskAdmin;

  /// No description provided for @aiQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Votre question'**
  String get aiQuestion;

  /// No description provided for @aiQuestionRequired.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez une question.'**
  String get aiQuestionRequired;

  /// No description provided for @aiTargetLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue de traduction'**
  String get aiTargetLanguage;

  /// No description provided for @aiRunning.
  ///
  /// In fr, this message translates to:
  /// **'L\'assistant travaille…'**
  String get aiRunning;

  /// No description provided for @aiResult.
  ///
  /// In fr, this message translates to:
  /// **'Réponse de l\'assistant'**
  String get aiResult;

  /// No description provided for @aiDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'Réponse générée par une IA : vérifiez les informations importantes.'**
  String get aiDisclaimer;

  /// No description provided for @aiTooLong.
  ///
  /// In fr, this message translates to:
  /// **'Ce document est trop long pour l\'assistant.'**
  String get aiTooLong;

  /// No description provided for @aiQuota.
  ///
  /// In fr, this message translates to:
  /// **'Demandes restantes aujourd\'hui : {count}'**
  String aiQuota(int count);
}

class _AiLocalizationsDelegate extends LocalizationsDelegate<AiLocalizations> {
  const _AiLocalizationsDelegate();

  @override
  Future<AiLocalizations> load(Locale locale) {
    return SynchronousFuture<AiLocalizations>(lookupAiLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AiLocalizationsDelegate old) => false;
}

AiLocalizations lookupAiLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AiLocalizationsEn();
    case 'fr':
      return AiLocalizationsFr();
  }

  throw FlutterError(
    'AiLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
