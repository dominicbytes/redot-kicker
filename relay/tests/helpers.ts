import { generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import type { RelayConfig } from "../src/config.js";
import type { RelayService } from "../src/server.js";

export interface CapturedRequest {
  method: string;
  path: string;
  query: URLSearchParams;
  headers: Record<string, string | string[] | undefined>;
  body: unknown;
  rawBody: string;
}

export interface MockKick {
  baseUrl: string;
  publicKeyPem: string;
  privateKeyPem: string;
  requests: CapturedRequest[];
  tokenScope: string;
  revokeStatus: number;
  close(): Promise<void>;
}

export async function startMockKick(): Promise<MockKick> {
  const keys = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
  });
  const requests: CapturedRequest[] = [];
  const model: MockKick = {
    baseUrl: "",
    publicKeyPem: keys.publicKey,
    privateKeyPem: keys.privateKey,
    requests,
    tokenScope: "user:read channel:read channel:write chat:write events:subscribe moderation:ban moderation:chat_message:manage channel:rewards:read channel:rewards:write kicks:read",
    revokeStatus: 200,
    close: async () => undefined,
  };
  const server = createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://mock.invalid");
    const bodyBytes = await readBody(request);
    const contentType = String(request.headers["content-type"] ?? "");
    let body: unknown = null;
    if (bodyBytes.length > 0) {
      if (contentType.includes("application/json")) body = JSON.parse(bodyBytes.toString("utf8"));
      else if (contentType.includes("application/x-www-form-urlencoded")) body = Object.fromEntries(new URLSearchParams(bodyBytes.toString("utf8")));
      else body = bodyBytes.toString("utf8");
    }
    requests.push({ method: request.method ?? "", path: url.pathname, query: url.searchParams, headers: request.headers, body, rawBody: bodyBytes.toString("utf8") });
    if (url.pathname === "/oauth/token") {
      const form = body as Record<string, string>;
      const refreshed = form.grant_type === "refresh_token";
      return sendJson(response, 200, {
        access_token: refreshed ? "kick-access-refreshed" : "kick-access-initial",
        refresh_token: refreshed ? "kick-refresh-refreshed" : "kick-refresh-initial",
        token_type: "Bearer",
        expires_in: refreshed ? 3600 : 30,
        scope: model.tokenScope,
      });
    }
    if (url.pathname === "/oauth/revoke") {
      response.writeHead(model.revokeStatus, { "content-type": "text/plain" });
      return response.end(model.revokeStatus === 200 ? "OK" : "Unavailable");
    }
    if (url.pathname === "/public/v1/public-key") {
      return sendJson(response, 200, { data: { public_key: keys.publicKey }, message: "OK" });
    }
    if (url.pathname === "/public/v1/users") {
      return sendJson(response, 200, { data: [{ user_id: 123456789, name: "fixture-user", email: "fixture@example.invalid", profile_picture: "https://cdn.example.invalid/user.png" }] });
    }
    if (url.pathname === "/public/v1/channels" && request.method === "GET") {
      return sendJson(response, 200, { data: [{ broadcaster_user_id: 123456789, slug: "fixture-channel", stream: { key: "never-forward", url: "rtmp://never-forward", is_live: true } }] });
    }
    if (url.pathname === "/public/v1/events/subscriptions" && request.method === "POST") {
      const source = body as { events?: Array<{ name?: string; version?: number }>; broadcaster_user_id?: number };
      const event = source.events?.[0] ?? { name: "chat.message.sent", version: 1 };
      return sendJson(response, 200, { data: [{ subscription_id: "01JTESTSUBSCRIPTION0000000001", name: event.name, version: event.version }] });
    }
    if (url.pathname === "/public/v1/events/subscriptions" && request.method === "GET") {
      return sendJson(response, 200, { data: [{ id: "01JTESTSUBSCRIPTION0000000001", event: "chat.message.sent", version: 1, broadcaster_user_id: 123456789, method: "webhook" }] });
    }
    if (url.pathname === "/public/v1/events/subscriptions" && request.method === "DELETE") {
      response.writeHead(204);
      return response.end();
    }
    if (url.pathname === "/public/v1/kicks/leaderboard") {
      response.writeHead(200, { "content-type": "application/json" });
      return response.end('{"data":[{"user_id":9007199254740993,"username":"large-id"}]}');
    }
    return sendJson(response, 200, {
      data: {
        ok: true,
        path: url.pathname,
        query: Object.fromEntries(url.searchParams),
        access_token: "must-be-stripped",
        stream: { key: "must-be-stripped", url: "rtmp://must-be-stripped", is_live: true },
      },
      message: "OK",
    }, { "x-ratelimit-remaining": "41", "x-ratelimit-reset": "1999999999", "retry-after": "2" });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  model.baseUrl = `http://127.0.0.1:${address.port}`;
  model.close = () => new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  return model;
}

