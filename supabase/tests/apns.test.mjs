// Tests for supabase/functions/send-push/apns.mjs. Run with: node --test supabase/tests/
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  apnsHost,
  base64url,
  importPrivateKey,
  isDeadToken,
  issuedAt,
  providerToken,
  sendAlert,
} from "../functions/send-push/apns.mjs";

/** A throwaway P-256 key, exported as a .p8-style PEM like Apple's. */
async function makeKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const base64 = btoa(String.fromCharCode(...der)).match(/.{1,64}/g).join("\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

function decode(part) {
  const base64 = part.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

test("provider token is a valid ES256 JWT for the team and key", async () => {
  const { pem, publicKey } = await makeKey();
  const jwt = await providerToken({ key: await importPrivateKey(pem), keyId: "ABC123DEFG", teamId: "LS942W7YC2", iat: 1_800_000_000 });

  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(new TextDecoder().decode(decode(header))), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(JSON.parse(new TextDecoder().decode(decode(claims))), { iss: "LS942W7YC2", iat: 1_800_000_000 });
  assert.equal(decode(signature).length, 64, "raw r‖s signature");
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    decode(signature),
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert.ok(valid, "signature verifies with the public key");
});

test("issue time stays fixed for 30 minutes", () => {
  assert.equal(issuedAt(1_800_000_000), 1_800_000_000);
  assert.equal(issuedAt(1_800_000_000 + 1799), 1_800_000_000);
  assert.equal(issuedAt(1_800_000_000 + 1800), 1_800_001_800);
});

test("base64url has no padding or unsafe characters", () => {
  assert.equal(base64url(new Uint8Array([251, 255, 191])), "-_-_");
  assert.equal(base64url(new Uint8Array([1])), "AQ");
});

test("sends to the right host with APNs headers and payload", async () => {
  let request;
  const fetchImpl = async (url, init) => {
    request = { url, init };
    return new Response(null, { status: 200 });
  };
  const result = await sendAlert({
    token: "abc", environment: "sandbox", bundleId: "com.abhaysingh.pawdone", jwt: "jwt",
    title: "Bruno", body: "Lunch is due now.", threadId: "pet-1", fetchImpl,
  });

  assert.deepEqual(result, { ok: true, status: 200 });
  assert.equal(request.url, "https://api.sandbox.push.apple.com/3/device/abc");
  assert.equal(request.init.headers.authorization, "bearer jwt");
  assert.equal(request.init.headers["apns-topic"], "com.abhaysingh.pawdone");
  assert.equal(request.init.headers["apns-push-type"], "alert");
  assert.deepEqual(JSON.parse(request.init.body), {
    aps: { alert: { title: "Bruno", body: "Lunch is due now." }, sound: "default", "thread-id": "pet-1" },
  });
  assert.equal(apnsHost("production"), "https://api.push.apple.com");
});

test("reports APNs failure reasons and spots dead tokens", async () => {
  const fail = (status, reason) => async () => new Response(JSON.stringify({ reason }), { status });
  const unregistered = await sendAlert({ token: "t", environment: "production", fetchImpl: fail(410, "Unregistered") });
  const badToken = await sendAlert({ token: "t", environment: "production", fetchImpl: fail(400, "BadDeviceToken") });
  const expired = await sendAlert({ token: "t", environment: "production", fetchImpl: fail(403, "ExpiredProviderToken") });

  assert.deepEqual(unregistered, { ok: false, status: 410, reason: "Unregistered" });
  assert.ok(isDeadToken(unregistered));
  assert.ok(isDeadToken(badToken));
  assert.ok(!isDeadToken(expired), "auth problems aren't the token's fault");
});
