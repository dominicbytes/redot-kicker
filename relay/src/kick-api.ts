import { createRequire } from "node:module";
import type { RelayConfig } from "./config.js";
import type { OperationContract } from "./contracts.js";
import { HttpError } from "./errors.js";
import { isRecord } from "./sanitizer.js";
import type { SessionRecord } from "./state.js";

interface JsonBigParser {
  parse(source: string): unknown;
  stringify(value: unknown): string;
}

const require = createRequire(import.meta.url);
const jsonBigFactory = require("json-bigint") as (options: Record<string, boolean>) => JsonBigParser;
const jsonBig = jsonBigFactory({ storeAsString: true, strict: true });
const jsonBigNative = jsonBigFactory({ useNativeBigInt: true, strict: true });

export interface TokenGrant {
  accessToken: string;
  refreshToken: string;
  tokenType: string;
  expiresAt: number;
  scopes: string[];
}

export interface KickIdentity {
  userId: string;
  username: string;
  channelId: string;
  channelSlug: string;
}

export interface UpstreamResult {
  status: number;
  body: unknown;
  headers: Record<string, string>;
}

export class KickApiClient {
  private readonly config: RelayConfig;

  constructor(config: RelayConfig) {
    this.config = config;
  }

  async exchangeCode(code: string, verifier: string, redirectUri: string): Promise<TokenGrant> {
    return this.tokenRequest(new URLSearchParams({
      grant_type: "authorization_code",
      client_id: this.config.kickClientId,
      client_secret: this.config.kickClientSecret,
      redirect_uri: redirectUri,
      code_verifier: verifier,
      code,
    }));
  }

  async refresh(refreshToken: string): Promise<TokenGrant> {
    return this.tokenRequest(new URLSearchParams({
      grant_type: "refresh_token",
      client_id: this.config.kickClientId,
      client_secret: this.config.kickClientSecret,
      refresh_token: refreshToken,
    }));
  }

