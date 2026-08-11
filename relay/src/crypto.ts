import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

export function sha256Base64Url(value: string | Buffer): string {
  return createHash("sha256").update(value).digest("base64url");
}

export function secureEqual(left: string, right: string): boolean {
  const a = Buffer.from(left, "utf8");
  const b = Buffer.from(right, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

export function proofCommitment(proof: string): string | null {
  if (!/^[A-Za-z0-9_-]{20,256}$/.test(proof)) return null;
  try {
    const bytes = Buffer.from(proof, "base64url");
    if (bytes.length < 16 || bytes.length > 128) return null;
    return sha256Base64Url(bytes);
  } catch {
    return null;
  }
}

export function pkcePair(): { verifier: string; challenge: string } {
  const verifier = randomToken(64);
  return { verifier, challenge: sha256Base64Url(verifier) };
}
