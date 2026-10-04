// Checks a signed request the way the app signs it (Sources/Domain/Leaderboard/
// RequestSigner.swift), over the exact bytes received. Pinned by test/vectors.json.

export const MAX_SKEW_SECONDS = 300;

export function base64UrlDecode(text: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) return null;
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (text.length % 4)) % 4);
  try {
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

async function sha256Hex(bytes: ArrayBuffer | Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function canonical(method: string, pathAndQuery: string, timestamp: string, nonce: string,
                                body: ArrayBuffer | Uint8Array): Promise<string> {
  return [method, pathAndQuery, timestamp, nonce, await sha256Hex(body)].join("\n");
}

/** A public key as `POST /join` sends it: 32 bytes, base64url. */
export const isPublicKey = (value: unknown): value is string =>
  typeof value === "string" && base64UrlDecode(value)?.length === 32;

export async function verify(publicKey: string, signature: string, message: string): Promise<boolean> {
  const keyBytes = base64UrlDecode(publicKey);
  const signatureBytes = base64UrlDecode(signature);
  if (keyBytes?.length !== 32 || signatureBytes?.length !== 64) return false;
  try {
    const key = await crypto.subtle.importKey("raw", keyBytes, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "Ed25519" }, key, signatureBytes, new TextEncoder().encode(message));
  } catch {
    return false;
  }
}

export const isFresh = (timestamp: string, now: number) =>
  /^\d{1,12}$/.test(timestamp) && Math.abs(Number(timestamp) - Math.floor(now / 1000)) <= MAX_SKEW_SECONDS;

export const isNonce = (nonce: string) => base64UrlDecode(nonce)?.length === 16;
