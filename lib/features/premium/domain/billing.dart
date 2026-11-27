import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';
import 'package:sqflite/sqflite.dart';

/// Product identifiers, exactly as created in the Play Console.
abstract final class PremiumProducts {
  static const String monthly = 'md_scanner_premium_monthly';
  static const String yearly = 'md_scanner_premium_yearly';
  static const String lifetime = 'md_scanner_premium_lifetime';

  static const Set<String> all = {monthly, yearly, lifetime};

  static PremiumPlan? planOf(String productId) => switch (productId) {
    monthly => PremiumPlan.monthly,
    yearly => PremiumPlan.yearly,
    lifetime => PremiumPlan.lifetime,
    _ => null,
  };
}

/// A product as described by the store. The price always comes from Google
/// Play: none is ever written in the app.
class StoreProduct extends Equatable {
  const StoreProduct({
    required this.id,
    required this.plan,
    required this.price,
    this.handle,
  });

  final String id;
  final PremiumPlan plan;

  /// Localized price string provided by the store.
  final String price;

  /// Opaque plugin object needed to start the purchase.
  final Object? handle;

  @override
  List<Object?> get props => [id, plan, price];
}

enum StorePurchaseStatus { pending, purchased, cancelled, failed }

/// A purchase reported by the Play Billing library on this device.
class StorePurchase extends Equatable {
  const StorePurchase({
    required this.productId,
    required this.status,
    required this.token,
    this.isAutoRenewing,
    this.needsCompletion = false,
    this.handle,
  });

  final String productId;
  final StorePurchaseStatus status;

  /// Purchase token, sent to the verification server. Never stored in clear.
  final String token;
  final bool? isAutoRenewing;

  /// The purchase still has to be acknowledged, or Google refunds it.
  final bool needsCompletion;
  final Object? handle;

  @override
  List<Object?> get props => [
    productId,
    status,
    token,
    isAutoRenewing,
    needsCompletion,
  ];
}

/// Thin view of the store plugin, so the billing rules are testable.
abstract interface class BillingGateway {
  Future<bool> isAvailable();

  /// Throws when the store cannot answer (as opposed to "no such product").
  Future<List<StoreProduct>> queryProducts(Set<String> ids);

  Future<void> buy(StoreProduct product);

  /// Purchases still owned according to Google Play. Throws when the store
  /// cannot be reached.
  Future<List<StorePurchase>> queryOwnedPurchases();

  Future<void> complete(StorePurchase purchase);

  Stream<List<StorePurchase>> get purchaseUpdates;
}

class VerifiedPurchase {
  const VerifiedPurchase({
    required this.source,
    this.expiresAt,
    this.isAutoRenewing,
  });

  final EntitlementSource source;
  final DateTime? expiresAt;
  final bool? isAutoRenewing;
}

/// Decides whether a purchase really entitles the user to Premium.
abstract interface class PurchaseVerifier {
  Future<Result<VerifiedPurchase>> verify(StorePurchase purchase);
}

/// Used when no verification server is configured: trusts a purchase only if
/// the Play Billing library reports it as purchased on this device.
///
/// This is weaker than server verification: it cannot see refunds until Play
/// stops returning the purchase, and a rooted device could tamper with it.
class PlayStorePurchaseVerifier implements PurchaseVerifier {
  const PlayStorePurchaseVerifier();

  @override
  Future<Result<VerifiedPurchase>> verify(StorePurchase purchase) async {
    if (purchase.status != StorePurchaseStatus.purchased ||
        purchase.token.isEmpty) {
      return const Err(BillingFailure(BillingFailureKind.verificationFailed));
    }
    return Success(
      VerifiedPurchase(
        source: EntitlementSource.playStore,
        isAutoRenewing: purchase.isAutoRenewing,
      ),
    );
  }
}

/// Applies the Premium rules:
/// - Premium is granted only for a verified purchase, never from a local flag;
/// - a purchase is acknowledged only after verification;
/// - at every start Google Play is asked again: a purchase it no longer
///   returns is revoked (expired, cancelled and lapsed, refunded);
/// - when the store cannot be reached, the last verified state is tolerated
///   for [offlineGrace], then the app falls back to the free tier.
class BillingService {
  BillingService({
    required this._gateway,
    required this._verifier,
    required Database database,
    required this._onEntitlement,
    this._logger,
    DateTime Function()? clock,
  }) : _db = database,
       _clock = clock ?? DateTime.now;

  final BillingGateway _gateway;
  final PurchaseVerifier _verifier;
  final Database _db;
  final void Function(Entitlement entitlement) _onEntitlement;
  final AppLogger? _logger;
  final DateTime Function() _clock;
  StreamSubscription<List<StorePurchase>>? _subscription;

  static const Duration offlineGrace = Duration(days: 3);
  static const String _table = 'subscription_cache';

  /// Emits the outcome of each purchase attempt started by [purchase].
  final StreamController<Result<void>> _outcomes =
      StreamController<Result<void>>.broadcast();

  Stream<Result<void>> get purchaseOutcomes => _outcomes.stream;

  /// Starts listening to the store and checks the current entitlement.
  Future<void> start() async {
    _subscription ??= _gateway.purchaseUpdates.listen(_onPurchases);
    await refreshEntitlement();
  }

