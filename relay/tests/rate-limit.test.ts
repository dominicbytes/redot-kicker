import assert from "node:assert/strict";
import test from "node:test";
import { NullLogger } from "../src/logger.js";
import { createRelayService } from "../src/server.js";
import { MemoryStateStore } from "../src/state.js";
import { authorize, jsonRequest, signedWebhook, startMockKick, testConfig } from "./helpers.js";

for (const hops of [0, 1, 2]) {
  test(`client rate buckets respect ${hops} trusted proxy hops`, async (t) => {
    const mock = await startMockKick();
    const config = { ...testConfig(mock), trustedProxyHops: hops };
    const relay = createRelayService(config, new MemoryStateStore(), new NullLogger());
    await relay.start();
    t.after(async () => { await relay.stop(); await mock.close(); });
    const body = { schema_version: 1, publisher_id: "fixture-publisher", application_id: "fixture-application", session_slot: "primary", capabilities: ["identity.read"], proof_sha256: "a".repeat(43) };
    const forwarded = (client: string) => hops === 2 ? `192.0.2.99, ${client}, 192.0.2.1` : `192.0.2.99, ${client}`;
    for (let i = 0; i < 10; i++) assert.equal((await jsonRequest(`${relay.baseUrl}/v1/auth/requests`, { method: "POST", headers: { "x-forwarded-for": forwarded("198.51.100.1") }, body })).status, 201);
    const begin = (xff: string) => jsonRequest(`${relay.baseUrl}/v1/auth/requests`, { method: "POST", headers: { "x-forwarded-for": xff }, body });
    assert.equal((await begin(forwarded("198.51.100.1"))).status, 429);
    assert.equal((await begin(forwarded("198.51.100.2"))).status, hops === 0 ? 429 : 201);
    // A forged leftmost address cannot reset the rightmost untrusted client's bucket.
    assert.equal((await begin(`203.0.113.77, ${forwarded("198.51.100.1")}`)).status, 429);
  });
}

test("health traffic cannot exhaust signed webhook or authenticated credential buckets", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const first = await authorize(relay, ["events.receive", "events.manage"]);
  const second = await authorize(relay, ["identity.read"]);
  const auth = { authorization: `Broker ${first.brokerSession}` };
  await jsonRequest(`${relay.baseUrl}/v1/kick/actions/subscriptions.create`, { method: "POST", headers: auth, body: { schema_version: 1, query: {}, path_parameters: {}, body: { events: [{ name: "chat.message.sent", version: 1 }] }, confirmed: false } });
  for (let i = 0; i < 300; i++) await jsonRequest(`${relay.baseUrl}/v1/health`);
  assert.equal((await jsonRequest(`${relay.baseUrl}/v1/health`)).status, 429);
  const payload = Buffer.from(JSON.stringify({ broadcaster: { user_id: 123456789 }, content: "fixture" }));
  const webhook = await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: signedWebhook(mock, payload), body: payload });
  assert.equal(webhook.status, 204);
  const invalid = signedWebhook(mock, payload, { "Kick-Event-Signature": "invalid" });
  assert.equal((await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: invalid, body: payload })).status, 401);
  for (let i = 0; i < 300; i++) await jsonRequest(`${relay.baseUrl}/v1/events/tickets`, { method: "POST", headers: auth, body: { schema_version: 1 } });
  assert.equal((await jsonRequest(`${relay.baseUrl}/v1/events/tickets`, { method: "POST", headers: auth, body: { schema_version: 1 } })).status, 429);
  assert.equal((await jsonRequest(`${relay.baseUrl}/v1/sessions/rotate`, { method: "POST", headers: { authorization: `Broker ${second.brokerSession}` }, body: { schema_version: 1, session_slot: "primary" } })).status, 200);
});

test("authorization polling uses proof-bound request buckets behind a shared proxy", async (t) => {
  const mock = await startMockKick();
  const store = new MemoryStateStore();
  const relay = createRelayService(testConfig(mock), store, new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const first = await authorize(relay, ["identity.read"]);
  const second = await authorize(relay, ["identity.read"]);
  const records = store.snapshot().authRequests;
  const poll = (index: number, proof: string) => jsonRequest(`${relay.baseUrl}/v1/auth/requests/${records[index]!.id}`, { headers: { "x-redot-kicker-proof": proof } });
  for (let i = 0; i < 300; i++) await poll(0, first.proof);
  assert.equal((await poll(0, first.proof)).status, 429);
  assert.equal((await poll(1, second.proof)).status, 410);
});
