// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'id_scanner_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class IdScannerLocalizationsFr extends IdScannerLocalizations {
  IdScannerLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get idTitle => 'Pièce d\'identité';

  @override
  String get idHint => 'Numériser recto et verso, repérer les informations';

  @override
  String get idFront => 'Recto';

  @override
  String get idBack => 'Verso (facultatif)';

  @override
  String get idCapture => 'Photographier';

  @override
  String get idImport => 'Importer';

  @override
  String get idRemove => 'Retirer';

  @override
  String get idAnalyze => 'Lire les informations';

  @override
  String get idAnalyzing => 'Lecture du document…';

  @override
  String get idFields => 'Informations repérées';

  @override
  String get idNoFields =>
      'Aucune information n\'a pu être repérée automatiquement.';

  @override
  String get idSurname => 'Nom';

  @override
  String get idGivenNames => 'Prénoms';

  @override
  String get idNumber => 'Numéro du document';

  @override
  String get idBirth => 'Date de naissance';

  @override
  String get idExpiry => 'Date d\'expiration';

  @override
  String get idNationality => 'Nationalité';

  @override
  String get idSex => 'Sexe';

  @override
  String get idDates => 'Autres dates';

  @override
  String get idNumbers => 'Autres numéros';

  @override
  String get idMrzValid =>
      'Zone de lecture automatique lue, clés de contrôle valides.';

  @override
  String get idMrzInvalid =>
      'Zone de lecture automatique lue, mais une clé de contrôle ne correspond pas : vérifiez les valeurs.';

  @override
  String get idDisclaimer =>
      'Ces informations sont lues automatiquement et peuvent contenir des erreurs. MD SCANNER ne vérifie pas l\'authenticité d\'un document.';

  @override
  String get idPrivacy =>
      'Rien n\'est conservé tant que vous n\'enregistrez pas. Pour ce type de document, pensez au coffre-fort.';

  @override
  String get idSavePdf => 'Enregistrer en PDF';

  @override
  String get idSaved => 'Document enregistré dans vos documents';

  @override
  String get idDefaultName => 'Pièce d\'identité';
}
