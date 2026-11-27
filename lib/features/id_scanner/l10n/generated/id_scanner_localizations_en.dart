// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'id_scanner_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class IdScannerLocalizationsEn extends IdScannerLocalizations {
  IdScannerLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get idTitle => 'ID document';

  @override
  String get idHint => 'Scan front and back, spot the information';

  @override
  String get idFront => 'Front';

  @override
  String get idBack => 'Back (optional)';

  @override
  String get idCapture => 'Take a picture';

  @override
  String get idImport => 'Import';

  @override
  String get idRemove => 'Remove';

  @override
  String get idAnalyze => 'Read the information';

  @override
  String get idAnalyzing => 'Reading the document…';

  @override
  String get idFields => 'Information spotted';

  @override
  String get idNoFields => 'No information could be spotted automatically.';

  @override
  String get idSurname => 'Surname';

  @override
  String get idGivenNames => 'Given names';

  @override
  String get idNumber => 'Document number';

  @override
  String get idBirth => 'Date of birth';

  @override
  String get idExpiry => 'Expiry date';

  @override
  String get idNationality => 'Nationality';

  @override
  String get idSex => 'Sex';

  @override
  String get idDates => 'Other dates';

  @override
  String get idNumbers => 'Other numbers';

  @override
  String get idMrzValid => 'Machine-readable zone read, check digits valid.';

  @override
  String get idMrzInvalid =>
      'Machine-readable zone read, but a check digit does not match: verify the values.';

  @override
  String get idDisclaimer =>
      'This information is read automatically and may contain errors. MD SCANNER does not verify the authenticity of a document.';

  @override
  String get idPrivacy =>
      'Nothing is kept until you save. For this kind of document, consider the vault.';

  @override
  String get idSavePdf => 'Save as PDF';

  @override
  String get idSaved => 'Document saved to your documents';

  @override
  String get idDefaultName => 'ID document';
}
