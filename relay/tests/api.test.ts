import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { NullLogger } from "../src/logger.js";
import { createRelayService } from "../src/server.js";
import { EncryptedFileStateStore, MemoryStateStore } from "../src/state.js";
import { authorize, jsonRequest, startMockKick, testConfig } from "./helpers.js";

test("allowlisted API proxy enforces capability, confirmation, path, query, refresh, and sanitization", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["categories.read", "channel.manage", "identity.read"]);
  const auth = { authorization: `Broker ${connected.brokerSession}` };

  const category = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/categories.search.v2`, { method: "POST", headers: auth, body: {
    schema_version: 1,
    query: { q: "redot", page: 2, tags: ["a", "b"] },
    path_parameters: {},
    body: {},
    confirmed: false,
  } });
  assert.equal(category.status, 200);
  assert.equal(category.body.data.ok, true);
  assert.equal(category.body.data.access_token, undefined);
  assert.equal(category.body.data.stream.key, undefined);
  assert.equal(category.body.data.stream.url, undefined);
  assert.equal(category.body.data.stream.is_live, true);
  assert.equal(category.headers.get("x-ratelimit-remaining"), "41");
  const proxied = mock.requests.findLast((request) => request.path === "/public/v2/categories");
  assert.equal(proxied?.method, "GET");
  assert.equal(proxied?.query.get("q"), "redot");
  assert.deepEqual(proxied?.query.getAll("tags"), ["a", "b"]);
  assert.match(String(proxied?.headers.authorization), /^Bearer kick-access-refreshed$/);
  assert.ok(mock.requests.some((request) => request.path === "/oauth/token" && (request.body as Record<string, string>).grant_type === "refresh_token"));

  const needsConfirmation = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/channels.update`, { method: "POST", headers: auth, body: { schema_version: 1, query: {}, path_parameters: {}, body: { stream_title: "Title" }, confirmed: false } });
  assert.equal(needsConfirmation.status, 409);
  const confirmed = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/channels.update`, { method: "POST", headers: auth, body: { schema_version: 1, query: {}, path_parameters: {}, body: { stream_title: "Title" }, confirmed: true } });
  assert.equal(confirmed.status, 200);
  assert.equal(mock.requests.findLast((request) => request.path === "/public/v1/channels")?.method, "PATCH");

  const missingCapability = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/moderation.ban`, { method: "POST", headers: auth, body: { schema_version: 1, query: {}, path_parameters: {}, body: {}, confirmed: true } });
  assert.equal(missingCapability.status, 403);
  const unknown = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/https%3A%2F%2Fevil.invalid`, { method: "POST", headers: auth, body: { schema_version: 1, query: {}, path_parameters: {}, body: {}, confirmed: true } });
  assert.equal(unknown.status, 404);
  assert.equal(mock.requests.some((request) => request.path.includes("evil")), false);
});

test("proxy rejects secret-bearing payload fields before upstream access", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["chat.write"]);
  const before = mock.requests.length;
  const result = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: { authorization: `Broker ${connected.brokerSession}` }, body: {
    schema_version: 1,
    query: {},
    path_parameters: {},
    body: { content: "hello", access_token: "attempted-exfiltration" },
    confirmed: false,
  } });
  assert.equal(result.status, 400);
  assert.equal(mock.requests.length, before);
});

test("write idempotency is persistent, replayable, and conflict-aware", async (t) => {
  const mock = await startMockKick();
  const store = new MemoryStateStore();
  const relay = createRelayService(testConfig(mock), store, new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["chat.write"]);
  const auth = { authorization: `Broker ${connected.brokerSession}` };
  const payload = {
    schema_version: 1,
    query: {},
    path_parameters: {},
    body: { content: "once only" },
    confirmed: false,
    idempotency_key: "chat-write-0001",
  };
  const first = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: auth, body: payload });
  const replayed = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: auth, body: payload });
  assert.equal(first.status, 200);
  assert.equal(replayed.status, 200);
  assert.deepEqual(replayed.body, first.body);
  assert.equal(mock.requests.filter((request) => request.path === "/public/v1/chat").length, 1);
  assert.equal(JSON.stringify(store.snapshot()).includes("chat-write-0001"), false);

  const conflict = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: auth, body: { ...payload, body: { content: "different" } } });
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.error.code, "idempotency_conflict");
  assert.equal(mock.requests.filter((request) => request.path === "/public/v1/chat").length, 1);
});

test("successful idempotent writes survive an encrypted relay-state restart", async () => {
  const mock = await startMockKick();
  const directory = await mkdtemp(join(tmpdir(), "redot-kicker-idempotency-"));
  const statePath = join(directory, "state.enc");
  const key = randomBytes(32);
  const config = testConfig(mock);
  let firstRelay: ReturnType<typeof createRelayService> | null = null;
  let secondRelay: ReturnType<typeof createRelayService> | null = null;
  try {
    firstRelay = createRelayService(config, await EncryptedFileStateStore.open(statePath, key), new NullLogger());
    await firstRelay.start();
    const connected = await authorize(firstRelay, ["chat.write"]);
    const auth = { authorization: `Broker ${connected.brokerSession}` };
    const payload = { schema_version: 1, query: {}, path_parameters: {}, body: { content: "survives restart" }, confirmed: false, idempotency_key: "chat-restart-0001" };
    assert.equal((await jsonRequest(`${firstRelay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: auth, body: payload })).status, 200);
    await firstRelay.stop();
    firstRelay = null;

    secondRelay = createRelayService(config, await EncryptedFileStateStore.open(statePath, key), new NullLogger());
    await secondRelay.start();
    assert.equal((await jsonRequest(`${secondRelay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: auth, body: payload })).status, 200);
    assert.equal(mock.requests.filter((request) => request.path === "/public/v1/chat").length, 1);
  } finally {
    if (firstRelay) await firstRelay.stop().catch(() => undefined);
    if (secondRelay) await secondRelay.stop().catch(() => undefined);
    await mock.close();
    await rm(directory, { recursive: true, force: true });
  }
});

test("subscription operations are bound to the authorized channel", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["events.manage"]);
  const auth = { authorization: `Broker ${connected.brokerSession}` };
  const action = (operation: string, query: Record<string, unknown>, body: Record<string, unknown>, confirmed = false) => jsonRequest(`${relay.baseUrl}/v1/kick/actions/${operation}`, {
    method: "POST",
    headers: auth,
    body: { schema_version: 1, query, path_parameters: {}, body, confirmed },
  });

  assert.equal((await action("subscriptions.list", { broadcaster_user_id: "777" }, {})).status, 403);
  assert.equal((await action("subscriptions.create", {}, { broadcaster_user_id: "777", events: [{ name: "chat.message.sent", version: 1 }] })).status, 403);
  const created = await action("subscriptions.create", {}, { events: [{ name: "chat.message.sent", version: 1 }] });
  assert.equal(created.status, 200);
  const upstreamCreate = mock.requests.findLast((request) => request.path === "/public/v1/events/subscriptions" && request.method === "POST");
  assert.match(String(upstreamCreate?.rawBody), /"broadcaster_user_id":123456789/);
  assert.equal((await action("subscriptions.delete", { id: ["not-owned"] }, {}, true)).status, 403);
  assert.equal((await action("subscriptions.delete", { id: ["01JTESTSUBSCRIPTION0000000001"] }, {}, true)).status, 204);
});

test("DELETE bodies preserve uint64 identifiers and large response IDs remain lossless", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["moderation.ban", "kicks.read"]);
  const auth = { authorization: `Broker ${connected.brokerSession}` };
  const unban = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/moderation.unban`, { method: "POST", headers: auth, body: {
    schema_version: 1,
    query: {},
    path_parameters: {},
    body: { broadcaster_user_id: "123456789", user_id: "9007199254740993" },
    confirmed: true,
  } });
  assert.equal(unban.status, 200);
  const upstreamDelete = mock.requests.findLast((request) => request.path === "/public/v1/moderation/bans");
  assert.equal(upstreamDelete?.method, "DELETE");
  assert.match(String(upstreamDelete?.rawBody), /"user_id":9007199254740993/);

  const leaderboard = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/kicks.leaderboard`, { method: "POST", headers: auth, body: { schema_version: 1, query: {}, path_parameters: {}, body: {}, confirmed: false } });
  assert.equal(leaderboard.status, 200);
  assert.equal(leaderboard.body.data[0].user_id, "9007199254740993");
});

test("request byte and JSON-shape limits fail before upstream access", async (t) => {
  const mock = await startMockKick();
  const config = testConfig(mock);
  config.maxJsonBodyBytes = 1024;
  const relay = createRelayService(config, new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["chat.write"]);
  const auth = { authorization: `Broker ${connected.brokerSession}` };
  const before = mock.requests.filter((request) => request.path === "/public/v1/chat").length;
  const oversized = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: auth, body: {
    schema_version: 1,
    query: {},
    path_parameters: {},
    body: { content: "x".repeat(2048) },
    confirmed: false,
  } });
  assert.equal(oversized.status, 413);

  let nested: Record<string, unknown> = {};
  for (let index = 0; index < 26; index += 1) nested = { child: nested };
  const tooDeep = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/chat.send`, { method: "POST", headers: auth, body: {
    schema_version: 1,
    query: {},
    path_parameters: {},
    body: nested,
    confirmed: false,
  } });
  assert.equal(tooDeep.status, 400);
  assert.equal(tooDeep.body.error.code, "json_shape");
  assert.equal(mock.requests.filter((request) => request.path === "/public/v1/chat").length, before);
});
