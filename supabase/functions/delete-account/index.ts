// Permanently deletes the signed-in user's account (App Store guideline 5.1.1(v)).
//   1. Finds their proof photos and detaches the ones in other households.
//   2. Deletes those photos from Storage.
//   3. Revokes their Sign in with Apple authorization, if they used it (Apple TN3194).
//   4. Deletes their RevenueCat customer data. App Store subscriptions are cancelled by
//      the user in Settings, not here.
//   5. Deletes the auth user, which cascades to all their rows.
// Steps 3 and 4 are best effort: a failure is logged but doesn't stop the deletion.
// If step 1, 2 or 5 fails it stops, so the request can be retried.
//
// Request body (optional): { "apple_authorization_code": "…" } from re-authenticating.
// Secrets for step 3: APPLE_SIGNIN_KEY_ID, APPLE_SIGNIN_PRIVATE_KEY (a .p8 key with
// Sign in with Apple enabled), APPLE_TEAM_ID (falls back to APNS_TEAM_ID),
// APPLE_CLIENT_ID (defaults to com.abhaysingh.pawdone).

import { createClient } from "npm:@supabase/supabase-js@2";
import { clientSecret, revokeAppleSignIn } from "../_shared/apple-signin.mjs";
import { importPrivateKey } from "../_shared/es256.mjs";
import { deleteSubscriber } from "../_shared/premium.mjs";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (request) => {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data, error: authError } = await supabase.auth.getUser(token);
  if (authError || !data.user) return json({ error: "Not signed in" }, 401);
  const user = data.user;

  let appleCode: string | undefined;
  try {
    appleCode = (await request.json())?.apple_authorization_code ?? undefined;
  } catch {
    // No body.
  }

  const { data: paths, error: prepareError } = await supabase.rpc("prepare_account_deletion", { p_user_id: user.id });
  if (prepareError) return failed("prepare", prepareError.message);

  const photoPaths = (paths ?? []) as string[];
  for (let start = 0; start < photoPaths.length; start += 1000) {
    const { error } = await supabase.storage.from("proof-photos").remove(photoPaths.slice(start, start + 1000));
    if (error) return failed("photos", error.message);
  }

  const usedApple = user.identities?.some((identity) => identity.provider === "apple") ?? false;
  const appleRevoked = usedApple ? await revokeApple(appleCode) : null;

  const revenueCatKey = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (revenueCatKey) {
    try {
      await deleteSubscriber(user.id, revenueCatKey);
    } catch (error) {
      console.error("RevenueCat customer not deleted", String(error));
    }
  }

  const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);
  if (deleteError) return failed("user", deleteError.message);

  return json({ deleted: true, photos: photoPaths.length, apple_revoked: appleRevoked });
});

/** Returns whether the Apple authorization was revoked. */
async function revokeApple(code: string | undefined): Promise<boolean> {
  const keyId = Deno.env.get("APPLE_SIGNIN_KEY_ID");
  const privateKey = Deno.env.get("APPLE_SIGNIN_PRIVATE_KEY");
  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? Deno.env.get("APNS_TEAM_ID");
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? "com.abhaysingh.pawdone";

  if (!code) {
    console.error("Sign in with Apple not revoked: the app sent no authorization code");
    return false;
  }
  if (!keyId || !privateKey || !teamId) {
    console.error("Sign in with Apple not revoked: APPLE_SIGNIN_* secrets are not set");
    return false;
  }
  try {
    const secret = await clientSecret({ key: await importPrivateKey(privateKey), keyId, teamId, clientId });
    await revokeAppleSignIn({ code, clientId, secret });
    return true;
  } catch (error) {
    console.error("Sign in with Apple not revoked", String(error));
    return false;
  }
}

function failed(step: string, message: string) {
  console.error(`Account deletion failed at ${step}`, message);
  return json({ error: "Deletion failed" }, 500);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
