import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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

  /// No description provided for @navHome.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get navHome;

  /// No description provided for @navScanner.
  ///
  /// In fr, this message translates to:
  /// **'Scanner'**
  String get navScanner;

  /// No description provided for @navTools.
  ///
  /// In fr, this message translates to:
  /// **'Outils'**
  String get navTools;

  /// No description provided for @navDocuments.
  ///
  /// In fr, this message translates to:
  /// **'Documents'**
  String get navDocuments;

  /// No description provided for @navProfile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get navProfile;

  /// No description provided for @homeTagline.
  ///
  /// In fr, this message translates to:
  /// **'Numérisez, organisez, partagez.'**
  String get homeTagline;

  /// No description provided for @homeScan.
  ///
  /// In fr, this message translates to:
  /// **'Numériser'**
  String get homeScan;

  /// No description provided for @homeImport.
  ///
  /// In fr, this message translates to:
  /// **'Importer'**
  String get homeImport;

  /// No description provided for @homePdfTools.
  ///
  /// In fr, this message translates to:
  /// **'Outils'**
  String get homePdfTools;

  /// No description provided for @homeRecent.
  ///
  /// In fr, this message translates to:
  /// **'Documents récents'**
  String get homeRecent;

  /// No description provided for @homeSeeAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout voir'**
  String get homeSeeAll;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun document pour l\'instant'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Numérisez votre premier document : il apparaîtra ici.'**
  String get homeEmptyMessage;

  /// No description provided for @scannerTitle.
  ///
  /// In fr, this message translates to:
  /// **'Scanner'**
  String get scannerTitle;

  /// No description provided for @scannerMode.
  ///
  /// In fr, this message translates to:
  /// **'Type de document'**
  String get scannerMode;

  /// No description provided for @modeDocument.
  ///
  /// In fr, this message translates to:
  /// **'Document'**
  String get modeDocument;

  /// No description provided for @modeReceipt.
  ///
  /// In fr, this message translates to:
  /// **'Reçu'**
  String get modeReceipt;

  /// No description provided for @modeBook.
  ///
  /// In fr, this message translates to:
  /// **'Livre'**
  String get modeBook;

  /// No description provided for @modeWhiteboard.
  ///
  /// In fr, this message translates to:
  /// **'Tableau'**
  String get modeWhiteboard;

  /// No description provided for @modeIdCard.
  ///
  /// In fr, this message translates to:
  /// **'Pièce d\'identité'**
  String get modeIdCard;

  /// No description provided for @scannerStart.
  ///
  /// In fr, this message translates to:
  /// **'Numériser avec l\'appareil photo'**
  String get scannerStart;

  /// No description provided for @scannerImport.
  ///
  /// In fr, this message translates to:
  /// **'Importer depuis la galerie'**
  String get scannerImport;

  /// No description provided for @scannerHint.
  ///
  /// In fr, this message translates to:
  /// **'Avec l\'appareil photo, la détection des bords et le recadrage sont assurés par le scanner de documents de Google. Pour les photos importées, MD SCANNER détecte et redresse lui-même le document.'**
  String get scannerHint;

  /// No description provided for @scannerPreparing.
  ///
  /// In fr, this message translates to:
  /// **'Préparation des pages…'**
  String get scannerPreparing;

  /// No description provided for @reviewTitle.
  ///
  /// In fr, this message translates to:
  /// **'Pages numérisées'**
  String get reviewTitle;

  /// No description provided for @reviewName.
  ///
  /// In fr, this message translates to:
  /// **'Nom du document'**
  String get reviewName;

  /// No description provided for @reviewDefaultName.
  ///
  /// In fr, this message translates to:
  /// **'Numérisation {date}'**
  String reviewDefaultName(String date);

  /// No description provided for @reviewAddCamera.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter avec l\'appareil photo'**
  String get reviewAddCamera;

  /// No description provided for @reviewAddGallery.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter depuis la galerie'**
  String get reviewAddGallery;

  /// No description provided for @reviewExportPdf.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer en PDF'**
  String get reviewExportPdf;

  /// No description provided for @reviewExportImages.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer en images JPG'**
  String get reviewExportImages;

  /// No description provided for @reviewExporting.
  ///
  /// In fr, this message translates to:
  /// **'Création du document…'**
  String get reviewExporting;

  /// No description provided for @reviewPage.
  ///
  /// In fr, this message translates to:
  /// **'Page {number}'**
  String reviewPage(int number);

  /// No description provided for @reviewDeletePage.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la page'**
  String get reviewDeletePage;

  /// No description provided for @reviewDuplicate.
  ///
  /// In fr, this message translates to:
  /// **'Dupliquer la page'**
  String get reviewDuplicate;

  /// No description provided for @reviewRotate.
  ///
  /// In fr, this message translates to:
  /// **'Pivoter'**
  String get reviewRotate;

  /// No description provided for @reviewMoveUp.
  ///
  /// In fr, this message translates to:
  /// **'Monter'**
  String get reviewMoveUp;

  /// No description provided for @reviewMoveDown.
  ///
  /// In fr, this message translates to:
  /// **'Descendre'**
  String get reviewMoveDown;

  /// No description provided for @reviewFilter.
  ///
  /// In fr, this message translates to:
  /// **'Filtre'**
  String get reviewFilter;

  /// No description provided for @reviewCropAuto.
  ///
  /// In fr, this message translates to:
  /// **'Recadrage automatique appliqué'**
  String get reviewCropAuto;

  /// No description provided for @reviewCropNone.
  ///
  /// In fr, this message translates to:
  /// **'Contour non détecté : page conservée entière'**
  String get reviewCropNone;

  /// No description provided for @filterOriginal.
  ///
  /// In fr, this message translates to:
  /// **'Original'**
  String get filterOriginal;

  /// No description provided for @filterEnhanced.
  ///
  /// In fr, this message translates to:
  /// **'Couleur améliorée'**
  String get filterEnhanced;

  /// No description provided for @filterGrayscale.
  ///
  /// In fr, this message translates to:
  /// **'Niveaux de gris'**
  String get filterGrayscale;

  /// No description provided for @filterBlackAndWhite.
  ///
  /// In fr, this message translates to:
  /// **'Noir et blanc'**
  String get filterBlackAndWhite;

  /// No description provided for @filterReadability.
  ///
  /// In fr, this message translates to:
  /// **'Lisibilité'**
  String get filterReadability;

  /// No description provided for @filterNoShadow.
  ///
  /// In fr, this message translates to:
  /// **'Sans ombres'**
  String get filterNoShadow;

  /// No description provided for @reviewDiscardTitle.
  ///
  /// In fr, this message translates to:
  /// **'Abandonner la numérisation ?'**
  String get reviewDiscardTitle;

  /// No description provided for @reviewDiscardMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les pages non enregistrées seront perdues.'**
  String get reviewDiscardMessage;

  /// No description provided for @reviewDiscard.
  ///
  /// In fr, this message translates to:
  /// **'Abandonner'**
  String get reviewDiscard;

  /// No description provided for @reviewImagesSaved.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 image enregistrée} other{{count} images enregistrées}}'**
  String reviewImagesSaved(int count);

  /// No description provided for @documentsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Documents'**
  String get documentsTitle;

  /// No description provided for @documentsSearch.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher par nom'**
  String get documentsSearch;

  /// No description provided for @documentsEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Votre bibliothèque est vide'**
  String get documentsEmptyTitle;

  /// No description provided for @documentsEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les documents numérisés, importés ou créés avec les outils apparaissent ici.'**
  String get documentsEmptyMessage;

  /// No description provided for @documentsNoResult.
  ///
  /// In fr, this message translates to:
  /// **'Aucun document ne correspond'**
  String get documentsNoResult;

  /// No description provided for @documentsSort.
  ///
  /// In fr, this message translates to:
  /// **'Trier'**
  String get documentsSort;

  /// No description provided for @sortNewest.
  ///
  /// In fr, this message translates to:
  /// **'Plus récents d\'abord'**
  String get sortNewest;

  /// No description provided for @sortOldest.
  ///
  /// In fr, this message translates to:
  /// **'Plus anciens d\'abord'**
  String get sortOldest;

  /// No description provided for @sortName.
  ///
  /// In fr, this message translates to:
  /// **'Nom (A à Z)'**
  String get sortName;

  /// No description provided for @sortSize.
  ///
  /// In fr, this message translates to:
  /// **'Taille (plus gros d\'abord)'**
  String get sortSize;

  /// No description provided for @documentsFavoritesOnly.
  ///
  /// In fr, this message translates to:
  /// **'Favoris'**
  String get documentsFavoritesOnly;

  /// No description provided for @documentsTrash.
  ///
  /// In fr, this message translates to:
  /// **'Corbeille'**
  String get documentsTrash;

  /// No description provided for @documentsImport.
  ///
  /// In fr, this message translates to:
  /// **'Importer un fichier'**
  String get documentsImport;

  /// No description provided for @documentsImported.
  ///
  /// In fr, this message translates to:
  /// **'Fichier importé'**
  String get documentsImported;

  /// No description provided for @documentRename.
  ///
  /// In fr, this message translates to:
  /// **'Renommer'**
  String get documentRename;

  /// No description provided for @documentFavorite.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter aux favoris'**
  String get documentFavorite;

  /// No description provided for @documentUnfavorite.
  ///
  /// In fr, this message translates to:
  /// **'Retirer des favoris'**
  String get documentUnfavorite;

  /// No description provided for @documentMoveToTrash.
  ///
  /// In fr, this message translates to:
  /// **'Mettre à la corbeille'**
  String get documentMoveToTrash;

  /// No description provided for @documentMovedToTrash.
  ///
  /// In fr, this message translates to:
  /// **'Document placé dans la corbeille'**
  String get documentMovedToTrash;

  /// No description provided for @documentNameEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Le nom ne peut pas être vide.'**
  String get documentNameEmpty;

  /// No description provided for @documentPreviewUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Aperçu indisponible pour ce type de fichier. Utilisez Partager pour l\'ouvrir dans une autre application.'**
  String get documentPreviewUnavailable;

  /// No description provided for @trashTitle.
  ///
  /// In fr, this message translates to:
  /// **'Corbeille'**
  String get trashTitle;

  /// No description provided for @trashEmpty.
  ///
  /// In fr, this message translates to:
  /// **'La corbeille est vide'**
  String get trashEmpty;

  /// No description provided for @trashRestore.
  ///
  /// In fr, this message translates to:
  /// **'Restaurer'**
  String get trashRestore;

  /// No description provided for @trashDeleteForever.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer définitivement'**
  String get trashDeleteForever;

  /// No description provided for @trashEmptyAll.
  ///
  /// In fr, this message translates to:
  /// **'Vider la corbeille'**
  String get trashEmptyAll;

  /// No description provided for @trashConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer définitivement ?'**
  String get trashConfirmTitle;

  /// No description provided for @trashConfirmMessage.
  ///
  /// In fr, this message translates to:
  /// **'Cette action est irréversible.'**
  String get trashConfirmMessage;

  /// No description provided for @toolsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Outils'**
  String get toolsTitle;

  /// No description provided for @toolsSectionText.
  ///
  /// In fr, this message translates to:
  /// **'Texte'**
  String get toolsSectionText;

  /// No description provided for @toolsSectionCodes.
  ///
  /// In fr, this message translates to:
  /// **'QR codes et codes-barres'**
  String get toolsSectionCodes;

  /// No description provided for @toolsSectionPdf.
  ///
  /// In fr, this message translates to:
  /// **'PDF'**
  String get toolsSectionPdf;

  /// No description provided for @toolsSectionSecurity.
  ///
  /// In fr, this message translates to:
  /// **'Sécurité'**
  String get toolsSectionSecurity;

  /// No description provided for @toolImagesToPdf.
  ///
  /// In fr, this message translates to:
  /// **'Images vers PDF'**
  String get toolImagesToPdf;

  /// No description provided for @toolImagesToPdfHint.
  ///
  /// In fr, this message translates to:
  /// **'Assembler des photos en un PDF'**
  String get toolImagesToPdfHint;

  /// No description provided for @toolMerge.
  ///
  /// In fr, this message translates to:
  /// **'Fusionner des PDF'**
  String get toolMerge;

  /// No description provided for @toolMergeHint.
  ///
  /// In fr, this message translates to:
  /// **'Réunir plusieurs PDF en un seul'**
  String get toolMergeHint;

  /// No description provided for @toolSplit.
  ///
  /// In fr, this message translates to:
  /// **'Extraire des pages'**
  String get toolSplit;

  /// No description provided for @toolSplitHint.
  ///
  /// In fr, this message translates to:
  /// **'Créer un PDF à partir de pages choisies'**
  String get toolSplitHint;

  /// No description provided for @toolCompress.
  ///
  /// In fr, this message translates to:
  /// **'Compresser'**
  String get toolCompress;

  /// No description provided for @toolCompressHint.
  ///
  /// In fr, this message translates to:
  /// **'Réduire la taille d\'un PDF'**
  String get toolCompressHint;

  /// No description provided for @toolRotate.
  ///
  /// In fr, this message translates to:
  /// **'Pivoter les pages'**
  String get toolRotate;

  /// No description provided for @toolRotateHint.
  ///
  /// In fr, this message translates to:
  /// **'Tourner toutes les pages'**
  String get toolRotateHint;

  /// No description provided for @toolProtect.
  ///
  /// In fr, this message translates to:
  /// **'Protéger par mot de passe'**
  String get toolProtect;

  /// No description provided for @toolProtectHint.
  ///
  /// In fr, this message translates to:
  /// **'Chiffrement AES 256 bits'**
  String get toolProtectHint;

  /// No description provided for @toolUnlock.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouiller'**
  String get toolUnlock;

  /// No description provided for @toolUnlockHint.
  ///
  /// In fr, this message translates to:
  /// **'Retirer le mot de passe d\'un PDF dont vous le connaissez'**
  String get toolUnlockHint;

  /// No description provided for @toolWatermark.
  ///
  /// In fr, this message translates to:
  /// **'Filigrane'**
  String get toolWatermark;

  /// No description provided for @toolWatermarkHint.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un texte en transparence'**
  String get toolWatermarkHint;

  /// No description provided for @toolPageNumbers.
  ///
  /// In fr, this message translates to:
  /// **'Numéroter les pages'**
  String get toolPageNumbers;

  /// No description provided for @toolPageNumbersHint.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter « page / total » en bas de page'**
  String get toolPageNumbersHint;

  /// No description provided for @toolPdfToImages.
  ///
  /// In fr, this message translates to:
  /// **'PDF vers images'**
  String get toolPdfToImages;

  /// No description provided for @toolPdfToImagesHint.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer chaque page en JPG'**
  String get toolPdfToImagesHint;

  /// No description provided for @toolAddPdf.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un PDF'**
  String get toolAddPdf;

  /// No description provided for @toolSelectedCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucun PDF sélectionné} =1{1 PDF sélectionné} other{{count} PDF sélectionnés}}'**
  String toolSelectedCount(int count);

  /// No description provided for @toolNeedTwo.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez au moins deux PDF.'**
  String get toolNeedTwo;

  /// No description provided for @toolMergeNow.
  ///
  /// In fr, this message translates to:
  /// **'Fusionner'**
  String get toolMergeNow;

  /// No description provided for @toolRanges.
  ///
  /// In fr, this message translates to:
  /// **'Pages à extraire'**
  String get toolRanges;

  /// No description provided for @toolRangesHint.
  ///
  /// In fr, this message translates to:
  /// **'Exemple : 1-3,5,8-'**
  String get toolRangesHint;

  /// No description provided for @toolPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get toolPassword;

  /// No description provided for @toolPasswordRequired.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez un mot de passe.'**
  String get toolPasswordRequired;

  /// No description provided for @toolPasswordOfPdf.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe du PDF'**
  String get toolPasswordOfPdf;

  /// No description provided for @toolWatermarkText.
  ///
  /// In fr, this message translates to:
  /// **'Texte du filigrane'**
  String get toolWatermarkText;

  /// No description provided for @toolTextRequired.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez un texte.'**
  String get toolTextRequired;

  /// No description provided for @toolCompressionLevel.
  ///
  /// In fr, this message translates to:
  /// **'Niveau de compression'**
  String get toolCompressionLevel;

  /// No description provided for @levelLow.
  ///
  /// In fr, this message translates to:
  /// **'Faible — qualité maximale'**
  String get levelLow;

  /// No description provided for @levelBalanced.
  ///
  /// In fr, this message translates to:
  /// **'Équilibrée'**
  String get levelBalanced;

  /// No description provided for @levelHigh.
  ///
  /// In fr, this message translates to:
  /// **'Élevée — fichier le plus léger'**
  String get levelHigh;

  /// No description provided for @toolRotation.
  ///
  /// In fr, this message translates to:
  /// **'Rotation'**
  String get toolRotation;

  /// No description provided for @rotateRight.
  ///
  /// In fr, this message translates to:
  /// **'90° vers la droite'**
  String get rotateRight;

  /// No description provided for @rotateHalf.
  ///
  /// In fr, this message translates to:
  /// **'180°'**
  String get rotateHalf;

  /// No description provided for @rotateLeft.
  ///
  /// In fr, this message translates to:
  /// **'90° vers la gauche'**
  String get rotateLeft;

  /// No description provided for @toolRunning.
  ///
  /// In fr, this message translates to:
  /// **'Traitement du PDF…'**
  String get toolRunning;

  /// No description provided for @toolCompressionResult.
  ///
  /// In fr, this message translates to:
  /// **'Taille réduite : {before} → {after}'**
  String toolCompressionResult(String before, String after);

  /// No description provided for @toolCompressionNone.
  ///
  /// In fr, this message translates to:
  /// **'Ce PDF est déjà optimisé : aucune réduction obtenue ({size}).'**
  String toolCompressionNone(String size);

  /// No description provided for @toolOpenResult.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get toolOpenResult;

  /// No description provided for @profileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get profileTitle;

  /// No description provided for @profileAppearance.
  ///
  /// In fr, this message translates to:
  /// **'Apparence'**
  String get profileAppearance;

  /// No description provided for @themeSystem.
  ///
  /// In fr, this message translates to:
  /// **'Automatique'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In fr, this message translates to:
  /// **'Clair'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In fr, this message translates to:
  /// **'Sombre'**
  String get themeDark;

  /// No description provided for @profileLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get profileLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In fr, this message translates to:
  /// **'Langue du système'**
  String get languageSystem;

  /// No description provided for @profileStorage.
  ///
  /// In fr, this message translates to:
  /// **'Stockage utilisé'**
  String get profileStorage;

  /// No description provided for @profileBackup.
  ///
  /// In fr, this message translates to:
  /// **'Sauvegarde'**
  String get profileBackup;

  /// No description provided for @backupExport.
  ///
  /// In fr, this message translates to:
  /// **'Exporter une sauvegarde'**
  String get backupExport;

  /// No description provided for @backupExportHint.
  ///
  /// In fr, this message translates to:
  /// **'Crée une archive de vos documents à partager ou à enregistrer'**
  String get backupExportHint;

  /// No description provided for @backupRestore.
  ///
  /// In fr, this message translates to:
  /// **'Restaurer une sauvegarde'**
  String get backupRestore;

  /// No description provided for @backupRestoreHint.
  ///
  /// In fr, this message translates to:
  /// **'Ajoute à la bibliothèque les documents d\'une archive'**
  String get backupRestoreHint;

  /// No description provided for @backupExporting.
  ///
  /// In fr, this message translates to:
  /// **'Création de la sauvegarde…'**
  String get backupExporting;

  /// No description provided for @backupRestoring.
  ///
  /// In fr, this message translates to:
  /// **'Restauration en cours…'**
  String get backupRestoring;

  /// No description provided for @backupRestored.
  ///
  /// In fr, this message translates to:
  /// **'Sauvegarde restaurée'**
  String get backupRestored;

  /// No description provided for @profileAbout.
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get profileAbout;

  /// No description provided for @profilePrivacy.
  ///
  /// In fr, this message translates to:
  /// **'Politique de confidentialité'**
  String get profilePrivacy;

  /// No description provided for @profileHelp.
  ///
  /// In fr, this message translates to:
  /// **'Aide et assistance'**
  String get profileHelp;

  /// No description provided for @profileLicenses.
  ///
  /// In fr, this message translates to:
  /// **'Licences open source'**
  String get profileLicenses;

  /// No description provided for @profileVersion.
  ///
  /// In fr, this message translates to:
  /// **'Version {version}'**
  String profileVersion(String version);

  /// No description provided for @profilePublisher.
  ///
  /// In fr, this message translates to:
  /// **'Édité par MarcelAlle.Dev'**
  String get profilePublisher;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
