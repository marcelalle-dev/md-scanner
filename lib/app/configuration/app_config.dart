/// Build-time configuration, supplied with `--dart-define=KEY=value`
/// (or `--dart-define-from-file=config/prod.json`).
///
/// Nothing here is a secret: every value ends up readable in the APK. API keys
/// and credentials live on the backend only (see docs/api.md).
abstract final class AppConfig {
  /// Base URL of the MD SCANNER backend that proxies the AI provider.
  /// Empty: the AI assistant is disabled and the app works without it.
  static const String aiBackendUrl = String.fromEnvironment('AI_BACKEND_URL');

  /// Endpoint that validates Google Play purchases with the Play Developer
  /// API. Empty: purchases are only checked against Google Play on the device.
  static const String purchaseVerificationUrl = String.fromEnvironment(
    'PURCHASE_VERIFICATION_URL',
  );

  static bool get isAiConfigured => aiBackendUrl.isNotEmpty;

  static bool get isServerVerificationConfigured =>
      purchaseVerificationUrl.isNotEmpty;

  static const String androidPackageName = 'dev.marcelalle.mdscanner';

  static const String publisherName = 'MarcelAlle.Dev';

  static const String repositoryUrl =
      'https://github.com/marcelalle-dev/md-scanner';

  static const String supportUrl = '$repositoryUrl/issues';

  static const String privacyPolicyUrl =
      '$repositoryUrl/blob/main/docs/privacy.md';

  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidPackageName';

  /// Google Play page where the user manages or cancels a subscription.
  static String manageSubscriptionUrl(String productId) =>
      'https://play.google.com/store/account/subscriptions'
      '?sku=$productId&package=$androidPackageName';
}
