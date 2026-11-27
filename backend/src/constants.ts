/** Public API version segment used in every route (`/v1/...`). */
export const API_VERSION = "v1";

export const SERVICE_NAME = "md-scanner-backend";

/** The only Android application this backend serves. */
export const ALLOWED_PACKAGE_NAME = "dev.marcelalle.mdscanner";

export const ROUTES = {
  health: `/${API_VERSION}/health`,
  aiTasks: `/${API_VERSION}/ai/tasks`,
  purchasesVerify: `/${API_VERSION}/purchases/verify`,
} as const;

/** Hard cap for the small JSON body of the purchase verification endpoint. */
export const PURCHASE_BODY_MAX_BYTES = 8 * 1024;

/**
 * Budget accounting unit: "input-token equivalents".
 * The weights follow Anthropic's price ratios, which are identical across the
 * current model tiers (output = 5x input, 5-minute cache write = 1.25x input,
 * cache read <= 0.1x input). Budget x input price per token is therefore an
 * upper bound of the spend for the configured model.
 */
export const BUDGET_WEIGHTS = {
  input: 1,
  cacheWrite: 1.25,
  cacheRead: 0.1,
  output: 5,
} as const;
