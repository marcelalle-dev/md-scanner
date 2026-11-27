import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/storage/database/app_database.dart';
import 'package:md_scanner/features/ads/domain/ad_policy.dart';
import 'package:md_scanner/features/premium/domain/billing.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';

import '../../helpers/test_database.dart';

class _FakeGateway implements BillingGateway {
  bool available = true;
  bool failQueries = false;
  List<StoreProduct> products = const [
    StoreProduct(
      id: PremiumProducts.yearly,
      plan: PremiumPlan.yearly,
      price: '19,99 €',
    ),
    StoreProduct(
      id: PremiumProducts.monthly,
      plan: PremiumPlan.monthly,
      price: '2,99 €',
    ),
  ];
  List<StorePurchase> owned = [];
  final List<StorePurchase> completed = [];
  final StreamController<List<StorePurchase>> updates =
      StreamController<List<StorePurchase>>.broadcast();

  Future<void> close() => updates.close();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async {
    if (failQueries) throw StateError('query failed');
    return List.of(products);
  }

  @override
  Future<void> buy(StoreProduct product) async {}

  @override
  Future<List<StorePurchase>> queryOwnedPurchases() async {
    if (failQueries) throw StateError('query failed');
    return owned;
  }

  @override
  Future<void> complete(StorePurchase purchase) async =>
      completed.add(purchase);

  @override
  Stream<List<StorePurchase>> get purchaseUpdates => updates.stream;
}

class _RejectingVerifier implements PurchaseVerifier {
  @override
  Future<Result<VerifiedPurchase>> verify(StorePurchase purchase) async =>
      const Err(BillingFailure(BillingFailureKind.verificationFailed));
}

StorePurchase _purchase(
  String productId, {
  StorePurchaseStatus status = StorePurchaseStatus.purchased,
  bool needsCompletion = true,
}) => StorePurchase(
  productId: productId,
  status: status,
  token: 'token-$productId',
  isAutoRenewing: true,
  needsCompletion: needsCompletion,
);

