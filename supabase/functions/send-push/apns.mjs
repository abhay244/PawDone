// Apple Push Notification service (APNs) with token-based auth (.p8 key).
// Plain JavaScript and Web APIs only, so it runs in Supabase Edge Functions (Deno) and
// under Node for tests (supabase/tests/apns.test.mjs).

import { base64url, importPrivateKey, signJWT } from "../_shared/es256.mjs";

export { base64url, importPrivateKey };

/**
 * Apple rejects provider tokens refreshed more often than every 20 minutes and accepts
 * them for up to an hour, so the issue time is rounded down to a 30-minute window.
 * Every run in the same window then sends the same issue time.
 */
export function issuedAt(nowSeconds = Math.floor(Date.now() / 1000)) {
  return nowSeconds - (nowSeconds % 1800);
}

/** The provider token (an ES256 JWT) sent as `authorization: bearer …`. */
export function providerToken({ key, keyId, teamId, iat = issuedAt() }) {
  return signJWT({ key, keyId, claims: { iss: teamId, iat } });
}

export function apnsHost(environment) {
  return environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}

/** Sends one alert. Resolves to { ok, status, reason }. */
export async function sendAlert({ token, environment, bundleId, jwt, title, body, threadId, fetchImpl = fetch }) {
  const response = await fetchImpl(`${apnsHost(environment)}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", "thread-id": threadId } }),
  });
  if (response.ok) return { ok: true, status: response.status };

  let reason;
  try {
    reason = (await response.json()).reason;
  } catch {
    reason = undefined;
  }
  return { ok: false, status: response.status, reason };
}

/** True when APNs says a token will never work again, so it should be forgotten. */
export function isDeadToken(result) {
  return result.status === 410 || (result.status === 400 && result.reason === "BadDeviceToken");
}
