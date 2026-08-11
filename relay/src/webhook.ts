import { createRequire } from "node:module";
import { verify } from "node:crypto";
import type { IncomingHttpHeaders } from "node:http";
import type { RelayConfig } from "./config.js";
import { SUPPORTED_EVENTS } from "./contracts.js";
import { HttpError } from "./errors.js";
import type { SafeLogger } from "./logger.js";
import { isRecord } from "./sanitizer.js";
import type { StateStore } from "./state.js";
import type { DownlinkHub } from "./websocket-hub.js";

interface JsonBigParser { parse(source: string): unknown; }
const require = createRequire(import.meta.url);
const jsonBig = (require("json-bigint") as (options: Record<string, boolean>) => JsonBigParser)({ storeAsString: true, strict: true });

export class WebhookProcessor {
  private readonly config: RelayConfig;
  private readonly store: StateStore;
  private readonly hub: DownlinkHub;
  private readonly publicKey: () => string;
  private readonly logger: SafeLogger;

  constructor(config: RelayConfig, store: StateStore, hub: DownlinkHub, publicKey: () => string, logger: SafeLogger) {
    this.config = config;
    this.store = store;
    this.hub = hub;
    this.publicKey = publicKey;
    this.logger = logger;
  }

  async process(headers: IncomingHttpHeaders, rawBody: Buffer): Promise<void> {
    const messageId = requiredHeader(headers, "kick-event-message-id", 128);
    const subscriptionId = requiredHeader(headers, "kick-event-subscription-id", 128);
    const signatureText = requiredHeader(headers, "kick-event-signature", 8192);
    const timestamp = requiredHeader(headers, "kick-event-message-timestamp", 64);
    const eventType = requiredHeader(headers, "kick-event-type", 128);
    const eventVersionText = requiredHeader(headers, "kick-event-version", 16);
    const timestampMs = Date.parse(timestamp);
    if (!Number.isFinite(timestampMs)) throw new HttpError(400, "timestamp_invalid", "Kick webhook timestamp is invalid");
    if (Math.abs(Date.now() - timestampMs) > this.config.webhookFreshnessSeconds * 1000) throw new HttpError(408, "timestamp_stale", "Kick webhook timestamp is outside the accepted window");
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(signatureText)) throw new HttpError(401, "signature_invalid", "Kick webhook signature is invalid");
    const signed = Buffer.concat([Buffer.from(`${messageId}.${timestamp}.`, "utf8"), rawBody]);
    let signatureValid = false;
    try { signatureValid = verify("RSA-SHA256", signed, this.publicKey(), Buffer.from(signatureText, "base64")); }
    catch { signatureValid = false; }
    if (!signatureValid) throw new HttpError(401, "signature_invalid", "Kick webhook signature is invalid");

    const snapshot = this.store.snapshot();
    const subscription = snapshot.subscriptions.find((entry) => entry.id === subscriptionId && entry.active);
    if (!subscription) throw new HttpError(403, "subscription_unknown", "Kick webhook subscription is not owned by this relay");
    const eventVersion = Number(eventVersionText);
    if (!Number.isSafeInteger(eventVersion) || eventVersion < 1 || subscription.eventType !== eventType || subscription.eventVersion !== eventVersion) throw new HttpError(403, "subscription_mismatch", "Kick webhook type or version does not match the owned subscription");

    let parsed: unknown;
    try { parsed = jsonBig.parse(rawBody.toString("utf8")); }
    catch { throw new HttpError(400, "payload_invalid", "Kick webhook body is malformed JSON"); }
    if (!isRecord(parsed)) throw new HttpError(400, "payload_invalid", "Kick webhook body must be an object");
    validatePayloadShape(parsed);
    const broadcaster = isRecord(parsed.broadcaster) ? parsed.broadcaster : {};
    const channelId = identifier(broadcaster.user_id ?? broadcaster.id ?? parsed.broadcaster_user_id);
    if (!channelId || channelId !== subscription.channelId) throw new HttpError(403, "channel_mismatch", "Kick webhook channel does not match the owned subscription");
    await this.store.mutate((state) => {
      const now = nowSeconds();
      state.replayEntries = state.replayEntries.filter((entry) => entry.expiresAt > now);
      if (state.replayEntries.some((entry) => entry.messageId === messageId)) throw new HttpError(409, "replay", "Kick webhook message was already processed");
      if (state.replayEntries.length >= this.config.maxReplayEntries) throw new HttpError(503, "replay_capacity", "Kick webhook replay protection is at capacity", true);
      state.replayEntries.push({ messageId, expiresAt: now + this.config.replayTtlSeconds });
    });
    const receivedAt = new Date().toISOString();
    const occurredAt = validDateString(parsed.created_at) ?? validDateString(parsed.updated_at) ?? timestamp;
    const sessions = this.store.snapshot().sessions.filter((session) => session.channelId === channelId && session.brokerExpiresAt > nowSeconds() && session.capabilities.includes("events.receive"));
    let deliveries = 0;
    for (const session of sessions) {
      const envelope: Record<string, unknown> = {
        platform: "kick",
        schema_version: 1,
        tenant_id: this.config.tenantId,
        application_id: this.config.applicationId,
        session_id: session.id,
        subscription_id: subscriptionId,
        source_message_id: messageId,
        event_type: eventType,
        event_version: eventVersion,
        occurred_at: occurredAt,
        received_at: receivedAt,
        channel_id: channelId,
        supported: SUPPORTED_EVENTS.has(eventType),
        payload: parsed,
      };
      deliveries += this.hub.publish(session.id, subscriptionId, envelope);
    }
    this.logger.info("webhook_accepted", { deliveries, supported: SUPPORTED_EVENTS.has(eventType) });
  }
}

function requiredHeader(headers: IncomingHttpHeaders, name: string, maxLength: number): string {
  const source = headers[name];
  const value = Array.isArray(source) ? "" : String(source ?? "");
  if (!value || value.length > maxLength || /[\r\n]/.test(value)) throw new HttpError(400, "header_invalid", `Required Kick webhook header is missing or invalid: ${name}`);
  return value;
}

function identifier(value: unknown): string {
  if (typeof value === "string" && /^[0-9]{1,20}$/.test(value)) return value;
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) return String(value);
  if (typeof value === "bigint" && value >= 0n) return value.toString();
  return "";
}

function validDateString(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 64 || !Number.isFinite(Date.parse(value))) return null;
  return value;
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

function validatePayloadShape(value: unknown, depth = 0, counter: { value: number } = { value: 0 }): void {
  counter.value += 1;
  if (depth > 32 || counter.value > 20_000) throw new HttpError(400, "payload_shape", "Kick webhook payload exceeds depth or item limits");
  if (Array.isArray(value)) for (const item of value) validatePayloadShape(item, depth + 1, counter);
  else if (isRecord(value)) for (const item of Object.values(value)) validatePayloadShape(item, depth + 1, counter);
}
