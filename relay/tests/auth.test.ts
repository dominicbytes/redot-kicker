import assert from "node:assert/strict";
import test from "node:test";
import { NullLogger } from "../src/logger.js";
import { createRelayService } from "../src/server.js";
import { emptyRelayState, MemoryStateStore } from "../src/state.js";
import { authorize, jsonRequest, startMockKick, testConfig } from "./helpers.js";

test("broker owns OAuth state/PKCE and returns a single-use scoped session", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });

  const proof = Buffer.from("proof-for-negative-check").toString("base64url");
  const proofHash = Buffer.from(await crypto.subtle.digest("SHA-256", Buffer.from("proof-for-negative-check"))).toString("base64url");
  const begin = await jsonRequest(`${relay.baseUrl}/v1/auth/requests`, { method: "POST", body: {
    schema_version: 1,
    publisher_id: "fixture-publisher",
    application_id: "fixture-application",
    session_slot: "primary",
    capabilities: ["identity.read", "channel.read", "events.receive"],
    proof_sha256: proofHash,
  } });
  assert.equal(begin.status, 201);
  assert.match(String(begin.body.authorization_url), new RegExp(`^${relay.baseUrl.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}/`));
  assert.equal(JSON.stringify(begin.body).includes("code_verifier"), false);
  const browser = await fetch(String(begin.body.authorization_url), { redirect: "manual" });
  assert.equal(browser.status, 302);
  const upstreamUrl = new URL(String(browser.headers.get("location")));
  assert.equal(upstreamUrl.searchParams.get("client_id"), "fixture-kick-client");
  assert.equal(upstreamUrl.searchParams.get("code_challenge_method"), "S256");
  assert.ok(upstreamUrl.searchParams.get("code_challenge"));
  assert.deepEqual(String(upstreamUrl.searchParams.get("scope")).split(" ").sort(), ["channel:read", "events:subscribe", "user:read"]);

  const state = String(upstreamUrl.searchParams.get("state"));
  const callback = await fetch(`${relay.baseUrl}/v1/oauth/callback?code=fixture-code&state=${encodeURIComponent(state)}`);
  assert.equal(callback.status, 200);
  const wrong = await jsonRequest(`${relay.baseUrl}/v1/auth/requests/${begin.body.request_id}`, { headers: { "x-redot-kicker-proof": "wrong-proof" } });
  assert.equal(wrong.status, 401);
  const poll = await jsonRequest(`${relay.baseUrl}/v1/auth/requests/${begin.body.request_id}`, { headers: { "x-redot-kicker-proof": proof } });
  assert.equal(poll.status, 200);
  assert.ok(poll.body.broker_session);
  assert.equal(poll.body.session.application_id, "fixture-application");
  assert.equal(poll.body.session.channel.id, "123456789");
  assert.deepEqual(poll.body.session.granted_capabilities, ["channel.read", "events.receive", "identity.read"]);
  const serialized = JSON.stringify(poll.body);
  assert.doesNotMatch(serialized, /kick-access|kick-refresh|fixture-kick-secret|code_verifier/);
  const consumed = await jsonRequest(`${relay.baseUrl}/v1/auth/requests/${begin.body.request_id}`, { headers: { "x-redot-kicker-proof": proof } });
  assert.equal(consumed.status, 410);
});

test("restore and rotate invalidate the previous broker credential; revoke deletes server token state", async (t) => {
  const mock = await startMockKick();
  const store = new MemoryStateStore();
  const relay = createRelayService(testConfig(mock), store, new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["identity.read", "channel.read"]);
  const restored = await jsonRequest(`${relay.baseUrl}/v1/sessions/restore`, { method: "POST", headers: { authorization: `Broker ${connected.brokerSession}` }, body: { schema_version: 1, session_slot: "primary" } });
  assert.equal(restored.status, 200);
  assert.notEqual(restored.body.broker_session, connected.brokerSession);
  const oldDenied = await jsonRequest(`${relay.baseUrl}/v1/sessions/rotate`, { method: "POST", headers: { authorization: `Broker ${connected.brokerSession}` }, body: { schema_version: 1 } });
  assert.equal(oldDenied.status, 401);
  const rotated = await jsonRequest(`${relay.baseUrl}/v1/sessions/rotate`, { method: "POST", headers: { authorization: `Broker ${restored.body.broker_session}` }, body: { schema_version: 1 } });
  assert.equal(rotated.status, 200);
  assert.notEqual(rotated.body.broker_session, restored.body.broker_session);
  const partial = await jsonRequest(`${relay.baseUrl}/v1/sessions/revoke`, { method: "POST", headers: { authorization: `Broker ${rotated.body.broker_session}` }, body: { schema_version: 1, revoke_kick_authorization: false, delete_token_state: true } });
  assert.equal(partial.status, 400);
  assert.equal(store.snapshot().sessions.length, 1);
  const revoked = await jsonRequest(`${relay.baseUrl}/v1/sessions/revoke`, { method: "POST", headers: { authorization: `Broker ${rotated.body.broker_session}` }, body: { schema_version: 1, revoke_kick_authorization: true, delete_token_state: true } });
  assert.equal(revoked.status, 200);
  assert.equal(store.snapshot().sessions.length, 0);
  assert.equal(mock.requests.filter((request) => request.path === "/oauth/revoke").length, 2);
});

