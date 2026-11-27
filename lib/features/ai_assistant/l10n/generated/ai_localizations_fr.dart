// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'ai_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AiLocalizationsFr extends AiLocalizations {
  AiLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get aiTitle => 'Assistant documentaire';

  @override
  String get aiHint => 'Résumer, interroger, traduire un document';

  @override
  String get aiChooseDocument => 'Choisissez un document';

  @override
  String get aiNoDocument => 'Aucun document';

  @override
  String get aiNoDocumentHint => 'Numérisez ou importez d\'abord un document.';

  @override
  String get aiNeedsText => 'Ce document n\'a pas encore de texte extrait.';

  @override
  String get aiRunOcr => 'Extraire le texte';

  @override
  String get aiLocalTitle => 'Repérage local';

  @override
  String get aiLocalHint =>
      'Dates et montants repérés sur l\'appareil, sans connexion ni IA.';

  @override
  String get aiLocalDates => 'Dates';

  @override
  String get aiLocalAmounts => 'Montants';

  @override
  String get aiLocalNone => 'Aucune date ni aucun montant repéré.';

  @override
  String get aiCloudTitle => 'Assistant IA';

  @override
  String get aiNotConfigured =>
      'L\'assistant IA n\'est pas disponible dans cette version de l\'application.';

  @override
  String get aiPremiumOnly => 'L\'assistant IA est une fonction Premium.';

  @override
  String get aiConsentTitle => 'Envoyer le texte à l\'assistant ?';

  @override
  String get aiConsentMessage =>
      'Pour répondre, le texte extrait de ce document est envoyé au serveur de MD SCANNER puis à un fournisseur d\'intelligence artificielle. Il n\'y est pas conservé. Aucun fichier n\'est envoyé. Vous pouvez refuser : le reste de l\'application fonctionne sans cela.';

  @override
  String get aiConsentAccept => 'Envoyer';

  @override
  String get aiTaskSummary => 'Résumer';

  @override
  String get aiTaskSections => 'Résumer par section';

  @override
  String get aiTaskQa => 'Poser une question';

  @override
  String get aiTaskExtract => 'Extraire dates, montants, noms';

  @override
  String get aiTaskTranslate => 'Traduire';

  @override
  String get aiTaskFlashcards => 'Fiches de révision';

  @override
  String get aiTaskAdmin => 'Analyser un courrier administratif';

  @override
  String get aiQuestion => 'Votre question';

  @override
  String get aiQuestionRequired => 'Saisissez une question.';

  @override
  String get aiTargetLanguage => 'Langue de traduction';

  @override
  String get aiRunning => 'L\'assistant travaille…';

  @override
  String get aiResult => 'Réponse de l\'assistant';

  @override
  String get aiDisclaimer =>
      'Réponse générée par une IA : vérifiez les informations importantes.';

  @override
  String get aiTooLong => 'Ce document est trop long pour l\'assistant.';

  @override
  String aiQuota(int count) {
    return 'Demandes restantes aujourd\'hui : $count';
  }
}
