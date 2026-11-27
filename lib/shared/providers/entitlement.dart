import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PremiumPlan { monthly, yearly, lifetime }

/// Where the current entitlement comes from. Premium is never granted from a
/// bare local flag: it always traces back to a purchase reported by Google
/// Play, ideally confirmed by the verification server.
enum EntitlementSource {
  /// No active purchase known.
  none,

  /// Purchase reported and signed by Google Play on this device.
  playStore,

  /// Purchase confirmed by the verification server (Play Developer API).
  server,

  /// Last verified state, reused for a limited grace period while offline.
  offlineGrace,
}

/// Capabilities reserved for Premium. Core scanning features are never gated.
enum PremiumFeature {
  noAds,
  advancedOcr,
  docxExport,
  batchProcessing,
  advancedPdfTools,
  aiAssistant,
  advancedVault,
  cloudBackup,
  advancedCustomization,
}

class Entitlement extends Equatable {
  const Entitlement({
    required this.isPremium,
    this.plan,
    this.expiresAt,
    this.source = EntitlementSource.none,
    this.isAutoRenewing,
  });

  const Entitlement.free() : this(isPremium: false);

  final bool isPremium;
  final PremiumPlan? plan;

  /// End of the paid period when known. Always null for [PremiumPlan.lifetime].
  final DateTime? expiresAt;
  final EntitlementSource source;

  /// False once a subscription was cancelled but is still within its paid
  /// period; null when unknown or not applicable.
  final bool? isAutoRenewing;

  bool has(PremiumFeature feature) => isPremium;

  @override
  List<Object?> get props => [
    isPremium,
    plan,
    expiresAt,
    source,
    isAutoRenewing,
  ];
}

/// Holds the entitlement for the running session. Starts free; the billing
/// service of the `premium` feature is the only writer.
class EntitlementController extends Notifier<Entitlement> {
  @override
  Entitlement build() => const Entitlement.free();

  void update(Entitlement entitlement) => state = entitlement;
}

final entitlementProvider =
    NotifierProvider<EntitlementController, Entitlement>(
      EntitlementController.new,
    );

final isPremiumProvider = Provider<bool>(
  (ref) => ref.watch(entitlementProvider.select((e) => e.isPremium)),
);

/// `ref.watch(hasPremiumFeatureProvider(PremiumFeature.docxExport))`
final hasPremiumFeatureProvider = Provider.family<bool, PremiumFeature>(
  (ref, feature) =>
      ref.watch(entitlementProvider.select((e) => e.has(feature))),
);
