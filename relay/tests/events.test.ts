import assert from "node:assert/strict";
import test from "node:test";
import WebSocket from "ws";
import { NullLogger } from "../src/logger.js";
import { createRelayService } from "../src/server.js";
import { MemoryStateStore } from "../src/state.js";
import { authorize, jsonRequest, signedWebhook, startMockKick, testConfig } from "./helpers.js";

test("verified webhook reaches one authenticated, subscription-bound WebSocket session exactly once", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["events.receive", "events.manage"]);
  const auth = { authorization: `Broker ${connected.brokerSession}` };
  const subscribed = await jsonRequest(`${relay.baseUrl}/v1/kick/actions/subscriptions.create`, { method: "POST", headers: auth, body: {
    schema_version: 1,
    query: {},
    path_parameters: {},
    body: { broadcaster_user_id: 123456789, events: [{ name: "chat.message.sent", version: 1 }], method: "webhook" },
    confirmed: false,
  } });
  assert.equal(subscribed.status, 200);
  const ticket = await jsonRequest(`${relay.baseUrl}/v1/events/tickets`, { method: "POST", headers: auth, body: { schema_version: 1 } });
  assert.equal(ticket.status, 200);
  assert.deepEqual(ticket.body.subscription_ids, ["01JTESTSUBSCRIPTION0000000001"]);
  assert.doesNotMatch(String(ticket.body.socket_url), new RegExp(String(ticket.body.ticket)));
  const socket = new WebSocket(String(ticket.body.socket_url), { headers: { authorization: `Ticket ${ticket.body.ticket}` } });
  t.after(() => socket.close());
  await onceOpen(socket);

  const payload = Buffer.from(JSON.stringify({
    broadcaster: { user_id: 123456789, username: "fixture-user", channel_slug: "fixture-channel" },
    sender: { user_id: 987, username: "viewer", channel_slug: "viewer" },
    message_id: "chat-message-1",
    content: "hello from a verified fixture",
    created_at: new Date().toISOString(),
  }));
  const headers = signedWebhook(mock, payload);
  const messagePromise = onceMessage(socket);
  const webhook = await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers, body: payload });
  assert.equal(webhook.status, 204);
  const envelope = JSON.parse(await messagePromise) as Record<string, any>;
  assert.equal(envelope.platform, "kick");
  assert.equal(envelope.schema_version, 1);
  assert.equal(envelope.session_id, connected.descriptor.session_id);
  assert.equal(envelope.subscription_id, "01JTESTSUBSCRIPTION0000000001");
  assert.equal(envelope.channel_id, "123456789");
  assert.equal(envelope.payload.content, "hello from a verified fixture");
  assert.equal("signature" in envelope, false);

  const replay = await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers, body: payload });
  assert.equal(replay.status, 409);
  await assert.rejects(() => onceMessage(socket, 100), /timeout/);
});

test("signature, freshness, event binding, channel binding, and one-time ticket failures are fail-closed", async (t) => {
  const mock = await startMockKick();
  const relay = createRelayService(testConfig(mock), new MemoryStateStore(), new NullLogger());
  await relay.start();
  t.after(async () => { await relay.stop(); await mock.close(); });
  const connected = await authorize(relay, ["events.receive", "events.manage"]);
  const auth = { authorization: `Broker ${connected.brokerSession}` };
  await jsonRequest(`${relay.baseUrl}/v1/kick/actions/subscriptions.create`, { method: "POST", headers: auth, body: { schema_version: 1, query: {}, path_parameters: {}, body: { broadcaster_user_id: 123456789, events: [{ name: "chat.message.sent", version: 1 }] }, confirmed: false } });
  const ticket = await jsonRequest(`${relay.baseUrl}/v1/events/tickets`, { method: "POST", headers: auth, body: { schema_version: 1 } });
  const first = new WebSocket(String(ticket.body.socket_url), { headers: { authorization: `Ticket ${ticket.body.ticket}` } });
  t.after(() => first.close());
  await onceOpen(first);
  const secondStatus = await rejectedUpgrade(String(ticket.body.socket_url), String(ticket.body.ticket));
  assert.equal(secondStatus, 401);

  const validBody = Buffer.from(JSON.stringify({ broadcaster: { user_id: 123456789 }, content: "safe", created_at: new Date().toISOString() }));
  const invalidSignature = signedWebhook(mock, validBody, { "Kick-Event-Message-Id": "invalid-signature-id" });
  invalidSignature["Kick-Event-Signature"] = Buffer.from("invalid").toString("base64");
  assert.equal((await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: invalidSignature, body: validBody })).status, 401);
  const stale = signedWebhook(mock, validBody, { "Kick-Event-Message-Id": "stale-id", "Kick-Event-Message-Timestamp": "2020-01-01T00:00:00Z" });
  assert.equal((await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: stale, body: validBody })).status, 408);
  const wrongType = signedWebhook(mock, validBody, { "Kick-Event-Message-Id": "wrong-type-id", "Kick-Event-Type": "channel.followed" });
  assert.equal((await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: wrongType, body: validBody })).status, 403);
  const wrongChannelBody = Buffer.from(JSON.stringify({ broadcaster: { user_id: 777 }, content: "wrong channel", created_at: new Date().toISOString() }));
  const wrongChannel = signedWebhook(mock, wrongChannelBody, { "Kick-Event-Message-Id": "wrong-channel-id" });
  assert.equal((await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: wrongChannel, body: wrongChannelBody })).status, 403);
  const contentTypeBody = Buffer.from(JSON.stringify({ broadcaster: { user_id: 123456789 }, content: "content type", created_at: new Date().toISOString() }));
  const contentTypeHeaders = signedWebhook(mock, contentTypeBody, { "Kick-Event-Message-Id": "content-type-id" });
  assert.equal((await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: { ...contentTypeHeaders, "content-type": "text/plain" }, body: contentTypeBody })).status, 415);
  const acceptedMessage = onceMessage(first);
  assert.equal((await fetch(`${relay.baseUrl}/v1/events/webhook`, { method: "POST", headers: contentTypeHeaders, body: contentTypeBody })).status, 204);
  assert.equal((JSON.parse(await acceptedMessage) as Record<string, any>).payload.content, "content type");
  await assert.rejects(() => onceMessage(first, 100), /timeout/);
});

function onceOpen(socket: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
}

function onceMessage(socket: WebSocket, timeoutMs = 2000): Promise<string> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { cleanup(); reject(new Error("message timeout")); }, timeoutMs);
    const onMessage = (data: WebSocket.RawData) => { cleanup(); resolve(data.toString()); };
    const onError = (error: Error) => { cleanup(); reject(error); };
    const cleanup = () => { clearTimeout(timeout); socket.off("message", onMessage); socket.off("error", onError); };
    socket.once("message", onMessage);
    socket.once("error", onError);
  });
}

function rejectedUpgrade(url: string, ticket: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url, { headers: { authorization: `Ticket ${ticket}` } });
    socket.once("unexpected-response", (_request, response) => { resolve(response.statusCode ?? 0); socket.terminate(); });
    socket.once("open", () => { socket.terminate(); reject(new Error("reused ticket unexpectedly opened")); });
    socket.once("error", () => undefined);
  });
}