  async revoke(token: string, hint: "access_token" | "refresh_token"): Promise<boolean> {
    if (!token) return true;
    const url = new URL(this.config.oauthRevokeUrl);
    url.searchParams.set("token", token);
    url.searchParams.set("token_hint_type", hint);
    try {
      const response = await fetch(url, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" }, signal: AbortSignal.timeout(this.config.upstreamTimeoutMs) });
      await consumeLimited(response, 16_384);
      return response.ok;
    } catch {
      return false;
    }
  }

  async resolveIdentity(accessToken: string): Promise<KickIdentity> {
    const users = await this.rawApiRequest("GET", new URL("/public/v1/users", this.config.kickApiBaseUrl), accessToken);
    if (users.status < 200 || users.status >= 300) throw new HttpError(502, "identity_upstream", "Kick did not return the authorized user", true);
    const user = firstDataRecord(users.body);
    const channels = await this.rawApiRequest("GET", new URL("/public/v1/channels", this.config.kickApiBaseUrl), accessToken);
    if (channels.status < 200 || channels.status >= 300) throw new HttpError(502, "channel_upstream", "Kick did not return the authorized channel", true);
    const channel = firstDataRecord(channels.body);
    const userId = identifier(user.user_id ?? user.id);
    const channelId = identifier(channel.broadcaster_user_id ?? channel.user_id ?? userId);
    const username = stringValue(user.name ?? user.username);
    const channelSlug = stringValue(channel.slug ?? user.channel_slug ?? username);
    if (!userId || !channelId || !username || !channelSlug) throw new HttpError(502, "identity_protocol", "Kick returned an incomplete account identity");
    return { userId, username, channelId, channelSlug };
  }

  async loadPublicKey(): Promise<string> {
    const response = await this.rawApiRequest("GET", new URL("/public/v1/public-key", this.config.kickApiBaseUrl), "");
    if (response.status < 200 || response.status >= 300) throw new HttpError(503, "public_key_unavailable", "Kick webhook public key is unavailable", true);
    const root = isRecord(response.body) ? response.body : {};
    const data = isRecord(root.data) ? root.data : root;
    const key = stringValue(data.public_key ?? data.key);
    if (!key.includes("BEGIN PUBLIC KEY")) throw new HttpError(503, "public_key_invalid", "Kick webhook public key response is invalid", true);
    return key;
  }

  async invoke(session: SessionRecord, contract: OperationContract, query: Record<string, unknown>, pathParameters: Record<string, unknown>, body: Record<string, unknown>): Promise<UpstreamResult> {
    let path = contract.path;
    for (const name of [...path.matchAll(/\{([A-Za-z0-9_]+)\}/g)].map((match) => match[1])) {
      if (!name) continue;
      const value = scalar(pathParameters[name]);
      if (!value) throw new HttpError(400, "path_parameter_missing", `Required path parameter is missing: ${name}`);
      path = path.replace(`{${name}}`, encodeURIComponent(value));
    }
    if (path.includes("{") || !path.startsWith("/")) throw new HttpError(400, "operation_unavailable", "Kick operation has no callable route");
    const url = new URL(path, this.config.kickApiBaseUrl);
    appendQuery(url, query);
    const headers: Record<string, string> = { accept: "application/json" };
    if (contract.id !== "public_key.get") headers.authorization = `${session.tokenType || "Bearer"} ${session.accessToken}`;
    const init: RequestInit = { method: contract.method, headers, signal: AbortSignal.timeout(this.config.upstreamTimeoutMs) };
    const sendBody = contract.body ?? (contract.method === "POST" || contract.method === "PATCH");
    if (sendBody) {
      headers["content-type"] = "application/json";
      init.body = jsonBigNative.stringify(normalizeNumericIdentifiers(body));
    }
    const response = await fetch(url, init);
    const text = await consumeLimited(response, this.config.maxUpstreamBodyBytes);
    return { status: response.status, body: parseMaybeJson(text, response.headers.get("content-type")), headers: selectedHeaders(response.headers) };
  }

  private async tokenRequest(form: URLSearchParams): Promise<TokenGrant> {
    let response: Response;
    try {
      response = await fetch(this.config.oauthTokenUrl, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" }, body: form, signal: AbortSignal.timeout(this.config.upstreamTimeoutMs) });
    } catch {
      throw new HttpError(503, "oauth_unavailable", "Kick authorization service is unavailable", true);
    }
    const text = await consumeLimited(response, 1_048_576);
    const source = parseMaybeJson(text, response.headers.get("content-type"));
    if (!response.ok || !isRecord(source)) throw new HttpError(502, "oauth_exchange_failed", "Kick did not accept the authorization exchange");
    const accessToken = stringValue(source.access_token);
    const refreshToken = stringValue(source.refresh_token);
    const tokenType = stringValue(source.token_type) || "Bearer";
    const expiresIn = Number(source.expires_in);
    const scopes = normalizeScopes(source.scope);
    if (!accessToken || !refreshToken || !Number.isFinite(expiresIn) || expiresIn <= 0 || scopes.length === 0) throw new HttpError(502, "oauth_protocol", "Kick returned an incomplete token grant");
    return { accessToken, refreshToken, tokenType, expiresAt: Math.floor(Date.now() / 1000) + Math.floor(expiresIn), scopes };
  }

  private async rawApiRequest(method: string, url: URL, accessToken: string): Promise<UpstreamResult> {
    const headers: Record<string, string> = { accept: "application/json" };
    if (accessToken) headers.authorization = `Bearer ${accessToken}`;
    let response: Response;
    try { response = await fetch(url, { method, headers, signal: AbortSignal.timeout(this.config.upstreamTimeoutMs) }); }
    catch { throw new HttpError(503, "kick_api_unavailable", "Kick API is unavailable", true); }
    const text = await consumeLimited(response, this.config.maxUpstreamBodyBytes);
    return { status: response.status, body: parseMaybeJson(text, response.headers.get("content-type")), headers: selectedHeaders(response.headers) };
  }
}

async function consumeLimited(response: Response, limit: number): Promise<string> {
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const part = await reader.read();
    if (part.done) break;
    size += part.value.byteLength;
    if (size > limit) {
      await reader.cancel();
      throw new HttpError(502, "upstream_body_too_large", "Kick response exceeded the relay limit");
    }
    chunks.push(part.value);
  }
  return Buffer.concat(chunks.map((chunk) => Buffer.from(chunk))).toString("utf8");
}

function parseMaybeJson(text: string, contentType: string | null): unknown {
  if (!text) return null;
  if (contentType?.toLowerCase().includes("json") || /^[\s]*[\[{]/.test(text)) {
    try { return jsonBig.parse(text); } catch { throw new HttpError(502, "upstream_json_invalid", "Kick returned malformed JSON"); }
  }
  return text;
}

function firstDataRecord(value: unknown): Record<string, unknown> {
  const root = isRecord(value) ? value : {};
  const data = root.data;
  if (Array.isArray(data) && isRecord(data[0])) return data[0];
  if (isRecord(data)) return data;
  throw new HttpError(502, "upstream_protocol", "Kick response did not contain the expected data");
}

function normalizeScopes(value: unknown): string[] {
  const source = Array.isArray(value) ? value.map(String) : stringValue(value).split(/[\s,]+/);
  return [...new Set(source.map((item) => item.trim()).filter(Boolean))].sort();
}

function identifier(value: unknown): string {
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isSafeInteger(value)) return String(value);
  if (typeof value === "bigint") return value.toString();
  return "";
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function scalar(value: unknown): string {
  if (typeof value === "string") return value.length <= 512 ? value : "";
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  return "";
}

function appendQuery(url: URL, query: Record<string, unknown>): void {
  const entries = Object.entries(query);
  if (entries.length > 64) throw new HttpError(400, "query_too_large", "Too many Kick query parameters");
  for (const [key, value] of entries) {
    if (!/^[A-Za-z0-9_.-]{1,128}$/.test(key)) throw new HttpError(400, "query_invalid", "Kick query parameter name is invalid");
    const values = Array.isArray(value) ? value : [value];
    if (values.length > 100) throw new HttpError(400, "query_too_large", "Kick query parameter has too many values");
    for (const item of values) {
      const encoded = scalar(item);
      if (!encoded && item !== "") throw new HttpError(400, "query_invalid", "Kick query parameter must be scalar");
      url.searchParams.append(key, encoded);
    }
  }
}

function selectedHeaders(headers: Headers): Record<string, string> {
  const result: Record<string, string> = {};
  for (const name of ["x-request-id", "x-ratelimit-remaining", "x-ratelimit-reset", "retry-after"]) {
    const value = headers.get(name);
    if (value !== null && value.length <= 256) result[name] = value;
  }
  return result;
}

function normalizeNumericIdentifiers(value: unknown, key = ""): unknown {
  if (Array.isArray(value)) return value.map((item) => normalizeNumericIdentifiers(item, key));
  if (isRecord(value)) return Object.fromEntries(Object.entries(value).map(([childKey, item]) => [childKey, normalizeNumericIdentifiers(item, childKey)]));
  if ((key === "broadcaster_user_id" || key === "user_id") && typeof value === "string" && /^[0-9]{1,20}$/.test(value)) return BigInt(value);
  return value;
}