test("failed upstream revocation deletes local token state and reports a retryable pending condition", async (t) => {
  const mock = await startMockKick();
  mock.revokeStatus = 503;
  const store = new MemoryStateStore();
  const relay = createRelayService(testConfig(mock), store, new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["identity.read"]);
  const revoked = await jsonRequest(`${relay.baseUrl}/v1/sessions/revoke`, { method: "POST", headers: { authorization: `Broker ${connected.brokerSession}` }, body: { schema_version: 1, revoke_kick_authorization: true, delete_token_state: true } });
  assert.equal(revoked.status, 503);
  assert.equal(revoked.body.error.code, "remote_revocation_pending");
  assert.equal(revoked.body.error.retryable, true);
  assert.equal(store.snapshot().sessions.length, 0);
  assert.equal(store.snapshot().pendingRevocations.length, 1);
});

test("health is redacted and does not reveal deployment identifiers", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const health = await jsonRequest(`${relay.baseUrl}/v1/health`);
  assert.equal(health.status, 200);
  assert.equal(health.body.data.status, "healthy");
  assert.doesNotMatch(JSON.stringify(health.body), /fixture-(tenant|publisher|application|kick-secret)/);
  assert.equal(health.headers.get("cache-control"), "no-store");
});

test("startup removes and revokes a completed authorization result that expired before polling", async (t) => {
  const mock = await startMockKick();
  const now = Math.floor(Date.now() / 1000);
  const initial = emptyRelayState();
  initial.authRequests.push({
    id: "expired-auth",
    publisherId: "fixture-publisher",
    applicationId: "fixture-application",
    sessionSlot: "primary",
    capabilities: ["identity.read"],
    requestedScopes: ["user:read"],
    proofHash: "proof-hash",
    oauthState: "",
    pkceVerifier: "",
    status: "completed",
    sessionId: "expired-unclaimed-session",
    resultBrokerCredential: "encrypted-at-rest-unclaimed-credential",
    failureCode: "",
    createdAt: now - 600,
    expiresAt: now - 1,
  });
  initial.sessions.push({
    id: "expired-unclaimed-session",
    sessionSlot: "primary",
    publisherId: "fixture-publisher",
    applicationId: "fixture-application",
    userId: "123456789",
    username: "fixture-user",
    channelId: "123456789",
    channelSlug: "fixture-channel",
    capabilities: ["identity.read"],
    scopes: ["user:read"],
    brokerCredentialHash: "broker-hash",
    brokerExpiresAt: now + 3600,
    accessToken: "expired-unclaimed-access",
    refreshToken: "expired-unclaimed-refresh",
    tokenType: "Bearer",
    tokenExpiresAt: now + 3600,
    createdAt: now - 600,
    updatedAt: now - 600,
  });
  initial.idempotencyEntries.push({
    keyHash: "key-hash",
    sessionId: "expired-unclaimed-session",
    operationId: "chat.send",
    requestHash: "request-hash",
    status: "completed",
    responseStatus: 200,
    responseBody: { data: { ok: true } },
    responseHeaders: {},
    responseAvailable: true,
    responseBytes: 20,
    createdAt: now - 60,
    expiresAt: now + 3600,
  });
  const store = new MemoryStateStore(initial);
  const relay = createRelayService(testConfig(mock), store, new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  assert.equal(store.snapshot().authRequests.length, 0);
  assert.equal(store.snapshot().sessions.length, 0);
  assert.equal(store.snapshot().idempotencyEntries.length, 0);
});
