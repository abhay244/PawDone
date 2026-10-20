// ES256-signed JWTs with an Apple .p8 key, used for APNs provider tokens and Sign in
// with Apple client secrets. Web APIs only, so it runs in Deno and under Node for tests.

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

/** Signs `claims` as an ES256 JWT with key ID `keyId`. */
export async function signJWT({ key, keyId, claims }) {
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const payload = base64url(encoder.encode(JSON.stringify(claims)));
  const signingInput = `${header}.${payload}`;
  // WebCrypto returns the raw r‖s signature JWS expects for ES256.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}
