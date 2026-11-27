import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:md_scanner/features/ads/data/ads_service.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';

/// Discreet adaptive banner. It occupies its own slot in the layout (it never
/// covers content) and renders nothing for Premium users, before consent, or
/// while no ad is loaded.
class AdBannerSlot extends ConsumerStatefulWidget {
  const AdBannerSlot({super.key});

  @override
  ConsumerState<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends ConsumerState<AdBannerSlot> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _loading = false;

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  void _drop() {
    _banner?.dispose();
    _banner = null;
    _loaded = false;
  }

  Future<void> _load(int width) async {
    if (_loading || _banner != null) return;
    _loading = true;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) {
      _loading = false;
      return;
    }
    final banner = BannerAd(
      adUnitId: AdsConfig.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(_drop);
        },
      ),
    );
    _banner = banner;
    _loading = false;
    await banner.load();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(adsServiceProvider);
    final premium = ref.watch(isPremiumProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: service.ready,
      builder: (context, ready, _) {
        if (premium || !ready || !AdsConfig.enabled) {
          if (_banner != null) _drop();
          return const SizedBox.shrink();
        }
        _load(MediaQuery.sizeOf(context).width.truncate());
        final banner = _banner;
        if (banner == null || !_loaded) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: SizedBox(
            width: banner.size.width.toDouble(),
            height: banner.size.height.toDouble(),
            child: AdWidget(ad: banner),
          ),
        );
      },
    );
  }
}
