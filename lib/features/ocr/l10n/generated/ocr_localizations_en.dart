// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'ocr_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class OcrLocalizationsEn extends OcrLocalizations {
  OcrLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get ocrTitle => 'Text recognition';

  @override
  String get ocrToolHint => 'Extract the text of an image or a PDF';

  @override
  String get ocrChooseDocument => 'Choose a document';

  @override
  String get ocrImportImage => 'Import an image';

  @override
  String get ocrNoDocument => 'No compatible document';

  @override
  String get ocrNoDocumentHint =>
      'Scan a document or import an image to extract its text.';

  @override
  String get ocrStart => 'Extract text';

  @override
  String get ocrRestart => 'Run recognition again';

  @override
  String get ocrRunning => 'Recognizing text…';

  @override
  String get ocrIntro =>
      'Recognition runs on the device, offline, for Latin-script text (French, English…).';

  @override
  String get ocrTextLabel => 'Extracted text — you can correct it';

  @override
  String get ocrSearch => 'Search in the text';

  @override
  String ocrMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
      zero: 'No match',
    );
    return '$_temp0';
  }

  @override
  String get ocrNextMatch => 'Next match';

  @override
  String get ocrSave => 'Save text';

  @override
  String get ocrSaved => 'Text saved with the document';

  @override
  String get ocrExportTxt => 'Export as TXT';

  @override
  String get ocrExportDocx => 'Export as DOCX';

  @override
  String get ocrExported => 'File created in your documents';

  @override
  String get ocrExtractText => 'Extract text';
}
