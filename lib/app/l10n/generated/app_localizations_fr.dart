// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get navHome => 'Accueil';

  @override
  String get navScanner => 'Scanner';

  @override
  String get navTools => 'Outils';

  @override
  String get navDocuments => 'Documents';

  @override
  String get navProfile => 'Profil';

  @override
  String get homeTagline => 'Numérisez, organisez, partagez.';

  @override
  String get homeScan => 'Numériser';

  @override
  String get homeImport => 'Importer';

  @override
  String get homePdfTools => 'Outils';

  @override
  String get homeRecent => 'Documents récents';

  @override
  String get homeSeeAll => 'Tout voir';

  @override
  String get homeEmptyTitle => 'Aucun document pour l\'instant';

  @override
  String get homeEmptyMessage =>
      'Numérisez votre premier document : il apparaîtra ici.';

  @override
  String get scannerTitle => 'Scanner';

  @override
  String get scannerMode => 'Type de document';

  @override
  String get modeDocument => 'Document';

  @override
  String get modeReceipt => 'Reçu';

  @override
  String get modeBook => 'Livre';

  @override
  String get modeWhiteboard => 'Tableau';

  @override
  String get modeIdCard => 'Pièce d\'identité';

  @override
  String get scannerStart => 'Numériser avec l\'appareil photo';

  @override
  String get scannerImport => 'Importer depuis la galerie';

  @override
  String get scannerHint =>
      'Avec l\'appareil photo, la détection des bords et le recadrage sont assurés par le scanner de documents de Google. Pour les photos importées, MD SCANNER détecte et redresse lui-même le document.';

  @override
  String get scannerPreparing => 'Préparation des pages…';

  @override
  String get reviewTitle => 'Pages numérisées';

  @override
  String get reviewName => 'Nom du document';

  @override
  String reviewDefaultName(String date) {
    return 'Numérisation $date';
  }

  @override
  String get reviewAddCamera => 'Ajouter avec l\'appareil photo';

  @override
  String get reviewAddGallery => 'Ajouter depuis la galerie';

  @override
  String get reviewExportPdf => 'Enregistrer en PDF';

  @override
  String get reviewExportImages => 'Enregistrer en images JPG';

  @override
  String get reviewExporting => 'Création du document…';

  @override
  String reviewPage(int number) {
    return 'Page $number';
  }

  @override
  String get reviewDeletePage => 'Supprimer la page';

  @override
  String get reviewDuplicate => 'Dupliquer la page';

  @override
  String get reviewRotate => 'Pivoter';

  @override
  String get reviewMoveUp => 'Monter';

  @override
  String get reviewMoveDown => 'Descendre';

  @override
  String get reviewFilter => 'Filtre';

  @override
  String get reviewCropAuto => 'Recadrage automatique appliqué';

  @override
  String get reviewCropNone => 'Contour non détecté : page conservée entière';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterEnhanced => 'Couleur améliorée';

  @override
  String get filterGrayscale => 'Niveaux de gris';

  @override
  String get filterBlackAndWhite => 'Noir et blanc';

  @override
  String get filterReadability => 'Lisibilité';

  @override
  String get filterNoShadow => 'Sans ombres';

  @override
  String get reviewDiscardTitle => 'Abandonner la numérisation ?';

  @override
  String get reviewDiscardMessage =>
      'Les pages non enregistrées seront perdues.';

  @override
  String get reviewDiscard => 'Abandonner';

  @override
  String reviewImagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images enregistrées',
      one: '1 image enregistrée',
    );
    return '$_temp0';
  }

  @override
  String get documentsTitle => 'Documents';

  @override
  String get documentsSearch => 'Rechercher par nom';

  @override
  String get documentsEmptyTitle => 'Votre bibliothèque est vide';

  @override
  String get documentsEmptyMessage =>
      'Les documents numérisés, importés ou créés avec les outils apparaissent ici.';

  @override
  String get documentsNoResult => 'Aucun document ne correspond';

  @override
  String get documentsSort => 'Trier';

  @override
  String get sortNewest => 'Plus récents d\'abord';

  @override
  String get sortOldest => 'Plus anciens d\'abord';

  @override
  String get sortName => 'Nom (A à Z)';

  @override
  String get sortSize => 'Taille (plus gros d\'abord)';

  @override
  String get documentsFavoritesOnly => 'Favoris';

  @override
  String get documentsTrash => 'Corbeille';

  @override
  String get documentsImport => 'Importer un fichier';

  @override
  String get documentsImported => 'Fichier importé';

  @override
  String get documentRename => 'Renommer';

  @override
  String get documentFavorite => 'Ajouter aux favoris';

  @override
  String get documentUnfavorite => 'Retirer des favoris';

  @override
  String get documentMoveToTrash => 'Mettre à la corbeille';

  @override
  String get documentMovedToTrash => 'Document placé dans la corbeille';

  @override
  String get documentNameEmpty => 'Le nom ne peut pas être vide.';

  @override
  String get documentPreviewUnavailable =>
      'Aperçu indisponible pour ce type de fichier. Utilisez Partager pour l\'ouvrir dans une autre application.';

  @override
  String get trashTitle => 'Corbeille';

  @override
  String get trashEmpty => 'La corbeille est vide';

  @override
  String get trashRestore => 'Restaurer';

  @override
  String get trashDeleteForever => 'Supprimer définitivement';

  @override
  String get trashEmptyAll => 'Vider la corbeille';

  @override
  String get trashConfirmTitle => 'Supprimer définitivement ?';

  @override
  String get trashConfirmMessage => 'Cette action est irréversible.';

  @override
  String get toolsTitle => 'Outils';

  @override
  String get toolsSectionText => 'Texte';

  @override
  String get toolsSectionCodes => 'QR codes et codes-barres';

  @override
  String get toolsSectionPdf => 'PDF';

  @override
  String get toolsSectionSecurity => 'Sécurité';

  @override
  String get toolImagesToPdf => 'Images vers PDF';

  @override
  String get toolImagesToPdfHint => 'Assembler des photos en un PDF';

  @override
  String get toolMerge => 'Fusionner des PDF';

  @override
  String get toolMergeHint => 'Réunir plusieurs PDF en un seul';

  @override
  String get toolSplit => 'Extraire des pages';

  @override
  String get toolSplitHint => 'Créer un PDF à partir de pages choisies';

  @override
  String get toolCompress => 'Compresser';

  @override
  String get toolCompressHint => 'Réduire la taille d\'un PDF';

  @override
  String get toolRotate => 'Pivoter les pages';

  @override
  String get toolRotateHint => 'Tourner toutes les pages';

  @override
  String get toolProtect => 'Protéger par mot de passe';

  @override
  String get toolProtectHint => 'Chiffrement AES 256 bits';

  @override
  String get toolUnlock => 'Déverrouiller';

  @override
  String get toolUnlockHint =>
      'Retirer le mot de passe d\'un PDF dont vous le connaissez';

  @override
  String get toolWatermark => 'Filigrane';

  @override
  String get toolWatermarkHint => 'Ajouter un texte en transparence';

  @override
  String get toolPageNumbers => 'Numéroter les pages';

  @override
  String get toolPageNumbersHint => 'Ajouter « page / total » en bas de page';

  @override
  String get toolPdfToImages => 'PDF vers images';

  @override
  String get toolPdfToImagesHint => 'Enregistrer chaque page en JPG';

  @override
  String get toolAddPdf => 'Ajouter un PDF';

  @override
  String toolSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF sélectionnés',
      one: '1 PDF sélectionné',
      zero: 'Aucun PDF sélectionné',
    );
    return '$_temp0';
  }

  @override
  String get toolNeedTwo => 'Sélectionnez au moins deux PDF.';

  @override
  String get toolMergeNow => 'Fusionner';

  @override
  String get toolRanges => 'Pages à extraire';

  @override
  String get toolRangesHint => 'Exemple : 1-3,5,8-';

  @override
  String get toolPassword => 'Mot de passe';

  @override
  String get toolPasswordRequired => 'Saisissez un mot de passe.';

  @override
  String get toolPasswordOfPdf => 'Mot de passe du PDF';

  @override
  String get toolWatermarkText => 'Texte du filigrane';

  @override
  String get toolTextRequired => 'Saisissez un texte.';

  @override
  String get toolCompressionLevel => 'Niveau de compression';

  @override
  String get levelLow => 'Faible — qualité maximale';

  @override
  String get levelBalanced => 'Équilibrée';

  @override
  String get levelHigh => 'Élevée — fichier le plus léger';

  @override
  String get toolRotation => 'Rotation';

  @override
  String get rotateRight => '90° vers la droite';

  @override
  String get rotateHalf => '180°';

  @override
  String get rotateLeft => '90° vers la gauche';

  @override
  String get toolRunning => 'Traitement du PDF…';

  @override
  String toolCompressionResult(String before, String after) {
    return 'Taille réduite : $before → $after';
  }

  @override
  String toolCompressionNone(String size) {
    return 'Ce PDF est déjà optimisé : aucune réduction obtenue ($size).';
  }

  @override
  String get toolOpenResult => 'Ouvrir';

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileAppearance => 'Apparence';

  @override
  String get themeSystem => 'Automatique';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get profileLanguage => 'Langue';

  @override
  String get languageSystem => 'Langue du système';

  @override
  String get profileStorage => 'Stockage utilisé';

  @override
  String get profileBackup => 'Sauvegarde';

  @override
  String get backupExport => 'Exporter une sauvegarde';

  @override
  String get backupExportHint =>
      'Crée une archive de vos documents à partager ou à enregistrer';

  @override
  String get backupRestore => 'Restaurer une sauvegarde';

  @override
  String get backupRestoreHint =>
      'Ajoute à la bibliothèque les documents d\'une archive';

  @override
  String get backupExporting => 'Création de la sauvegarde…';

  @override
  String get backupRestoring => 'Restauration en cours…';

  @override
  String get backupRestored => 'Sauvegarde restaurée';

  @override
  String get profileAbout => 'À propos';

  @override
  String get profilePrivacy => 'Politique de confidentialité';

  @override
  String get profileHelp => 'Aide et assistance';

  @override
  String get profileLicenses => 'Licences open source';

  @override
  String profileVersion(String version) {
    return 'Version $version';
  }

  @override
  String get profilePublisher => 'Édité par MarcelAlle.Dev';
}
