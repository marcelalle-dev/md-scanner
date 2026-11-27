import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/configuration/app_config.dart';
import 'package:md_scanner/app/theme/app_theme.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/l10n/failure_messages.dart';
import 'package:md_scanner/core/utils/formatters.dart';
import 'package:md_scanner/core/widgets/cards.dart';
import 'package:md_scanner/core/widgets/feedback.dart';
import 'package:md_scanner/core/widgets/state_views.dart';
import 'package:md_scanner/features/premium/domain/billing.dart';
import 'package:md_scanner/features/premium/l10n/generated/premium_localizations.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';
import 'package:url_launcher/url_launcher.dart';

/// Offers read from Google Play. Prices are the store's, never hard-coded.
final premiumOffersProvider = FutureProvider.autoDispose<List<StoreProduct>>((
  ref,
) async {
  final result = await ref.watch(billingServiceProvider).loadOffers();
  return switch (result) {
    Success(:final value) => value,
    Err(:final failure) => throw FailureException(failure),
  };
});

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  StreamSubscription<Result<void>>? _outcomes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _outcomes = ref
        .read(billingServiceProvider)
        .purchaseOutcomes
        .listen(_onOutcome);
  }

  @override
  void dispose() {
    _outcomes?.cancel();
    super.dispose();
  }

  void _onOutcome(Result<void> outcome) {
    if (!mounted) return;
    final l10n = PremiumLocalizations.of(context);
    setState(() => _busy = false);
    switch (outcome) {
      case Success():
        context.showMessage(l10n.premiumThanks);
      case Err(:final failure):
        if (failure is BillingFailure &&
            failure.kind == BillingFailureKind.userCancelled) {
          return;
        }
        if (failure is BillingFailure &&
            failure.kind == BillingFailureKind.pending) {
          context.showMessage(l10n.premiumPending);
          return;
        }
        context.showFailure(failure);
    }
  }

  Future<void> _buy(StoreProduct product) async {
    setState(() => _busy = true);
    final result = await ref.read(billingServiceProvider).purchase(product);
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      setState(() => _busy = false);
      context.showFailure(failure);
    }
  }

  Future<void> _restore() async {
    final l10n = PremiumLocalizations.of(context);
    setState(() => _busy = true);
    final result = await ref.read(billingServiceProvider).refreshEntitlement();
    if (!mounted) return;
    setState(() => _busy = false);
    final failure = result.failureOrNull;
    failure == null
        ? context.showMessage(l10n.premiumRestored)
        : context.showFailure(failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = PremiumLocalizations.of(context);
    final theme = Theme.of(context);
    final entitlement = ref.watch(entitlementProvider);
    final offers = ref.watch(premiumOffersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.premiumTitle)),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium,
                size: 40,
                color: AppSemanticColors.of(context).premium,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.premiumTagline,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final benefit in [
            l10n.benefitNoAds,
            l10n.benefitDocx,
            l10n.benefitAi,
            l10n.benefitCustom,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: AppSemanticColors.of(context).success,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(benefit)),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (entitlement.isPremium) ...[
            InfoBanner(
              tone: entitlement.source == EntitlementSource.offlineGrace
                  ? InfoBannerTone.warning
                  : InfoBannerTone.success,
              message: [
                l10n.premiumActive,
                if (entitlement.plan == PremiumPlan.lifetime)
                  l10n.premiumActiveLifetime
                else if (entitlement.expiresAt != null)
                  l10n.premiumActiveUntil(
                    formatDate(
                      context.coreL10n.localeName,
                      entitlement.expiresAt!,
                    ),
                  ),
                if (entitlement.source == EntitlementSource.offlineGrace)
                  l10n.premiumOfflineGrace,
              ].join('\n'),
            ),
            if (entitlement.plan != null &&
                entitlement.plan != PremiumPlan.lifetime) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    AppConfig.manageSubscriptionUrl(switch (entitlement.plan!) {
                      PremiumPlan.monthly => PremiumProducts.monthly,
                      PremiumPlan.yearly => PremiumProducts.yearly,
                      PremiumPlan.lifetime => PremiumProducts.lifetime,
                    }),
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.premiumManage),
              ),
            ],
          ] else
            offers.when(
              loading: () => LoadingState(message: l10n.premiumLoading),
              error: (error, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InfoBanner(
                    tone: InfoBannerTone.warning,
                    message:
                        '${l10n.premiumNoOffers}\n${failureMessage(context, failureOf(error))}\n${l10n.premiumNoOffersHint}',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(premiumOffersProvider),
                    child: Text(context.coreL10n.actionRetry),
                  ),
                ],
              ),
              data: (products) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.sm,
                children: [
                  for (final product in products)
                    Card(
                      child: ListTile(
                        title: Text(switch (product.plan) {
                          PremiumPlan.monthly => l10n.planMonthly,
                          PremiumPlan.yearly => l10n.planYearly,
                          PremiumPlan.lifetime => l10n.planLifetime,
                        }),
                        subtitle: Text(
                          '${product.price} · ${switch (product.plan) {
                            PremiumPlan.monthly => l10n.planMonthlyNote,
                            PremiumPlan.yearly => l10n.planYearlyNote,
                            PremiumPlan.lifetime => l10n.planLifetimeNote,
                          }}',
                        ),
                        trailing: FilledButton(
                          onPressed: _busy ? null : () => _buy(product),
                          child: Text(l10n.premiumBuy),
                        ),
                      ),
                    ),
                  Text(l10n.premiumLegal, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: _busy ? null : _restore,
            child: Text(l10n.premiumRestore),
          ),
        ],
      ),
    );
  }
}
