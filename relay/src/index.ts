import { loadRelayConfig } from "./config.js";
import { EncryptedFileStateStore } from "./state.js";
import { createRelayService } from "./server.js";

const config = await loadRelayConfig();
const store = await EncryptedFileStateStore.open(config.stateFile, config.masterKey);
const relay = createRelayService(config, store);

let stopping = false;
async function stop(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  process.stdout.write(`${JSON.stringify({ timestamp: new Date().toISOString(), level: "info", event: "relay_stopping", signal })}\n`);
  await relay.stop();
  process.exitCode = 0;
}

process.once("SIGTERM", () => void stop("SIGTERM"));
process.once("SIGINT", () => void stop("SIGINT"));
process.on("uncaughtException", () => { process.stderr.write(`${JSON.stringify({ timestamp: new Date().toISOString(), level: "error", event: "uncaught_exception" })}\n`); process.exit(1); });
process.on("unhandledRejection", () => { process.stderr.write(`${JSON.stringify({ timestamp: new Date().toISOString(), level: "error", event: "unhandled_rejection" })}\n`); process.exit(1); });

await relay.start();
