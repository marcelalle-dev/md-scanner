import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/features/ads/domain/ad_policy.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';

/// Ad unit identifiers, supplied at build time. Without a value, Google's
/// official Android TEST units are used: they only serve test ads.
/// Source: https://developers.google.com/admob/android/test-ads
abstract final class AdsConfig {
  static const String _testBanner = 'ca-app-pub-3940256099942544/9214589741';
  static const String _testInterstitial =
      'ca-app-pub-3940256099942544/1033173712';

  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static const String _banner = String.fromEnvironment('ADMOB_BANNER_UNIT_ID');
  static const String _rewarded = String.fromEnvironment(
    'ADMOB_REWARDED_UNIT_ID',
  );
  static const String _interstitial = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_UNIT_ID',
  );

  static const bool enabled = bool.fromEnvironment(
    'ADS_ENABLED',
    defaultValue: true,
  );

  static String get bannerUnitId => _banner.isEmpty ? _testBanner : _banner;

  static String get interstitialUnitId =>
      _interstitial.isEmpty ? _testInterstitial : _interstitial;

  static String get rewardedUnitId =>
      _rewarded.isEmpty ? _testRewarded : _rewarded;

  static bool get usesTestUnits => _banner.isEmpty || _interstitial.isEmpty;
}

/// Google Mobile Ads behind the consent of the user.
///
/// Nothing is requested before Google's consent flow (UMP) says ads may be
/// requested. Every failure is swallowed: ads never break the app.
class AdsService {
  AdsService({required this._isPremium, this._logger});

  final bool Function() _isPremium;
  final AppLogger? _logger;
  final AdPolicy policy = AdPolicy();

  /// True once consent is settled and the SDK is initialized.
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  /// True when the user must be offered a way to change the consent choice.
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  InterstitialAd? _interstitial;
  bool _started = false;

  bool get _active => AdsConfig.enabled && !_isPremium();

  Future<void> initialize() async {
    if (_started || !_active) return;
    _started = true;
    try {
      await _requestConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      privacyOptionsRequired.value =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      await MobileAds.instance.initialize();
      ready.value = true;
      _preloadInterstitial();
    } on MissingPluginException {
      // No native SDK (tests): ads stay off.
    } on PlatformException catch (error) {
      _logger?.warning('ads.init_failed', {'code': error.code.length});
    }
  }

  Future<void> _requestConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) {
        if (!done.isCompleted) done.complete();
      }),
      (_) {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future.timeout(const Duration(seconds: 30), onTimeout: () {});
  }

  /// Reopens Google's privacy options form (settings entry point).
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((_) {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  void _preloadInterstitial() {
    if (!ready.value || !_active || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: AdsConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  /// Records a completed task and shows an interstitial if the policy allows
  /// it. Call only at a natural break, after the result was shown.
  void taskCompleted() {
    policy.taskCompleted();
    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }
    if (!policy.canShowInterstitial(isPremium: _isPremium())) return;
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) => ad.dispose(),
    );
    policy.interstitialShown();
    ad.show();
  }

  /// Shows a rewarded ad and resolves to true only if the user earned the
  /// reward by watching it. Resolves to false when no ad could be shown.
  Future<bool> showRewarded() {
    if (!ready.value || !_active) return Future.value(false);
    final done = Completer<bool>();
    var earned = false;
    void finish(bool value) {
      if (!done.isCompleted) done.complete(value);
    }

    RewardedAd.load(
      adUnitId: AdsConfig.rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              finish(earned);
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              finish(false);
            },
          );
          ad.show(onUserEarnedReward: (_, _) => earned = true);
        },
        onAdFailedToLoad: (_) => finish(false),
      ),
    );
    return done.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => earned,
    );
  }

  /// Drops loaded ads at once, for example when the user becomes Premium.
  void disposeAds() {
    _interstitial?.dispose();
    _interstitial = null;
  }

  void dispose() {
    disposeAds();
    ready.dispose();
    privacyOptionsRequired.dispose();
  }
}

final adsServiceProvider = Provider<AdsService>((ref) {
  final service = AdsService(
    isPremium: () => ref.read(isPremiumProvider),
    logger: ref.watch(appLoggerProvider),
  );
  ref.listen(isPremiumProvider, (_, premium) {
    if (premium) service.disposeAds();
  });
  ref.onDispose(service.dispose);
  return service;
});