void main() {
  late AppDatabase database;
  late _FakeGateway gateway;
  late Entitlement entitlement;
  late DateTime now;
  late BillingService service;

  BillingService build({PurchaseVerifier? verifier}) => BillingService(
    gateway: gateway,
    verifier: verifier ?? const PlayStorePurchaseVerifier(),
    database: database.db,
    onEntitlement: (value) => entitlement = value,
    clock: () => now,
  );

  setUp(() async {
    database = await openTestDatabase();
    gateway = _FakeGateway();
    entitlement = const Entitlement.free();
    now = DateTime.utc(2026, 11, 27);
    service = build();
  });

  tearDown(() async {
    await service.dispose();
    await gateway.close();
    await database.close();
  });

  Future<Result<void>> deliver(StorePurchase purchase) async {
    final outcome = service.purchaseOutcomes.first;
    gateway.updates.add([purchase]);
    return outcome;
  }

  test('starts free when Google Play owns nothing', () async {
    await service.start();

    expect(entitlement.isPremium, isFalse);
  });

  test('offers come from the store, sorted by plan', () async {
    final offers = (await service.loadOffers()).valueOrNull!;

    expect(offers.map((o) => o.plan), [
      PremiumPlan.monthly,
      PremiumPlan.yearly,
    ]);
    expect(offers.first.price, '2,99 €');
  });

  test('a failed product query is an error, not an empty catalogue', () async {
    gateway.failQueries = true;
    expect(
      (await service.loadOffers()).failureOrNull,
      isA<BillingFailure>().having(
        (f) => f.kind,
        'kind',
        BillingFailureKind.storeUnavailable,
      ),
    );

    gateway
      ..failQueries = false
      ..products = const [];
    expect(
      (await service.loadOffers()).failureOrNull,
      const BillingFailure(BillingFailureKind.productNotFound),
    );
  });

  test('a verified purchase grants Premium and is acknowledged', () async {
    await service.start();

    final outcome = await deliver(_purchase(PremiumProducts.yearly));

    expect(outcome.isSuccess, isTrue);
    expect(entitlement.isPremium, isTrue);
    expect(entitlement.plan, PremiumPlan.yearly);
    expect(entitlement.source, EntitlementSource.playStore);
    expect(gateway.completed, hasLength(1));
  });

  test('the purchase token is never stored in clear', () async {
    await service.start();
    await deliver(_purchase(PremiumProducts.monthly));

    final row = (await database.db.query('subscription_cache')).single;
    expect(row.values.join('|'), isNot(contains('token-')));
    expect((row['purchase_token_hash']! as String).length, 64);
  });

  test('pending, cancelled and failed purchases grant nothing', () async {
    await service.start();
    for (final (status, kind) in [
      (StorePurchaseStatus.pending, BillingFailureKind.pending),
      (StorePurchaseStatus.cancelled, BillingFailureKind.userCancelled),
      (StorePurchaseStatus.failed, BillingFailureKind.purchaseFailed),
    ]) {
      final outcome = await deliver(
        _purchase(PremiumProducts.yearly, status: status),
      );
      expect(outcome.failureOrNull, BillingFailure(kind));
    }

    expect(entitlement.isPremium, isFalse);
    expect(gateway.completed, isEmpty);
  });

  test(
    'a purchase that fails verification is neither granted nor acknowledged',
    () async {
      await service.dispose();
      service = build(verifier: _RejectingVerifier());
      await service.start();

      final outcome = await deliver(_purchase(PremiumProducts.lifetime));

      expect(
        outcome.failureOrNull,
        const BillingFailure(BillingFailureKind.verificationFailed),
      );
      expect(entitlement.isPremium, isFalse);
      expect(gateway.completed, isEmpty);
      expect(await database.db.query('subscription_cache'), isEmpty);
    },
  );

  test('restoring finds a purchase still owned', () async {
    gateway.owned = [
      _purchase(PremiumProducts.lifetime, needsCompletion: false),
    ];

    expect((await service.refreshEntitlement()).isSuccess, isTrue);

    expect(entitlement.isPremium, isTrue);
    expect(entitlement.plan, PremiumPlan.lifetime);
  });

  test(
    'Premium is revoked when Google Play no longer returns the purchase',
    () async {
      gateway.owned = [_purchase(PremiumProducts.monthly)];
      await service.start();
      expect(entitlement.isPremium, isTrue);

      // Expired, cancelled and lapsed, or refunded.
      gateway.owned = [];
      await service.refreshEntitlement();

      expect(entitlement.isPremium, isFalse);
      expect(await database.db.query('subscription_cache'), isEmpty);
    },
  );

  test(
    'offline, the last verified state is tolerated for three days only',
    () async {
      gateway.owned = [_purchase(PremiumProducts.yearly)];
      await service.start();

      gateway.available = false;
      now = now.add(const Duration(days: 2));
      final result = await service.refreshEntitlement();
      expect(result.isFailure, isTrue);
      expect(entitlement.isPremium, isTrue);
      expect(entitlement.source, EntitlementSource.offlineGrace);

      now = now.add(const Duration(days: 2));
      await service.refreshEntitlement();
      expect(entitlement.isPremium, isFalse);
    },
  );

  test(
    'without any verified purchase, being offline never grants Premium',
    () async {
      gateway.available = false;

      await service.start();

      expect(entitlement.isPremium, isFalse);
    },
  );

  test('unknown products are ignored', () async {
    gateway.owned = [_purchase('some_other_product')];

    await service.refreshEntitlement();

    expect(entitlement.isPremium, isFalse);
  });

  group('AdPolicy', () {
    late DateTime clock;
    late AdPolicy policy;

    setUp(() {
      clock = DateTime.utc(2026, 11, 27, 9);
      policy = AdPolicy(clock: () => clock);
    });

    void completeTasks(int count) {
      for (var i = 0; i < count; i++) {
        policy.taskCompleted();
      }
    }

    test('never shows an interstitial to a Premium user', () {
      completeTasks(10);
      clock = clock.add(const Duration(hours: 1));

      expect(policy.canShowInterstitial(isPremium: true), isFalse);
      expect(policy.canShowInterstitial(isPremium: false), isTrue);
    });

    test('waits for the warm-up and for enough completed tasks', () {
      completeTasks(AdPolicy.tasksBetween);
      expect(policy.canShowInterstitial(isPremium: false), isFalse);

      clock = clock.add(AdPolicy.warmUp);
      expect(policy.canShowInterstitial(isPremium: false), isTrue);

      policy.interstitialShown();
      clock = clock.add(const Duration(hours: 1));
      completeTasks(AdPolicy.tasksBetween - 1);
      expect(policy.canShowInterstitial(isPremium: false), isFalse);
    });

    test('keeps a minimum interval and a session cap', () {
      clock = clock.add(AdPolicy.warmUp);
      completeTasks(AdPolicy.tasksBetween);
      policy.interstitialShown();

      completeTasks(AdPolicy.tasksBetween);
      expect(policy.canShowInterstitial(isPremium: false), isFalse);
      clock = clock.add(AdPolicy.minInterval);
      expect(policy.canShowInterstitial(isPremium: false), isTrue);

      for (var shown = 1; shown < AdPolicy.maxPerSession; shown++) {
        policy.interstitialShown();
        clock = clock.add(AdPolicy.minInterval);
        completeTasks(AdPolicy.tasksBetween);
      }
      expect(policy.canShowInterstitial(isPremium: false), isFalse);
    });
  });
}
