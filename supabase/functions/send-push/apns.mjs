// Apple Push Notification service (APNs) with token-based auth (.p8 key).
// Plain JavaScript and Web APIs only, so it runs in Supabase Edge Functions (Deno) and
// under Node for tests (supabase/tests/apns.test.mjs).

const encoder = new TextEncoder();

export function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** Imports the contents of an AuthKey_XXXXXXXXXX.p8 file. */
export async function importPrivateKey(pem) {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/**
 * Apple rejects provider tokens refreshed more often than every 20 minutes and accepts
 * them for up to an hour, so the issue time is rounded down to a 30-minute window.
 * Every run in the same window then sends the same issue time.
 */
export function issuedAt(nowSeconds = Math.floor(Date.now() / 1000)) {
  return nowSeconds - (nowSeconds % 1800);
}

/** The provider token (an ES256 JWT) sent as `authorization: bearer …`. */
export async function providerToken({ key, keyId, teamId, iat = issuedAt() }) {
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: teamId, iat })));
  const signingInput = `${header}.${claims}`;
  // WebCrypto returns the raw r‖s signature JWS expects for ES256.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
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
