// Sends due task reminders and "task done" alerts through APNs.
// Called every minute by pg_cron (see migrations/20261015000002_schedule_push.sql).
//
// Secrets (Supabase dashboard → Edge Functions → Secrets):
//   APNS_KEY_ID       Key ID of the APNs auth key
//   APNS_TEAM_ID      Apple Developer Team ID
//   APNS_PRIVATE_KEY  Contents of the AuthKey_XXXXXXXXXX.p8 file
//   APNS_BUNDLE_ID    Optional, defaults to com.abhaysingh.pawdone
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPrivateKey, isDeadToken, providerToken, sendAlert } from "./apns.mjs";

type Push = {
  kind: "reminder" | "completed";
  token: string;
  environment: "sandbox" | "production";
  title: string;
  body: string;
  thread_id: string;
};

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async () => {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.abhaysingh.pawdone";

  // Check before claiming, so nothing is marked sent while APNs isn't set up.
  if (!keyId || !teamId || !privateKey) {
    return json({ error: "APNs secrets are not set" }, 500);
  }

  const { data, error } = await supabase.rpc("claim_push_notifications");
  if (error) return json({ error: error.message }, 500);

  const pushes = (data ?? []) as Push[];
  if (pushes.length === 0) return json({ sent: 0 });

  const jwt = await providerToken({ key: await importPrivateKey(privateKey), keyId, teamId });
  const results = await Promise.all(
    pushes.map((push) =>
      sendAlert({
        token: push.token,
        environment: push.environment,
        bundleId,
        jwt,
        title: push.title,
        body: push.body,
        threadId: push.thread_id,
      })
    ),
  );

  const deadTokens = pushes.filter((_, index) => isDeadToken(results[index])).map((push) => push.token);
  if (deadTokens.length > 0) {
    await supabase.rpc("forget_push_tokens", { p_tokens: deadTokens });
  }

  const failures = results.filter((result) => !result.ok);
  if (failures.length > 0) console.error("APNs failures", failures);

  return json({
    sent: results.length - failures.length,
    failed: failures.map((result) => result.reason ?? result.status),
    forgotten: deadTokens.length,
  });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
