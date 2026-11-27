// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'premium_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class PremiumLocalizationsEn extends PremiumLocalizations {
  PremiumLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get premiumTitle => 'MD SCANNER Premium';

  @override
  String get premiumTagline => 'No ads, with every advanced feature.';

  @override
  String get premiumActive => 'Your Premium is active';

  @override
  String get premiumActiveLifetime => 'Lifetime purchase';

  @override
  String premiumActiveUntil(String date) {
    return 'Valid until $date';
  }

  @override
  String get premiumOfflineGrace =>
      'Verification pending: reconnect to the Internet to confirm your subscription.';

  @override
  String get benefitNoAds => 'No ads';

  @override
  String get benefitDocx => 'Export recognized text as DOCX';

  @override
  String get benefitAi => 'AI assistant for your documents';

  @override
  String get benefitCustom => 'Custom QR code colours';

  @override
  String get planMonthly => 'Monthly';

  @override
  String get planYearly => 'Yearly';

  @override
  String get planLifetime => 'Lifetime';

  @override
  String get planMonthlyNote => 'Subscription renewed every month';

  @override
  String get planYearlyNote => 'Subscription renewed every year';

  @override
  String get planLifetimeNote => 'One-time payment';

  @override
  String get premiumBuy => 'Choose';

  @override
  String get premiumRestore => 'Restore my purchases';

  @override
  String get premiumRestored => 'Purchases checked with Google Play';

  @override
  String get premiumManage => 'Manage my subscription';

  @override
  String get premiumLoading => 'Loading offers…';

  @override
  String get premiumNoOffers => 'Offers are not available right now.';

  @override
  String get premiumNoOffersHint =>
      'Purchases require a version installed from Google Play and an Internet connection.';

  @override
  String get premiumLegal =>
      'Subscriptions renew automatically, at the displayed price, until cancelled in Google Play. Payment is charged to your Google account.';

  @override
  String get premiumThanks => 'Thank you! Premium is active.';

  @override
  String get premiumPending => 'Purchase pending approval by Google Play.';

  @override
  String get premiumEntry => 'Premium';

  @override
  String get premiumEntryHint => 'Remove ads and unlock advanced features';

  @override
  String get premiumEntryActive => 'Premium active';

  @override
  String get adsPrivacy => 'Ad privacy choices';
}
