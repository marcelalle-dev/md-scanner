import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:md_scanner/app/configuration/app_config.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/premium/domain/billing.dart';
import 'package:md_scanner/shared/providers/entitlement.dart';

/// Google Play Billing through the official `in_app_purchase` plugin.
class PlayBillingGateway implements BillingGateway {
  PlayBillingGateway([InAppPurchase? store])
    : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async {
    final response = await _store.queryProductDetails(ids);
    final error = response.error;
    // A failed query also comes back with an empty list: only the error
    // field tells it apart from "products not created yet".
    if (error != null) throw StateError('product query failed');
    return [
      for (final details in response.productDetails)
        if (PremiumProducts.planOf(details.id) case final plan?)
          StoreProduct(
            id: details.id,
            plan: plan,
            price: details.price,
            handle: details,
          ),
    ];
  }

  @override
  Future<void> buy(StoreProduct product) async {
    final details = product.handle! as ProductDetails;
    await _store.buyNonConsumable(
      purchaseParam: details is GooglePlayProductDetails
          ? GooglePlayPurchaseParam(
              productDetails: details,
              offerToken: details.offerToken,
            )
          : PurchaseParam(productDetails: details),
    );
  }

  @override
  Future<List<StorePurchase>> queryOwnedPurchases() async {
    final addition = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    if (response.error != null) throw StateError('purchase query failed');
    return [for (final purchase in response.pastPurchases) _map(purchase)];
  }

  @override
  Future<void> complete(StorePurchase purchase) =>
      _store.completePurchase(purchase.handle! as PurchaseDetails);

  @override
  Stream<List<StorePurchase>> get purchaseUpdates =>
      _store.purchaseStream.map((purchases) => purchases.map(_map).toList());

  StorePurchase _map(PurchaseDetails purchase) {
    final play = purchase is GooglePlayPurchaseDetails
        ? purchase.billingClientPurchase
        : null;
    final purchasedInPlay =
        play == null || play.purchaseState == PurchaseStateWrapper.purchased;
    return StorePurchase(
      productId: purchase.productID,
      status: switch (purchase.status) {
        PurchaseStatus.pending => StorePurchaseStatus.pending,
        PurchaseStatus.canceled => StorePurchaseStatus.cancelled,
        PurchaseStatus.error => StorePurchaseStatus.failed,
        PurchaseStatus.purchased || PurchaseStatus.restored =>
          purchasedInPlay
              ? StorePurchaseStatus.purchased
              : StorePurchaseStatus.pending,
      },
      token: purchase.verificationData.serverVerificationData,
      isAutoRenewing: play?.isAutoRenewing,
      needsCompletion: purchase.pendingCompletePurchase,
      handle: purchase,
    );
  }
}

/// Server-side verification through the MD SCANNER backend, which asks the
/// Google Play Developer API. Detects refunds and tampering.
class ServerPurchaseVerifier implements PurchaseVerifier {
  ServerPurchaseVerifier({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<Result<VerifiedPurchase>> verify(StorePurchase purchase) => guard(
    () async {
      final response = await _client
          .post(
            endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'packageName': AppConfig.androidPackageName,
              'productId': purchase.productId,
              'purchaseToken': purchase.token,
              'type': purchase.productId == PremiumProducts.lifetime
                  ? 'product'
                  : 'subscription',
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw FailureException(
          NetworkFailure(
            NetworkFailureKind.serverError,
            statusCode: response.statusCode,
          ),
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['valid'] != true) {
        throw const FailureException(
          BillingFailure(BillingFailureKind.verificationFailed),
        );
      }
      final expiry = body['expiryTimeMillis'];
      return VerifiedPurchase(
        source: EntitlementSource.server,
        expiresAt: expiry is int
            ? DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true)
            : null,
        isAutoRenewing: body['autoRenewing'] as bool?,
      );
    },
    onError: (error, _) => error is FormatException || error is TypeError
        ? const NetworkFailure(NetworkFailureKind.invalidResponse)
        : null,
  );
}

/// Server verification when a backend is configured, device-side otherwise.
PurchaseVerifier createPurchaseVerifier() =>
    AppConfig.isServerVerificationConfigured
    ? ServerPurchaseVerifier(
        endpoint: Uri.parse(AppConfig.purchaseVerificationUrl),
      )
    : const PlayStorePurchaseVerifier();
