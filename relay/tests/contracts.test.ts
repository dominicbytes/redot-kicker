import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { OPERATIONS, SUPPORTED_EVENTS } from "../src/contracts.js";

test("relay operation and event catalogs match the frozen addon contract", async () => {
  const contract = JSON.parse(await readFile(resolve(process.cwd(), "..", "addons", "redot-kicker", "contracts", "kick_api_contract.json"), "utf8")) as {
    endpoints: Array<{ id: string; method: string; path: string; scopes: string[] }>;
    events: Array<{ type: string }>;
  };
  const addonOperations = contract.endpoints.map(({ id, method, path, scopes }) => ({ id, method, path, scopes })).sort((left, right) => left.id.localeCompare(right.id));
  const relayOperations = [...OPERATIONS.values()].map(({ id, method, path, scopes }) => ({ id, method, path, scopes: [...scopes] })).sort((left, right) => left.id.localeCompare(right.id));
  assert.equal(relayOperations.length, 28);
  assert.deepEqual(relayOperations, addonOperations);
  assert.deepEqual([...SUPPORTED_EVENTS].sort(), contract.events.map((event) => event.type).sort());
});
