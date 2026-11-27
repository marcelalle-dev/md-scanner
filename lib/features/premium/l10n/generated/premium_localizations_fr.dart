// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'premium_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class PremiumLocalizationsFr extends PremiumLocalizations {
  PremiumLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get premiumTitle => 'MD SCANNER Premium';

  @override
  String get premiumTagline =>
      'Sans publicité, avec toutes les fonctions avancées.';

  @override
  String get premiumActive => 'Votre Premium est actif';

  @override
  String get premiumActiveLifetime => 'Achat à vie';

  @override
  String premiumActiveUntil(String date) {
    return 'Valable jusqu\'au $date';
  }

  @override
  String get premiumOfflineGrace =>
      'Vérification en attente : reconnectez-vous à Internet pour confirmer votre abonnement.';

  @override
  String get benefitNoAds => 'Aucune publicité';

  @override
  String get benefitDocx => 'Export du texte reconnu en DOCX';

  @override
  String get benefitAi => 'Assistant IA pour vos documents';

  @override
  String get benefitCustom => 'Couleurs personnalisées des QR codes';

  @override
  String get planMonthly => 'Mensuel';

  @override
  String get planYearly => 'Annuel';

  @override
  String get planLifetime => 'À vie';

  @override
  String get planMonthlyNote => 'Abonnement renouvelé chaque mois';

  @override
  String get planYearlyNote => 'Abonnement renouvelé chaque année';

  @override
  String get planLifetimeNote => 'Paiement unique';

  @override
  String get premiumBuy => 'Choisir';

  @override
  String get premiumRestore => 'Restaurer mes achats';

  @override
  String get premiumRestored => 'Achats vérifiés auprès de Google Play';

  @override
  String get premiumManage => 'Gérer mon abonnement';

  @override
  String get premiumLoading => 'Chargement des offres…';

  @override
  String get premiumNoOffers =>
      'Les offres ne sont pas disponibles pour le moment.';

  @override
  String get premiumNoOffersHint =>
      'Les achats nécessitent une version installée depuis Google Play et une connexion Internet.';

  @override
  String get premiumLegal =>
      'Les abonnements se renouvellent automatiquement, au prix affiché, jusqu\'à leur annulation dans Google Play. Le paiement est débité sur votre compte Google.';

  @override
  String get premiumThanks => 'Merci ! Premium est activé.';

  @override
  String get premiumPending =>
      'Achat en attente de validation par Google Play.';

  @override
  String get premiumEntry => 'Premium';

  @override
  String get premiumEntryHint =>
      'Supprimer les publicités et débloquer les fonctions avancées';

  @override
  String get premiumEntryActive => 'Premium actif';

  @override
  String get adsPrivacy => 'Choix de confidentialité publicitaire';
}
