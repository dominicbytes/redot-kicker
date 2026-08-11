import { readFile } from "node:fs/promises";

export interface RelayConfig {
  host: string;
  port: number;
  publicBaseUrl: string;
  tenantId: string;
  publisherId: string;
  applicationId: string;
  kickClientId: string;
  kickClientSecret: string;
  masterKey: Buffer;
  stateFile: string;
  kickApiBaseUrl: string;
  oauthAuthorizeUrl: string;
  oauthTokenUrl: string;
  oauthRevokeUrl: string;
  authRequestTtlSeconds: number;
  brokerSessionTtlSeconds: number;
  ticketTtlSeconds: number;
  webhookFreshnessSeconds: number;
  replayTtlSeconds: number;
  maxReplayEntries: number;
  maxJsonBodyBytes: number;
  maxWebhookBodyBytes: number;
  maxUpstreamBodyBytes: number;
  maxSocketQueueEntries: number;
  maxSocketPacketBytes: number;
  upstreamTimeoutMs: number;
  tokenRefreshSkewSeconds: number;
  reconcileIntervalSeconds: number;
  publicKeyPem: string;
}

export async function loadRelayConfig(environment: NodeJS.ProcessEnv = process.env): Promise<RelayConfig> {
  rejectInlineSecret(environment, "REDOT_KICKER_CLIENT_SECRET");
  rejectInlineSecret(environment, "REDOT_KICKER_MASTER_KEY");
  const clientSecretPath = required(environment, "REDOT_KICKER_CLIENT_SECRET_FILE");
  const masterKeyPath = required(environment, "REDOT_KICKER_MASTER_KEY_FILE");
  const publicKeyPath = environment.REDOT_KICKER_PUBLIC_KEY_FILE?.trim() ?? "";
  const config: RelayConfig = {
    host: environment.REDOT_KICKER_HOST?.trim() || "0.0.0.0",
    port: integer(environment.REDOT_KICKER_PORT, 8080, 1, 65535, "REDOT_KICKER_PORT"),
    publicBaseUrl: required(environment, "REDOT_KICKER_PUBLIC_BASE_URL").replace(/\/$/, ""),
    tenantId: required(environment, "REDOT_KICKER_TENANT_ID"),
    publisherId: required(environment, "REDOT_KICKER_PUBLISHER_ID"),
    applicationId: required(environment, "REDOT_KICKER_APPLICATION_ID"),
    kickClientId: required(environment, "REDOT_KICKER_KICK_CLIENT_ID"),
    kickClientSecret: await readSecret(clientSecretPath),
    masterKey: decodeMasterKey(await readSecret(masterKeyPath)),
    stateFile: environment.REDOT_KICKER_STATE_FILE?.trim() || "/var/lib/redot-kicker/state.enc",
    kickApiBaseUrl: "https://api.kick.com",
    oauthAuthorizeUrl: "https://id.kick.com/oauth/authorize",
    oauthTokenUrl: "https://id.kick.com/oauth/token",
    oauthRevokeUrl: "https://id.kick.com/oauth/revoke",
    authRequestTtlSeconds: integer(environment.REDOT_KICKER_AUTH_REQUEST_TTL_SECONDS, 300, 60, 900, "REDOT_KICKER_AUTH_REQUEST_TTL_SECONDS"),
    brokerSessionTtlSeconds: integer(environment.REDOT_KICKER_SESSION_TTL_SECONDS, 2_592_000, 3600, 7_776_000, "REDOT_KICKER_SESSION_TTL_SECONDS"),
    ticketTtlSeconds: integer(environment.REDOT_KICKER_TICKET_TTL_SECONDS, 30, 5, 120, "REDOT_KICKER_TICKET_TTL_SECONDS"),
    webhookFreshnessSeconds: integer(environment.REDOT_KICKER_WEBHOOK_FRESHNESS_SECONDS, 300, 30, 900, "REDOT_KICKER_WEBHOOK_FRESHNESS_SECONDS"),
    replayTtlSeconds: integer(environment.REDOT_KICKER_REPLAY_TTL_SECONDS, 3600, 300, 86_400, "REDOT_KICKER_REPLAY_TTL_SECONDS"),
    maxReplayEntries: integer(environment.REDOT_KICKER_MAX_REPLAY_ENTRIES, 50_000, 100, 1_000_000, "REDOT_KICKER_MAX_REPLAY_ENTRIES"),
    maxJsonBodyBytes: integer(environment.REDOT_KICKER_MAX_JSON_BYTES, 1_048_576, 1024, 2_097_152, "REDOT_KICKER_MAX_JSON_BYTES"),
    maxWebhookBodyBytes: integer(environment.REDOT_KICKER_MAX_WEBHOOK_BYTES, 262_144, 1024, 1_048_576, "REDOT_KICKER_MAX_WEBHOOK_BYTES"),
    maxUpstreamBodyBytes: integer(environment.REDOT_KICKER_MAX_UPSTREAM_BYTES, 8_388_608, 1024, 16_777_216, "REDOT_KICKER_MAX_UPSTREAM_BYTES"),
    maxSocketQueueEntries: integer(environment.REDOT_KICKER_MAX_SOCKET_QUEUE, 256, 1, 4096, "REDOT_KICKER_MAX_SOCKET_QUEUE"),
    maxSocketPacketBytes: integer(environment.REDOT_KICKER_MAX_SOCKET_PACKET_BYTES, 262_144, 1024, 1_048_576, "REDOT_KICKER_MAX_SOCKET_PACKET_BYTES"),
    upstreamTimeoutMs: integer(environment.REDOT_KICKER_UPSTREAM_TIMEOUT_MS, 20_000, 1000, 120_000, "REDOT_KICKER_UPSTREAM_TIMEOUT_MS"),
    tokenRefreshSkewSeconds: integer(environment.REDOT_KICKER_TOKEN_REFRESH_SKEW_SECONDS, 60, 0, 600, "REDOT_KICKER_TOKEN_REFRESH_SKEW_SECONDS"),
    reconcileIntervalSeconds: integer(environment.REDOT_KICKER_RECONCILE_SECONDS, 300, 0, 3600, "REDOT_KICKER_RECONCILE_SECONDS"),
    publicKeyPem: publicKeyPath ? await readSecret(publicKeyPath) : "",
  };
  validateRelayConfig(config);
  return config;
}

