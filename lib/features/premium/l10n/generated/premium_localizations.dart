import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'premium_localizations_en.dart';
import 'premium_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of PremiumLocalizations
/// returned by `PremiumLocalizations.of(context)`.
///
/// Applications need to include `PremiumLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/premium_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: PremiumLocalizations.localizationsDelegates,
///   supportedLocales: PremiumLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the PremiumLocalizations.supportedLocales
/// property.
abstract class PremiumLocalizations {
  PremiumLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static PremiumLocalizations of(BuildContext context) {
    return Localizations.of<PremiumLocalizations>(
      context,
      PremiumLocalizations,
    )!;
  }

  static const LocalizationsDelegate<PremiumLocalizations> delegate =
      _PremiumLocalizationsDelegate();

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

  /// No description provided for @premiumTitle.
  ///
  /// In fr, this message translates to:
  /// **'MD SCANNER Premium'**
  String get premiumTitle;

  /// No description provided for @premiumTagline.
  ///
  /// In fr, this message translates to:
  /// **'Sans publicité, avec toutes les fonctions avancées.'**
  String get premiumTagline;

  /// No description provided for @premiumActive.
  ///
  /// In fr, this message translates to:
  /// **'Votre Premium est actif'**
  String get premiumActive;

  /// No description provided for @premiumActiveLifetime.
  ///
  /// In fr, this message translates to:
  /// **'Achat à vie'**
  String get premiumActiveLifetime;

  /// No description provided for @premiumActiveUntil.
  ///
  /// In fr, this message translates to:
  /// **'Valable jusqu\'au {date}'**
  String premiumActiveUntil(String date);

  /// No description provided for @premiumOfflineGrace.
  ///
  /// In fr, this message translates to:
  /// **'Vérification en attente : reconnectez-vous à Internet pour confirmer votre abonnement.'**
  String get premiumOfflineGrace;

  /// No description provided for @benefitNoAds.
  ///
  /// In fr, this message translates to:
  /// **'Aucune publicité'**
  String get benefitNoAds;

  /// No description provided for @benefitDocx.
  ///
  /// In fr, this message translates to:
  /// **'Export du texte reconnu en DOCX'**
  String get benefitDocx;

  /// No description provided for @benefitAi.
  ///
  /// In fr, this message translates to:
  /// **'Assistant IA pour vos documents'**
  String get benefitAi;

  /// No description provided for @benefitCustom.
  ///
  /// In fr, this message translates to:
  /// **'Couleurs personnalisées des QR codes'**
  String get benefitCustom;

  /// No description provided for @planMonthly.
  ///
  /// In fr, this message translates to:
  /// **'Mensuel'**
  String get planMonthly;

  /// No description provided for @planYearly.
  ///
  /// In fr, this message translates to:
  /// **'Annuel'**
  String get planYearly;

  /// No description provided for @planLifetime.
  ///
  /// In fr, this message translates to:
  /// **'À vie'**
  String get planLifetime;

  /// No description provided for @planMonthlyNote.
  ///
  /// In fr, this message translates to:
  /// **'Abonnement renouvelé chaque mois'**
  String get planMonthlyNote;

  /// No description provided for @planYearlyNote.
  ///
  /// In fr, this message translates to:
  /// **'Abonnement renouvelé chaque année'**
  String get planYearlyNote;

  /// No description provided for @planLifetimeNote.
  ///
  /// In fr, this message translates to:
  /// **'Paiement unique'**
  String get planLifetimeNote;

  /// No description provided for @premiumBuy.
  ///
  /// In fr, this message translates to:
  /// **'Choisir'**
  String get premiumBuy;

  /// No description provided for @premiumRestore.
  ///
  /// In fr, this message translates to:
  /// **'Restaurer mes achats'**
  String get premiumRestore;

  /// No description provided for @premiumRestored.
  ///
  /// In fr, this message translates to:
  /// **'Achats vérifiés auprès de Google Play'**
  String get premiumRestored;

  /// No description provided for @premiumManage.
  ///
  /// In fr, this message translates to:
  /// **'Gérer mon abonnement'**
  String get premiumManage;

  /// No description provided for @premiumLoading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement des offres…'**
  String get premiumLoading;

  /// No description provided for @premiumNoOffers.
  ///
  /// In fr, this message translates to:
  /// **'Les offres ne sont pas disponibles pour le moment.'**
  String get premiumNoOffers;

  /// No description provided for @premiumNoOffersHint.
  ///
  /// In fr, this message translates to:
  /// **'Les achats nécessitent une version installée depuis Google Play et une connexion Internet.'**
  String get premiumNoOffersHint;

  /// No description provided for @premiumLegal.
  ///
  /// In fr, this message translates to:
  /// **'Les abonnements se renouvellent automatiquement, au prix affiché, jusqu\'à leur annulation dans Google Play. Le paiement est débité sur votre compte Google.'**
  String get premiumLegal;

  /// No description provided for @premiumThanks.
  ///
  /// In fr, this message translates to:
  /// **'Merci ! Premium est activé.'**
  String get premiumThanks;

  /// No description provided for @premiumPending.
  ///
  /// In fr, this message translates to:
  /// **'Achat en attente de validation par Google Play.'**
  String get premiumPending;

  /// No description provided for @premiumEntry.
  ///
  /// In fr, this message translates to:
  /// **'Premium'**
  String get premiumEntry;

  /// No description provided for @premiumEntryHint.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer les publicités et débloquer les fonctions avancées'**
  String get premiumEntryHint;

  /// No description provided for @premiumEntryActive.
  ///
  /// In fr, this message translates to:
  /// **'Premium actif'**
  String get premiumEntryActive;

  /// No description provided for @adsPrivacy.
  ///
  /// In fr, this message translates to:
  /// **'Choix de confidentialité publicitaire'**
  String get adsPrivacy;
}

class _PremiumLocalizationsDelegate
    extends LocalizationsDelegate<PremiumLocalizations> {
  const _PremiumLocalizationsDelegate();

  @override
  Future<PremiumLocalizations> load(Locale locale) {
    return SynchronousFuture<PremiumLocalizations>(
      lookupPremiumLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_PremiumLocalizationsDelegate old) => false;
}

PremiumLocalizations lookupPremiumLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return PremiumLocalizationsEn();
    case 'fr':
      return PremiumLocalizationsFr();
  }

  throw FlutterError(
    'PremiumLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
