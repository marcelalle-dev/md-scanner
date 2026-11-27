// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'ocr_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class OcrLocalizationsFr extends OcrLocalizations {
  OcrLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get ocrTitle => 'Reconnaissance de texte';

  @override
  String get ocrToolHint => 'Extraire le texte d\'une image ou d\'un PDF';

  @override
  String get ocrChooseDocument => 'Choisissez un document';

  @override
  String get ocrImportImage => 'Importer une image';

  @override
  String get ocrNoDocument => 'Aucun document compatible';

  @override
  String get ocrNoDocumentHint =>
      'Numérisez un document ou importez une image pour en extraire le texte.';

  @override
  String get ocrStart => 'Extraire le texte';

  @override
  String get ocrRestart => 'Relancer la reconnaissance';

  @override
  String get ocrRunning => 'Reconnaissance du texte…';

  @override
  String get ocrIntro =>
      'La reconnaissance fonctionne sur l\'appareil, sans connexion, pour les textes en alphabet latin (français, anglais…).';

  @override
  String get ocrTextLabel => 'Texte extrait — vous pouvez le corriger';

  @override
  String get ocrSearch => 'Rechercher dans le texte';

  @override
  String ocrMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count occurrences',
      one: '1 occurrence',
      zero: 'Aucune occurrence',
    );
    return '$_temp0';
  }

  @override
  String get ocrNextMatch => 'Occurrence suivante';

  @override
  String get ocrSave => 'Enregistrer le texte';

  @override
  String get ocrSaved => 'Texte enregistré avec le document';

  @override
  String get ocrExportTxt => 'Exporter en TXT';

  @override
  String get ocrExportDocx => 'Exporter en DOCX';

  @override
  String get ocrExported => 'Fichier créé dans vos documents';

  @override
  String get ocrExtractText => 'Extraire le texte';
}
