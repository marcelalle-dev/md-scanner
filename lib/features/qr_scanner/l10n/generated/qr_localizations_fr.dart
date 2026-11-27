// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'qr_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class QrLocalizationsFr extends QrLocalizations {
  QrLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get qrScanTitle => 'Scanner un QR code';

  @override
  String get barcodeScanTitle => 'Scanner un code-barres';

  @override
  String get qrScanHint => 'Lire un QR code, Data Matrix, Aztec ou PDF417';

  @override
  String get barcodeScanHint => 'Lire un code EAN, UPC, Code 128 ou Code 39';

  @override
  String get qrHistoryTitle => 'Historique des codes';

  @override
  String get qrHistoryHint => 'Codes lus et codes créés';

  @override
  String get qrGeneratorTitle => 'Créer un QR code';

  @override
  String get qrGeneratorHint => 'Texte, lien, Wi-Fi, contact…';

  @override
  String get barcodeGeneratorTitle => 'Créer un code-barres';

  @override
  String get barcodeGeneratorHint =>
      'EAN, UPC, Code 128, Code 39, Data Matrix…';

  @override
  String get qrTorch => 'Lampe';

  @override
  String get qrImport => 'Lire depuis une image';

  @override
  String get qrNoCodeInImage => 'Aucun code lisible dans cette image.';

  @override
  String get qrPermissionDenied =>
      'L\'accès à l\'appareil photo est nécessaire pour lire un code.';

  @override
  String get qrCameraError => 'L\'appareil photo n\'a pas pu démarrer.';

  @override
  String get qrZoom => 'Zoom';

  @override
  String get qrResultTitle => 'Code lu';

  @override
  String qrFormat(String format) {
    return 'Format : $format';
  }

  @override
  String get qrOpen => 'Ouvrir';

  @override
  String get qrOpenConfirmTitle => 'Ouvrir ce lien ?';

  @override
  String get qrOpenFailed => 'Aucune application ne peut ouvrir ce contenu.';

  @override
  String get qrBlocked =>
      'Ce type de lien est bloqué par sécurité et ne peut pas être ouvert.';

  @override
  String get qrSafe =>
      'Aucun signe suspect détecté. Vérifiez tout de même l\'adresse.';

  @override
  String get qrCaution => 'Prudence :';

  @override
  String get qrDangerous => 'Lien potentiellement dangereux :';

  @override
  String get riskNoTls => 'connexion non chiffrée (http)';

  @override
  String get riskIpHost => 'adresse IP à la place d\'un nom de site';

  @override
  String get riskPunycode => 'nom de site avec caractères trompeurs';

  @override
  String get riskUserInfo => 'identifiant caché avant le « @ »';

  @override
  String get riskManySubdomains => 'trop de sous-domaines';

  @override
  String get riskShortener => 'lien raccourci masquant la destination';

  @override
  String get riskPort => 'port inhabituel';

  @override
  String get riskLong => 'adresse anormalement longue';

  @override
  String get riskExecutable => 'téléchargement d\'un programme';

  @override
  String get typeUrl => 'Lien';

  @override
  String get typeWifi => 'Réseau Wi-Fi';

  @override
  String get typeEmail => 'E-mail';

  @override
  String get typePhone => 'Téléphone';

  @override
  String get typeSms => 'SMS';

  @override
  String get typeGeo => 'Position';

  @override
  String get typeContact => 'Contact';

  @override
  String get typeEvent => 'Événement';

  @override
  String get typeProduct => 'Code produit';

  @override
  String get typeText => 'Texte';

  @override
  String wifiNetwork(String name) {
    return 'Réseau : $name';
  }

  @override
  String wifiPassword(String password) {
    return 'Mot de passe : $password';
  }

  @override
  String get wifiCopyPassword => 'Copier le mot de passe';

  @override
  String get productSearch => 'Rechercher ce produit sur le Web';

  @override
  String get historyEmpty => 'Aucun code pour l\'instant';

  @override
  String get historyClear => 'Effacer l\'historique';

  @override
  String get historyClearConfirm => 'Effacer tout l\'historique ?';

  @override
  String get historyScanned => 'Lus';

  @override
  String get historyGenerated => 'Créés';

  @override
  String get historyAll => 'Tous';

  @override
  String get genFormat => 'Format';

  @override
  String get genContent => 'Contenu du code';

  @override
  String genInvalid(String format) {
    return 'Ce contenu n\'est pas valide pour le format $format.';
  }

  @override
  String get genEmpty => 'Saisissez le contenu du code.';

  @override
  String get genColor => 'Couleur';

  @override
  String get genLowContrast =>
      'Contraste faible : ce code risque de ne pas être lisible.';

  @override
  String get genSave => 'Enregistrer en PNG';

  @override
  String get genSaved => 'Image enregistrée dans vos documents';

  @override
  String get genTemplateText => 'Texte';

  @override
  String get genTemplateUrl => 'Lien';

  @override
  String get genTemplateWifi => 'Wi-Fi';

  @override
  String get genTemplateEmail => 'E-mail';

  @override
  String get genTemplatePhone => 'Téléphone';

  @override
  String get genWifiName => 'Nom du réseau';

  @override
  String get genWifiPassword => 'Mot de passe du réseau';
}