export function validateRelayConfig(config: RelayConfig): void {
  for (const [name, value] of [["tenantId", config.tenantId], ["publisherId", config.publisherId], ["applicationId", config.applicationId]] as const) {
    if (!/^[A-Za-z0-9._-]{1,128}$/.test(value)) throw new Error(`${name} must contain only letters, digits, dot, underscore, and hyphen`);
  }
  if (config.kickClientId.length < 1 || config.kickClientId.length > 512) throw new Error("kickClientId is invalid");
  if (config.kickClientSecret.length < 1 || config.kickClientSecret.length > 4096) throw new Error("Kick client secret file is empty or too large");
  if (config.masterKey.length !== 32) throw new Error("Master key must decode to exactly 32 bytes");
  validateEndpoint(config.publicBaseUrl, true, "publicBaseUrl");
  validateEndpoint(config.kickApiBaseUrl, true, "kickApiBaseUrl");
  validateEndpoint(config.oauthAuthorizeUrl, true, "oauthAuthorizeUrl");
  validateEndpoint(config.oauthTokenUrl, true, "oauthTokenUrl");
  validateEndpoint(config.oauthRevokeUrl, true, "oauthRevokeUrl");
  if (!config.stateFile && process.env.NODE_ENV !== "test") throw new Error("stateFile is required outside tests");
}

function validateEndpoint(value: string, allowLoopback: boolean, name: string): void {
  let url: URL;
  try { url = new URL(value); } catch { throw new Error(`${name} must be an absolute URL`); }
  const loopback = url.hostname === "127.0.0.1" || url.hostname === "localhost" || url.hostname === "::1";
  if (url.protocol !== "https:" && !(allowLoopback && loopback && url.protocol === "http:")) throw new Error(`${name} must use HTTPS or loopback HTTP`);
  if (url.username || url.password || url.hash) throw new Error(`${name} must not contain credentials or fragments`);
}

async function readSecret(path: string): Promise<string> {
  const value = (await readFile(path, "utf8")).replace(/[\r\n]+$/, "");
  if (!value) throw new Error(`Secret file is empty: ${path}`);
  return value;
}

function decodeMasterKey(value: string): Buffer {
  if (/^[0-9a-fA-F]{64}$/.test(value)) return Buffer.from(value, "hex");
  try { return Buffer.from(value, "base64url"); } catch { throw new Error("Master key must be base64url or 64 hexadecimal characters"); }
}

function rejectInlineSecret(environment: NodeJS.ProcessEnv, name: string): void {
  if (environment[name]) throw new Error(`${name} is rejected; mount a secret file and provide its path instead`);
}

function required(environment: NodeJS.ProcessEnv, name: string): string {
  const value = environment[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function integer(source: string | undefined, fallback: number, minimum: number, maximum: number, name: string): number {
  if (source === undefined || source.trim() === "") return fallback;
  const value = Number(source);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new Error(`${name} must be an integer from ${minimum} through ${maximum}`);
  return value;
}
