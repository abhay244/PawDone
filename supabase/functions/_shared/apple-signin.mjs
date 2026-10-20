// Revokes a user's Sign in with Apple authorization when they delete their account, as
// Apple requires (TN3194). The app sends a fresh authorization code from re-authenticating;
// it's exchanged for a refresh token, which is then revoked.
// Web APIs only, so it runs in Deno and under Node for tests (supabase/tests/apple-signin.test.mjs).

import { signJWT } from "./es256.mjs";

const APPLE = "https://appleid.apple.com";

/** The client secret: an ES256 JWT signed with the Sign in with Apple key. Valid for 5 minutes. */
export function clientSecret({ key, keyId, teamId, clientId, nowSeconds = Math.floor(Date.now() / 1000) }) {
  return signJWT({
    key,
    keyId,
    claims: { iss: teamId, iat: nowSeconds, exp: nowSeconds + 300, aud: APPLE, sub: clientId },
  });
}

async function post(path, form, fetchImpl) {
  const response = await fetchImpl(`${APPLE}${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString(),
  });
  if (!response.ok) {
    let reason = String(response.status);
    try {
      reason = (await response.json()).error ?? reason;
    } catch {
      // Keep the status code.
    }
    throw new Error(`Apple ${path} failed: ${reason}`);
  }
  return response;
}

/** Exchanges the authorization code for tokens, then revokes the refresh token. */
export async function revokeAppleSignIn({ code, clientId, secret, fetchImpl = fetch }) {
  const tokens = await (await post("/auth/token", {
    client_id: clientId,
    client_secret: secret,
    code,
    grant_type: "authorization_code",
  }, fetchImpl)).json();

  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) throw new Error("Apple returned no token to revoke");

  await post("/auth/revoke", {
    client_id: clientId,
    client_secret: secret,
    token,
    token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
  }, fetchImpl);
}
