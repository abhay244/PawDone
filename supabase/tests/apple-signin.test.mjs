// Tests for supabase/functions/_shared/apple-signin.mjs. Run with: node --test supabase/tests/
import assert from "node:assert/strict";
import { test } from "node:test";
import { clientSecret, revokeAppleSignIn } from "../functions/_shared/apple-signin.mjs";
import { importPrivateKey } from "../functions/_shared/es256.mjs";

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

test("client secret is a signed JWT for Apple's audience", async () => {
  const { pem, publicKey } = await makeKey();
  const secret = await clientSecret({
    key: await importPrivateKey(pem), keyId: "SIWA123456", teamId: "LS942W7YC2",
    clientId: "com.abhaysingh.pawdone", nowSeconds: 1_800_000_000,
  });

  const [header, claims, signature] = secret.split(".");
  assert.deepEqual(JSON.parse(new TextDecoder().decode(decode(header))), { alg: "ES256", kid: "SIWA123456" });
  assert.deepEqual(JSON.parse(new TextDecoder().decode(decode(claims))), {
    iss: "LS942W7YC2", iat: 1_800_000_000, exp: 1_800_000_300,
    aud: "https://appleid.apple.com", sub: "com.abhaysingh.pawdone",
  });
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, publicKey, decode(signature), new TextEncoder().encode(`${header}.${claims}`),
  );
  assert.ok(valid);
});

test("exchanges the code, then revokes the refresh token", async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, form: Object.fromEntries(new URLSearchParams(init.body)) });
    return url.endsWith("/auth/token")
      ? new Response(JSON.stringify({ access_token: "a", refresh_token: "r" }), { status: 200 })
      : new Response("", { status: 200 });
  };
  await revokeAppleSignIn({ code: "c0de", clientId: "com.abhaysingh.pawdone", secret: "s", fetchImpl });

  assert.equal(calls[0].url, "https://appleid.apple.com/auth/token");
  assert.deepEqual(calls[0].form, {
    client_id: "com.abhaysingh.pawdone", client_secret: "s", code: "c0de", grant_type: "authorization_code",
  });
  assert.equal(calls[1].url, "https://appleid.apple.com/auth/revoke");
  assert.deepEqual(calls[1].form, {
    client_id: "com.abhaysingh.pawdone", client_secret: "s", token: "r", token_type_hint: "refresh_token",
  });
});

test("reports Apple's error", async () => {
  const fetchImpl = async () => new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
  await assert.rejects(
    revokeAppleSignIn({ code: "old", clientId: "x", secret: "s", fetchImpl }),
    /invalid_grant/,
  );
});
