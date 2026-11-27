export type PurchaseType = "subscription" | "product";

/**
 * Closed catalogue of Google Play products that grant premium access.
 * Anything else is rejected before any call to Google.
 */
export const PREMIUM_PRODUCTS = {
  md_scanner_premium_monthly: "subscription",
  md_scanner_premium_yearly: "subscription",
  md_scanner_premium_lifetime: "product",
} as const satisfies Record<string, PurchaseType>;

export type ProductId = keyof typeof PREMIUM_PRODUCTS;

export function isProductId(value: string): value is ProductId {
  return Object.hasOwn(PREMIUM_PRODUCTS, value);
}

export function purchaseTypeOf(productId: ProductId): PurchaseType {
  return PREMIUM_PRODUCTS[productId];
}
