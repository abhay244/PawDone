// Tests for supabase/functions/_shared/premium.mjs. Run with: node --test supabase/tests/
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  affectedUserIDs,
  authorizationMatches,
  entitlementRow,
  fetchSubscriber,
  premiumFromSubscriber,
} from "../functions/_shared/premium.mjs";

const NOW = new Date("2026-10-16T10:00:00Z");
const ASHA = "6f1c1d4e-3a6b-4c8e-9a51-1d2f3e4a5b6c";
const SAM = "9a8b7c6d-5e4f-4a3b-2c1d-0e9f8a7b6c5d";

function subscriber(entitlement) {
  return { request_date: NOW.toISOString(), subscriber: { entitlements: entitlement ? { premium: entitlement } : {} } };
}

test("active subscription is Premium until it expires", () => {
  const premium = premiumFromSubscriber(subscriber({
    expires_date: "2026-11-16T10:00:00Z",
    grace_period_expires_date: null,
    product_identifier: "com.abhaysingh.pawdone.premium.monthly",
    purchase_date: "2026-10-16T10:00:00Z",
  }), NOW);
  assert.deepEqual(premium, {
    isPremium: true,
    productId: "com.abhaysingh.pawdone.premium.monthly",
    expiresAt: "2026-11-16T10:00:00.000Z",
  });
});

test("expired subscription is not Premium", () => {
  const premium = premiumFromSubscriber(subscriber({ expires_date: "2026-10-01T00:00:00Z", product_identifier: "m" }), NOW);
  assert.equal(premium.isPremium, false);
  assert.equal(premium.expiresAt, "2026-10-01T00:00:00.000Z", "keeps the date for the record");
});

test("billing grace period keeps Premium", () => {
  const premium = premiumFromSubscriber(subscriber({
    expires_date: "2026-10-15T00:00:00Z",
    grace_period_expires_date: "2026-10-31T00:00:00Z",
    product_identifier: "m",
  }), NOW);
  assert.equal(premium.isPremium, true);
  assert.equal(premium.expiresAt, "2026-10-31T00:00:00.000Z");
});

test("no expiry means lifetime", () => {
  const premium = premiumFromSubscriber(subscriber({ expires_date: null, product_identifier: "lifetime" }), NOW);
  assert.deepEqual(premium, { isPremium: true, productId: "lifetime", expiresAt: null });
});

test("no entitlement means Free", () => {
  assert.deepEqual(premiumFromSubscriber(subscriber(null), NOW), { isPremium: false, productId: null, expiresAt: null });
  assert.equal(premiumFromSubscriber({}, NOW).isPremium, false);
});

test("affected users: deduplicated Supabase IDs only", () => {
  const ids = affectedUserIDs({
    app_user_id: ASHA.toUpperCase(),
    original_app_user_id: "$RCAnonymousID:abc123",
    aliases: [ASHA, "$RCAnonymousID:abc123"],
  });
  assert.deepEqual(ids, [ASHA]);
});

test("affected users: both sides of a transfer", () => {
  const ids = affectedUserIDs({ app_user_id: SAM, aliases: [SAM], transferred_from: [ASHA], transferred_to: [SAM] });
  assert.deepEqual(ids.sort(), [ASHA, SAM].sort());
  assert.deepEqual(affectedUserIDs(undefined), []);
});

test("entitlement row matches the table", () => {
  const row = entitlementRow(ASHA, { isPremium: true, productId: "m", expiresAt: "2026-11-16T10:00:00.000Z" }, NOW);
  assert.deepEqual(row, {
    user_id: ASHA,
    is_premium: true,
    product_id: "m",
    expires_at: "2026-11-16T10:00:00.000Z",
    updated_at: NOW.toISOString(),
  });
});

test("fetches the subscriber with the secret key", async () => {
  let request;
  const fetchImpl = async (url, init) => {
    request = { url, init };
    return new Response(JSON.stringify(subscriber(null)), { status: 200 });
  };
  await fetchSubscriber(ASHA, "sk_test", fetchImpl);
  assert.equal(request.url, `https://api.revenuecat.com/v1/subscribers/${ASHA}`);
  assert.equal(request.init.headers.authorization, "Bearer sk_test");

  await assert.rejects(fetchSubscriber(ASHA, "sk_test", async () => new Response("", { status: 500 })));
});

test("webhook authorization must match exactly", () => {
  assert.ok(authorizationMatches("Bearer s3cret", "Bearer s3cret"));
  assert.ok(!authorizationMatches("Bearer s3cret ", "Bearer s3cret"));
  assert.ok(!authorizationMatches(null, "Bearer s3cret"));
  assert.ok(!authorizationMatches("anything", ""));
});
