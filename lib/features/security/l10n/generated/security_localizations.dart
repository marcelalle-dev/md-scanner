import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'security_localizations_en.dart';
import 'security_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of SecurityLocalizations
/// returned by `SecurityLocalizations.of(context)`.
///
/// Applications need to include `SecurityLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/security_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: SecurityLocalizations.localizationsDelegates,
///   supportedLocales: SecurityLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the SecurityLocalizations.supportedLocales
/// property.
abstract class SecurityLocalizations {
  SecurityLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static SecurityLocalizations of(BuildContext context) {
    return Localizations.of<SecurityLocalizations>(
      context,
      SecurityLocalizations,
    )!;
  }

  static const LocalizationsDelegate<SecurityLocalizations> delegate =
      _SecurityLocalizationsDelegate();

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

  /// No description provided for @vaultTitle.
  ///
  /// In fr, this message translates to:
  /// **'Coffre-fort'**
  String get vaultTitle;

  /// No description provided for @vaultHint.
  ///
  /// In fr, this message translates to:
  /// **'Documents chiffrés, protégés par code PIN'**
  String get vaultHint;

  /// No description provided for @vaultSetupTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créez votre code PIN'**
  String get vaultSetupTitle;

  /// No description provided for @vaultSetupMessage.
  ///
  /// In fr, this message translates to:
  /// **'Le coffre-fort chiffre vos documents sensibles sur cet appareil. Choisissez un code de 4 à 8 chiffres. Ce code ne peut pas être récupéré : si vous l\'oubliez, les documents du coffre seront perdus.'**
  String get vaultSetupMessage;

  /// No description provided for @vaultPin.
  ///
  /// In fr, this message translates to:
  /// **'Code PIN'**
  String get vaultPin;

  /// No description provided for @vaultPinConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmez le code PIN'**
  String get vaultPinConfirm;

  /// No description provided for @vaultPinInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Le code doit comporter 4 à 8 chiffres.'**
  String get vaultPinInvalid;

  /// No description provided for @vaultPinMismatch.
  ///
  /// In fr, this message translates to:
  /// **'Les deux codes ne correspondent pas.'**
  String get vaultPinMismatch;

  /// No description provided for @vaultCreate.
  ///
  /// In fr, this message translates to:
  /// **'Créer le coffre-fort'**
  String get vaultCreate;

  /// No description provided for @vaultLockedTitle.
  ///
  /// In fr, this message translates to:
  /// **'Coffre-fort verrouillé'**
  String get vaultLockedTitle;

  /// No description provided for @vaultUnlock.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouiller'**
  String get vaultUnlock;

  /// No description provided for @vaultUseBiometrics.
  ///
  /// In fr, this message translates to:
  /// **'Utiliser la biométrie'**
  String get vaultUseBiometrics;

  /// No description provided for @vaultBiometricReason.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouillez votre coffre-fort MD SCANNER'**
  String get vaultBiometricReason;

  /// No description provided for @vaultEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Le coffre-fort est vide'**
  String get vaultEmpty;

  /// No description provided for @vaultEmptyHint.
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez un document : il sera chiffré et retiré de la bibliothèque.'**
  String get vaultEmptyHint;

  /// No description provided for @vaultAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un document'**
  String get vaultAdd;

  /// No description provided for @vaultChoose.
  ///
  /// In fr, this message translates to:
  /// **'Choisir un document à protéger'**
  String get vaultChoose;

  /// No description provided for @vaultNothingToAdd.
  ///
  /// In fr, this message translates to:
  /// **'Aucun document dans la bibliothèque.'**
  String get vaultNothingToAdd;

  /// No description provided for @vaultEncrypting.
  ///
  /// In fr, this message translates to:
  /// **'Chiffrement du document…'**
  String get vaultEncrypting;

  /// No description provided for @vaultDecrypting.
  ///
  /// In fr, this message translates to:
  /// **'Déchiffrement du document…'**
  String get vaultDecrypting;

  /// No description provided for @vaultAdded.
  ///
  /// In fr, this message translates to:
  /// **'Document chiffré et placé dans le coffre-fort'**
  String get vaultAdded;

  /// No description provided for @vaultRemoved.
  ///
  /// In fr, this message translates to:
  /// **'Document replacé dans la bibliothèque'**
  String get vaultRemoved;

  /// No description provided for @vaultOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get vaultOpen;

  /// No description provided for @vaultRemove.
  ///
  /// In fr, this message translates to:
  /// **'Sortir du coffre-fort'**
  String get vaultRemove;

  /// No description provided for @vaultLockNow.
  ///
  /// In fr, this message translates to:
  /// **'Verrouiller'**
  String get vaultLockNow;

  /// No description provided for @vaultBiometricSetting.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouillage biométrique'**
  String get vaultBiometricSetting;

  /// No description provided for @vaultBiometricUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Aucune biométrie n\'est configurée sur cet appareil.'**
  String get vaultBiometricUnavailable;

  /// No description provided for @vaultRemovePin.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le code PIN'**
  String get vaultRemovePin;

  /// No description provided for @vaultRemovePinBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Sortez d\'abord tous les documents du coffre-fort.'**
  String get vaultRemovePinBlocked;

  /// No description provided for @vaultRemovePinConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre code PIN pour le supprimer'**
  String get vaultRemovePinConfirm;

  /// No description provided for @vaultPinRemoved.
  ///
  /// In fr, this message translates to:
  /// **'Code PIN supprimé'**
  String get vaultPinRemoved;

  /// No description provided for @vaultMoveHere.
  ///
  /// In fr, this message translates to:
  /// **'Mettre au coffre-fort'**
  String get vaultMoveHere;

  /// No description provided for @vaultPreviewUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Ce type de fichier ne peut pas être affiché ici. Sortez-le du coffre-fort pour l\'ouvrir.'**
  String get vaultPreviewUnavailable;
}

class _SecurityLocalizationsDelegate
    extends LocalizationsDelegate<SecurityLocalizations> {
  const _SecurityLocalizationsDelegate();

  @override
  Future<SecurityLocalizations> load(Locale locale) {
    return SynchronousFuture<SecurityLocalizations>(
      lookupSecurityLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_SecurityLocalizationsDelegate old) => false;
}

SecurityLocalizations lookupSecurityLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SecurityLocalizationsEn();
    case 'fr':
      return SecurityLocalizationsFr();
  }

  throw FlutterError(
    'SecurityLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