  Future<Result<List<StoreProduct>>> loadOffers() => guard(() async {
    if (!await _gateway.isAvailable()) {
      throw const FailureException(
        BillingFailure(BillingFailureKind.storeUnavailable),
      );
    }
    final products = await _gateway.queryProducts(PremiumProducts.all);
    if (products.isEmpty) {
      throw const FailureException(
        BillingFailure(BillingFailureKind.productNotFound),
      );
    }
    return products..sort((a, b) => a.plan.index.compareTo(b.plan.index));
  }, onError: _storeError);

  /// Opens the Google Play purchase sheet. The result arrives later through
  /// [purchaseOutcomes].
  Future<Result<void>> purchase(StoreProduct product) =>
      guard(() => _gateway.buy(product), onError: _storeError);

  /// Asks Google Play which purchases are still owned and updates Premium.
  Future<Result<void>> refreshEntitlement() async {
    List<StorePurchase> owned;
    try {
      if (!await _gateway.isAvailable()) throw StateError('unavailable');
      owned = await _gateway.queryOwnedPurchases();
    } catch (_) {
      await _applyOfflineGrace();
      return const Err(BillingFailure(BillingFailureKind.storeUnavailable));
    }

    for (final purchase in owned) {
      if (purchase.status != StorePurchaseStatus.purchased) continue;
      final plan = PremiumProducts.planOf(purchase.productId);
      if (plan == null) continue;
      final verified = await _verifier.verify(purchase);
      if (verified case Success(:final value)) {
        await _grant(purchase, plan, value);
        return const Success(null);
      }
    }
    // Google Play answered and confirmed nothing: Premium is revoked.
    await _db.delete(_table);
    _onEntitlement(const Entitlement.free());
    return const Success(null);
  }

  Future<void> _onPurchases(List<StorePurchase> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case StorePurchaseStatus.pending:
          _outcomes.add(const Err(BillingFailure(BillingFailureKind.pending)));
        case StorePurchaseStatus.cancelled:
          _outcomes.add(
            const Err(BillingFailure(BillingFailureKind.userCancelled)),
          );
        case StorePurchaseStatus.failed:
          _outcomes.add(
            const Err(BillingFailure(BillingFailureKind.purchaseFailed)),
          );
        case StorePurchaseStatus.purchased:
          final plan = PremiumProducts.planOf(purchase.productId);
          final verified = plan == null
              ? const Err<VerifiedPurchase>(
                  BillingFailure(BillingFailureKind.productNotFound),
                )
              : await _verifier.verify(purchase);
          switch (verified) {
            case Success(:final value):
              await _grant(purchase, plan!, value);
              if (purchase.needsCompletion) await _gateway.complete(purchase);
              _outcomes.add(const Success(null));
            case Err(:final failure):
              // Not acknowledged on purpose: Google refunds an unverified
              // purchase automatically.
              _logger?.failure('billing.verification_failed', failure);
              _outcomes.add(Err(failure));
          }
      }
    }
  }

  Future<void> _grant(
    StorePurchase purchase,
    PremiumPlan plan,
    VerifiedPurchase verified,
  ) async {
    await _db.insert(_table, {
      'product_id': purchase.productId,
      'state': 'active',
      'verification_source': verified.source.name,
      'purchase_token_hash': sha256
          .convert(utf8.encode(purchase.token))
          .toString(),
      'expiration_date': verified.expiresAt?.toUtc().millisecondsSinceEpoch,
      'last_verified_at': _clock().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _onEntitlement(
      Entitlement(
        isPremium: true,
        plan: plan,
        expiresAt: verified.expiresAt,
        source: verified.source,
        isAutoRenewing: verified.isAutoRenewing,
      ),
    );
    _logger?.info('billing.premium_granted', {'plan': plan});
  }

  Future<void> _applyOfflineGrace() async {
    final rows = await _db.query(_table, orderBy: 'last_verified_at DESC');
    for (final row in rows) {
      final plan = PremiumProducts.planOf(row['product_id']! as String);
      final verifiedAt = DateTime.fromMillisecondsSinceEpoch(
        row['last_verified_at']! as int,
        isUtc: true,
      );
      final expiry = row['expiration_date'] as int?;
      final now = _clock().toUtc();
      final expired =
          expiry != null &&
          now.isAfter(DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true));
      if (plan != null &&
          !expired &&
          now.difference(verifiedAt) <= offlineGrace) {
        _onEntitlement(
          Entitlement(
            isPremium: true,
            plan: plan,
            source: EntitlementSource.offlineGrace,
          ),
        );
        return;
      }
    }
    _onEntitlement(const Entitlement.free());
  }

  Failure? _storeError(Object error, StackTrace _) => error is FailureException
      ? null
      : BillingFailure(
          BillingFailureKind.storeUnavailable,
          debugMessage: error.runtimeType.toString(),
        );

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _outcomes.close();
  }
}

/// Bound to the Play implementation in `bootstrap()`.
final billingGatewayProvider = Provider<BillingGateway>(
  (ref) => throw StateError('billingGatewayProvider must be overridden'),
);

final purchaseVerifierProvider = Provider<PurchaseVerifier>(
  (ref) => const PlayStorePurchaseVerifier(),
);

final billingServiceProvider = Provider<BillingService>((ref) {
  final service = BillingService(
    gateway: ref.watch(billingGatewayProvider),
    verifier: ref.watch(purchaseVerifierProvider),
    database: ref.watch(databaseProvider),
    onEntitlement: ref.read(entitlementProvider.notifier).update,
    logger: ref.watch(appLoggerProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
