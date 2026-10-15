// Updates the signed-in user's Premium status straight from RevenueCat. The app calls
// this right after a purchase or restore, so Premium unlocks without waiting for the
// webhook.
//
// Secret: REVENUECAT_SECRET_KEY (see revenuecat-webhook).

import { createClient } from "npm:@supabase/supabase-js@2";
import { entitlementRow, fetchSubscriber, premiumFromSubscriber } from "../_shared/premium.mjs";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (request) => {
  const secretKey = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!secretKey) return json({ error: "RevenueCat secret is not set" }, 500);

  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data, error: authError } = await supabase.auth.getUser(token);
  if (authError || !data.user) return json({ error: "Not signed in" }, 401);

  try {
    const premium = premiumFromSubscriber(await fetchSubscriber(data.user.id, secretKey));
    const { error } = await supabase.from("entitlements").upsert(entitlementRow(data.user.id, premium));
    if (error) throw new Error(error.message);
    return json({ is_premium: premium.isPremium, expires_at: premium.expiresAt });
  } catch (error) {
    console.error("Premium sync failed", String(error));
    return json({ error: "Sync failed" }, 502);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
