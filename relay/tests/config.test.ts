import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadRelayConfig } from "../src/config.js";

test("configuration accepts mounted secrets and rejects inline or malformed secret/public URL input", async () => {
  const directory = await mkdtemp(join(tmpdir(), "redot-kicker-config-"));
  const clientSecret = join(directory, "client-secret");
  const masterKey = join(directory, "master-key");
  try {
    await writeFile(clientSecret, "mounted-client-secret\n", { mode: 0o600 });
    await writeFile(masterKey, `${randomBytes(32).toString("base64url")}\n`, { mode: 0o600 });
    const environment: NodeJS.ProcessEnv = {
      REDOT_KICKER_PUBLIC_BASE_URL: "https://relay.example.invalid",
      REDOT_KICKER_TENANT_ID: "tenant",
      REDOT_KICKER_PUBLISHER_ID: "publisher",
      REDOT_KICKER_APPLICATION_ID: "application",
      REDOT_KICKER_KICK_CLIENT_ID: "client-id",
      REDOT_KICKER_CLIENT_SECRET_FILE: clientSecret,
      REDOT_KICKER_MASTER_KEY_FILE: masterKey,
    };
    const loaded = await loadRelayConfig(environment);
    assert.equal(loaded.kickClientSecret, "mounted-client-secret");
    assert.equal(loaded.masterKey.length, 32);
    await assert.rejects(() => loadRelayConfig({ ...environment, REDOT_KICKER_CLIENT_SECRET: "inline" }), /rejected/);
    await assert.rejects(() => loadRelayConfig({ ...environment, REDOT_KICKER_MASTER_KEY: "inline" }), /rejected/);
    await assert.rejects(() => loadRelayConfig({ ...environment, REDOT_KICKER_PUBLIC_BASE_URL: "http://relay.example.invalid" }), /HTTPS/);
    await writeFile(masterKey, randomBytes(31).toString("base64url"), { mode: 0o600 });
    await assert.rejects(() => loadRelayConfig(environment), /32 bytes/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
