const SECRET_KEYS = new Set([
  "access_token",
  "authorization",
  "broker_session",
  "client_secret",
  "code_verifier",
  "refresh_token",
  "session_credential",
  "stream_key",
  "token",
]);

export function sanitizeForClient(value: unknown, parentKey = "", depth = 0): unknown {
  if (depth > 32) return null;
  if (Array.isArray(value)) return value.map((item) => sanitizeForClient(item, parentKey, depth + 1));
  if (isRecord(value)) {
    const output: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value)) {
      const normalized = key.toLowerCase();
      if (SECRET_KEYS.has(normalized)) continue;
      if (parentKey === "stream" && (normalized === "key" || normalized === "url")) continue;
      output[key] = sanitizeForClient(item, normalized, depth + 1);
    }
    return output;
  }
  return value;
}

export function containsSecretField(value: unknown, depth = 0): boolean {
  if (depth > 32) return true;
  if (Array.isArray(value)) return value.some((item) => containsSecretField(item, depth + 1));
  if (!isRecord(value)) return false;
  return Object.entries(value).some(([key, item]) => SECRET_KEYS.has(key.toLowerCase()) || containsSecretField(item, depth + 1));
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
