import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { EncryptedFileStateStore, emptyRelayState } from "../src/state.js";

test("encrypted state survives restart without plaintext secrets", async () => {
  const directory = await mkdtemp(join(tmpdir(), "redot-kicker-state-"));
  const statePath = join(directory, "state.enc");
  const key = randomBytes(32);
  try {
    const store = await EncryptedFileStateStore.open(statePath, key);
    await store.mutate((state) => {
      state.sessions.push({
        id: "session-id",
        sessionSlot: "primary",
        publisherId: "publisher",
        applicationId: "application",
        userId: "123",
        username: "user",
        channelId: "123",
        channelSlug: "channel",
        capabilities: ["identity.read"],
        scopes: ["user:read"],
        brokerCredentialHash: "hashed-broker-secret",
        brokerExpiresAt: 1999999999,
        accessToken: "kick-access-plaintext-sentinel",
        refreshToken: "kick-refresh-plaintext-sentinel",
        tokenType: "Bearer",
        tokenExpiresAt: 1999999999,
        createdAt: 1700000000,
        updatedAt: 1700000000,
      });
    });
    const raw = await readFile(statePath, "utf8");
    assert.doesNotMatch(raw, /kick-access-plaintext-sentinel|kick-refresh-plaintext-sentinel|hashed-broker-secret/);
    const reopened = await EncryptedFileStateStore.open(statePath, key);
    assert.equal(reopened.snapshot().sessions[0]?.accessToken, "kick-access-plaintext-sentinel");
    await assert.rejects(() => EncryptedFileStateStore.open(statePath, randomBytes(32)), /decrypt|authentication|state/i);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("empty state has bounded versioned collections and no raw webhook storage", () => {
  const state = emptyRelayState();
  assert.equal(state.schemaVersion, 1);
  assert.deepEqual(state.authRequests, []);
  assert.deepEqual(state.sessions, []);
  assert.deepEqual(state.subscriptions, []);
  assert.deepEqual(state.replayEntries, []);
  assert.deepEqual(state.idempotencyEntries, []);
  assert.equal("rawWebhookBodies" in state, false);
});
