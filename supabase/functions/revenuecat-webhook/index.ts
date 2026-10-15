// Keeps public.entitlements in step with RevenueCat. RevenueCat calls this for every
// subscription event (purchase, renewal, cancellation, expiry, transfer, …).
// Following RevenueCat's advice, it ignores the event details and fetches each affected
// customer's current state instead.
//
// Secrets (Supabase dashboard → Edge Functions → Secrets):
//   REVENUECAT_WEBHOOK_AUTH  The exact Authorization header value set on the RevenueCat webhook
//   REVENUECAT_SECRET_KEY    RevenueCat secret API key (v1, starts with sk_)

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  affectedUserIDs,
  authorizationMatches,
  entitlementRow,
  fetchSubscriber,
  premiumFromSubscriber,
} from "../_shared/premium.mjs";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (request) => {
  const expectedAuth = Deno.env.get("REVENUECAT_WEBHOOK_AUTH");
  const secretKey = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!expectedAuth || !secretKey) {
    return json({ error: "RevenueCat secrets are not set" }, 500);
  }
  if (!authorizationMatches(request.headers.get("authorization"), expectedAuth)) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const userIDs = affectedUserIDs(body?.event);
  const results = await Promise.allSettled(userIDs.map(async (userID) => {
    const premium = premiumFromSubscriber(await fetchSubscriber(userID, secretKey));
    const { error } = await supabase.from("entitlements").upsert(entitlementRow(userID, premium));
    // Skips IDs that aren't Supabase users (e.g. RevenueCat test events).
    if (error && error.code !== "23503") throw new Error(error.message);
    return premium.isPremium;
  }));

  const failures = results.filter((result) => result.status === "rejected");
  if (failures.length > 0) {
    console.error("Entitlement sync failed", failures.map((failure) => String(failure.reason)));
    // A non-200 makes RevenueCat retry later.
    return json({ error: "Sync failed" }, 500);
  }
  return json({ synced: userIDs.length, type: body?.event?.type ?? null });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
