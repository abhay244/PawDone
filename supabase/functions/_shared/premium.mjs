// Premium status from RevenueCat, shared by the revenuecat-webhook and sync-premium
// Edge Functions. Plain JavaScript and Web APIs so it also runs under Node for tests
// (supabase/tests/premium.test.mjs).

/** The RevenueCat entitlement that unlocks Premium. */
export const ENTITLEMENT_ID = "premium";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Supabase user IDs a webhook event is about. The app logs in to RevenueCat with the
 * Supabase user ID, so anything else (e.g. RevenueCat's anonymous IDs) is skipped.
 */
export function affectedUserIDs(event) {
  const ids = [
    event?.app_user_id,
    event?.original_app_user_id,
    ...(event?.aliases ?? []),
    ...(event?.transferred_from ?? []),
    ...(event?.transferred_to ?? []),
  ];
  return [...new Set(ids.filter((id) => typeof id === "string" && UUID.test(id)).map((id) => id.toLowerCase()))];
}

/**
 * Premium state from a RevenueCat v1 subscriber response.
 * Active while the entitlement hasn't expired, including any billing grace period;
 * a null expiry means it never expires.
 */
export function premiumFromSubscriber(body, now = new Date()) {
  const entitlement = body?.subscriber?.entitlements?.[ENTITLEMENT_ID];
  if (!entitlement) {
    return { isPremium: false, productId: null, expiresAt: null };
  }
  const productId = entitlement.product_identifier ?? null;
  if (!entitlement.expires_date) {
    return { isPremium: true, productId, expiresAt: null };
  }

  let expiry = new Date(entitlement.expires_date);
  if (entitlement.grace_period_expires_date) {
    const grace = new Date(entitlement.grace_period_expires_date);
    if (grace > expiry) expiry = grace;
  }
  return { isPremium: expiry > now, productId, expiresAt: expiry.toISOString() };
}

/** Fetches a customer from RevenueCat's v1 API with a secret key. */
export async function fetchSubscriber(appUserID, secretKey, fetchImpl = fetch) {
  const response = await fetchImpl(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserID)}`, {
    headers: { authorization: `Bearer ${secretKey}`, accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error(`RevenueCat returned ${response.status} for ${appUserID}`);
  }
  return response.json();
}

/** Deletes a customer's data from RevenueCat (account deletion). Doesn't cancel App Store subscriptions. */
export async function deleteSubscriber(appUserID, secretKey, fetchImpl = fetch) {
  const response = await fetchImpl(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserID)}`, {
    method: "DELETE",
    headers: { authorization: `Bearer ${secretKey}`, accept: "application/json" },
  });
  // 404: RevenueCat never saw this user, so there's nothing to delete.
  if (!response.ok && response.status !== 404) {
    throw new Error(`RevenueCat returned ${response.status} deleting ${appUserID}`);
  }
}

/** The row to upsert into public.entitlements. */
export function entitlementRow(userID, premium, now = new Date()) {
  return {
    user_id: userID,
    is_premium: premium.isPremium,
    product_id: premium.productId,
    expires_at: premium.expiresAt,
    updated_at: now.toISOString(),
  };
}

/** Compares a request's Authorization header with the expected value in constant time. */
export function authorizationMatches(header, expected) {
  if (!header || !expected) return false;
  const a = new TextEncoder().encode(header);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) difference |= a[index] ^ b[index];
  return difference === 0;
}