export function testConfig(mock: MockKick): RelayConfig {
  return {
    host: "127.0.0.1",
    port: 0,
    publicBaseUrl: "http://127.0.0.1:0",
    tenantId: "fixture-tenant",
    publisherId: "fixture-publisher",
    applicationId: "fixture-application",
    kickClientId: "fixture-kick-client",
    kickClientSecret: "fixture-kick-secret",
    masterKey: randomBytes(32),
    stateFile: ":memory:",
    kickApiBaseUrl: mock.baseUrl,
    oauthAuthorizeUrl: `${mock.baseUrl}/oauth/authorize`,
    oauthTokenUrl: `${mock.baseUrl}/oauth/token`,
    oauthRevokeUrl: `${mock.baseUrl}/oauth/revoke`,
    authRequestTtlSeconds: 300,
    brokerSessionTtlSeconds: 3600,
    ticketTtlSeconds: 30,
    webhookFreshnessSeconds: 300,
    replayTtlSeconds: 3600,
    maxReplayEntries: 100,
    maxJsonBodyBytes: 1024 * 1024,
    maxWebhookBodyBytes: 256 * 1024,
    maxUpstreamBodyBytes: 8 * 1024 * 1024,
    maxSocketQueueEntries: 4,
    maxSocketPacketBytes: 256 * 1024,
    upstreamTimeoutMs: 5000,
    tokenRefreshSkewSeconds: 60,
    reconcileIntervalSeconds: 0,
    publicKeyPem: mock.publicKeyPem,
  };
}

export interface AuthorizedSession {
  brokerSession: string;
  descriptor: Record<string, unknown>;
  proof: string;
}

export async function authorize(relay: RelayService, capabilities: string[]): Promise<AuthorizedSession> {
  const proofBytes = randomBytes(32);
  const proof = proofBytes.toString("base64url");
  const proofHash = Buffer.from(await crypto.subtle.digest("SHA-256", proofBytes)).toString("base64url");
  const begin = await jsonRequest(`${relay.baseUrl}/v1/auth/requests`, {
    method: "POST",
    body: {
      schema_version: 1,
      publisher_id: "fixture-publisher",
      application_id: "fixture-application",
      session_slot: "primary",
      capabilities,
      proof_sha256: proofHash,
    },
  });
  if (begin.status !== 201) throw new Error(`authorization begin failed: ${begin.status} ${JSON.stringify(begin.body)}`);
  const requestId = String(begin.body.request_id);
  const browser = await fetch(String(begin.body.authorization_url), { redirect: "manual" });
  if (browser.status !== 302) throw new Error(`authorization redirect failed: ${browser.status}`);
  const kickLocation = new URL(String(browser.headers.get("location")));
  const state = String(kickLocation.searchParams.get("state"));
  const callback = await fetch(`${relay.baseUrl}/v1/oauth/callback?code=fixture-code&state=${encodeURIComponent(state)}`);
  if (callback.status !== 200) throw new Error(`authorization callback failed: ${callback.status}`);
  const polled = await jsonRequest(`${relay.baseUrl}/v1/auth/requests/${requestId}`, {
    method: "GET",
    headers: { "x-redot-kicker-proof": proof },
  });
  if (polled.status !== 200) throw new Error(`authorization poll failed: ${polled.status} ${JSON.stringify(polled.body)}`);
  return { brokerSession: String(polled.body.broker_session), descriptor: polled.body.session as Record<string, unknown>, proof };
}

export async function jsonRequest(url: string, options: { method?: string; headers?: Record<string, string>; body?: unknown } = {}): Promise<{ status: number; headers: Headers; body: Record<string, any> }> {
  const headers = { accept: "application/json", ...(options.body === undefined ? {} : { "content-type": "application/json" }), ...options.headers };
  const request: RequestInit = { method: options.method ?? "GET", headers };
  if (options.body !== undefined) request.body = JSON.stringify(options.body);
  const response = await fetch(url, request);
  const text = await response.text();
  return { status: response.status, headers: response.headers, body: text.length > 0 ? JSON.parse(text) : {} };
}

export function signedWebhook(mock: MockKick, body: Buffer, overrides: Partial<Record<string, string>> = {}): Record<string, string> {
  const messageId = overrides["Kick-Event-Message-Id"] ?? "01JTESTMESSAGE000000000000001";
  const timestamp = overrides["Kick-Event-Message-Timestamp"] ?? new Date().toISOString();
  const signed = Buffer.concat([Buffer.from(`${messageId}.${timestamp}.`, "utf8"), body]);
  const signature = sign("RSA-SHA256", signed, mock.privateKeyPem).toString("base64");
  return {
    "content-type": "application/json",
    "Kick-Event-Message-Id": messageId,
    "Kick-Event-Subscription-Id": "01JTESTSUBSCRIPTION0000000001",
    "Kick-Event-Signature": signature,
    "Kick-Event-Message-Timestamp": timestamp,
    "Kick-Event-Type": "chat.message.sent",
    "Kick-Event-Version": "1",
    ...overrides,
  };
}

function sendJson(response: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}): void {
  response.writeHead(status, { "content-type": "application/json", ...headers });
  response.end(JSON.stringify(body));
}

function readBody(request: IncomingMessage): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks)));
    request.on("error", reject);
  });
}
