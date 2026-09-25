import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { CAPABILITY_SCOPES, OPERATIONS, SUPPORTED_EVENTS, type OperationContract } from "./contracts.js";
import type { RelayConfig } from "./config.js";
import { validateRelayConfig } from "./config.js";
import { pkcePair, proofCommitment, randomToken, secureEqual, sha256Base64Url } from "./crypto.js";
import { asHttpError, HttpError } from "./errors.js";
import { KickApiClient, type TokenGrant, type UpstreamResult } from "./kick-api.js";
import { JsonConsoleLogger, type SafeLogger } from "./logger.js";
import { containsSecretField, isRecord, sanitizeForClient } from "./sanitizer.js";
import type { AuthRequestRecord, IdempotencyRecord, SessionRecord, StateStore, SubscriptionRecord } from "./state.js";
import { WebhookProcessor } from "./webhook.js";
import { DownlinkHub } from "./websocket-hub.js";

const IDEMPOTENCY_TTL_SECONDS = 24 * 60 * 60;
const IDEMPOTENCY_MAX_ENTRIES = 10_000;
const IDEMPOTENCY_MAX_RESPONSE_BYTES = 1024 * 1024;
const IDEMPOTENCY_MAX_TOTAL_RESPONSE_BYTES = 64 * 1024 * 1024;

export class RelayService {
  private readonly config: RelayConfig;
  private readonly store: StateStore;
  private readonly kick: KickApiClient;
  private readonly logger: SafeLogger;
  private readonly hub: DownlinkHub;
  private readonly server: Server;
  private readonly limiter = new FixedWindowLimiter();
  private readonly refreshLocks = new Map<string, Promise<SessionRecord>>();
  private publicKeyPem = "";
  private webhook: WebhookProcessor;
  private effectivePublicBaseUrl = "";
  private reconcileTimer: NodeJS.Timeout | null = null;
  private publicKeyTimer: NodeJS.Timeout | null = null;
  private maintenanceTimer: NodeJS.Timeout | null = null;
  private revocationsRunning = false;
  private startedAt = 0;
  private subscriptionHealth = true;

  constructor(config: RelayConfig, store: StateStore, logger: SafeLogger = new JsonConsoleLogger()) {
    validateRelayConfig(config);
    this.config = config;
    this.store = store;
    this.kick = new KickApiClient(config);
    this.logger = logger;
    this.hub = new DownlinkHub(config, logger);
    this.server = createServer((request, response) => void this.handle(request, response));
    this.hub.attach(this.server);
    this.webhook = new WebhookProcessor(config, store, this.hub, () => this.publicKeyPem, logger);
  }

  get baseUrl(): string {
    if (!this.effectivePublicBaseUrl) throw new Error("Relay has not started");
    return this.effectivePublicBaseUrl;
  }

  async start(): Promise<void> {
    if (this.startedAt) throw new Error("Relay is already started");
    this.publicKeyPem = this.config.publicKeyPem || await this.kick.loadPublicKey();
    await this.cleanupExpired();
    await new Promise<void>((resolve, reject) => {
      const onError = (error: Error) => { this.server.off("listening", onListening); reject(error); };
      const onListening = () => { this.server.off("error", onError); resolve(); };
      this.server.once("error", onError);
      this.server.once("listening", onListening);
      this.server.listen(this.config.port, this.config.host);
    });
    const address = this.server.address() as AddressInfo;
    const configured = new URL(this.config.publicBaseUrl);
    if (configured.port === "0") configured.port = String(address.port);
    this.effectivePublicBaseUrl = configured.toString().replace(/\/$/, "");
    this.startedAt = Date.now();
    if (this.config.reconcileIntervalSeconds > 0) {
      this.reconcileTimer = setInterval(() => void this.reconcileSubscriptions(), this.config.reconcileIntervalSeconds * 1000);
      this.reconcileTimer.unref();
    }
    if (!this.config.publicKeyPem) {
      this.publicKeyTimer = setInterval(() => void this.refreshPublicKey(), 6 * 60 * 60 * 1000);
      this.publicKeyTimer.unref();
    }
    this.maintenanceTimer = setInterval(() => {
      void this.cleanupExpired();
      void this.processPendingRevocations();
    }, 60_000);
    this.maintenanceTimer.unref();
    void this.processPendingRevocations();
    this.logger.info("relay_started", { port: address.port, state_schema: 1 });
  }

  async stop(): Promise<void> {
    if (this.reconcileTimer) clearInterval(this.reconcileTimer);
    if (this.publicKeyTimer) clearInterval(this.publicKeyTimer);
    if (this.maintenanceTimer) clearInterval(this.maintenanceTimer);
    this.reconcileTimer = null;
    this.publicKeyTimer = null;
    this.maintenanceTimer = null;
    await this.hub.close();
    if (this.server.listening) await new Promise<void>((resolve, reject) => this.server.close((error) => error ? reject(error) : resolve()));
    this.startedAt = 0;
  }

  private async handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const started = Date.now();
    const requestId = randomToken(12);
    applySecurityHeaders(response, requestId);
    let route = "unknown";
    let status = 500;
    try {
      if (!this.limiter.allow(request.socket.remoteAddress ?? "unknown", 300, 60)) throw new HttpError(429, "rate_limited", "Relay request rate limit exceeded", true);
      const url = new URL(request.url ?? "/", "http://relay.invalid");
      if (url.pathname === "/v1/health" && request.method === "GET") {
        route = "health";
        status = this.health(response);
      } else if (url.pathname === "/v1/auth/requests" && request.method === "POST") {
        route = "auth.begin";
        if (!this.limiter.allow(`auth:${request.socket.remoteAddress ?? "unknown"}`, 10, 60)) throw new HttpError(429, "rate_limited", "Authorization request rate limit exceeded", true);
        status = await this.beginAuthorization(request, response);
      } else if (/^\/v1\/auth\/requests\/[A-Za-z0-9_-]+\/authorize$/.test(url.pathname) && request.method === "GET") {
        route = "auth.redirect";
        status = this.redirectAuthorization(url, response);
      } else if (/^\/v1\/auth\/requests\/[A-Za-z0-9_-]+$/.test(url.pathname) && request.method === "GET") {
        route = "auth.status";
        status = await this.pollAuthorization(url, request, response);
      } else if (url.pathname === "/v1/oauth/callback" && request.method === "GET") {
        route = "oauth.callback";
        status = await this.oauthCallback(url, response);
      } else if (url.pathname === "/v1/sessions/restore" && request.method === "POST") {
        route = "session.restore";
        status = await this.rotateSession(request, response, true);
      } else if (url.pathname === "/v1/sessions/rotate" && request.method === "POST") {
        route = "session.rotate";
        status = await this.rotateSession(request, response, false);
      } else if (url.pathname === "/v1/sessions/revoke" && request.method === "POST") {
        route = "session.revoke";
        status = await this.revokeSession(request, response);
      } else if (/^\/v1\/kick\/actions\/[^/]+$/.test(url.pathname) && request.method === "POST") {
        route = "api.invoke";
        status = await this.invokeOperation(url, request, response);
      } else if (url.pathname === "/v1/events/tickets" && request.method === "POST") {
        route = "events.ticket";
        status = await this.eventTicket(request, response);
      } else if (url.pathname === "/v1/events/webhook" && request.method === "POST") {
        route = "events.webhook";
        status = await this.receiveWebhook(request, response);
      } else {
        throw new HttpError(404, "not_found", "Relay route was not found");
      }
    } catch (error) {
      const failure = asHttpError(error);
      status = failure.status;
      if (!response.headersSent) sendJson(response, failure.status, { error: { code: failure.code, message: failure.message, retryable: failure.retryable } });
      else response.end();
      if (failure.status >= 500) this.logger.error("request_failed", { status: failure.status, retryable: failure.retryable });
    } finally {
      this.logger.info("request_complete", { route, status, duration_ms: Date.now() - started });
    }
  }

  private health(response: ServerResponse): number {
    const snapshot = this.store.snapshot();
    const now = nowSeconds();
    const activeSessions = snapshot.sessions.filter((session) => session.brokerExpiresAt > now).length;
    const healthySubscriptions = snapshot.subscriptions.filter((subscription) => subscription.active).length;
    sendJson(response, 200, { data: {
      status: this.publicKeyPem && this.subscriptionHealth ? "healthy" : "degraded",
      schema_version: 1,
      uptime_seconds: this.startedAt ? Math.floor((Date.now() - this.startedAt) / 1000) : 0,
      active_sessions: activeSessions,
      healthy_subscriptions: healthySubscriptions,
      active_downlinks: this.hub.activeConnectionCount(),
      pending_revocations: snapshot.pendingRevocations.length,
    } });
    return 200;
  }

  private async beginAuthorization(request: IncomingMessage, response: ServerResponse): Promise<number> {
    const body = await readJsonObject(request, this.config.maxJsonBodyBytes);
    requireSchema(body);
    const publisherId = safeIdentifier(body.publisher_id, 128, "publisher_id");
    const applicationId = safeIdentifier(body.application_id, 128, "application_id");
    const sessionSlot = safeIdentifier(body.session_slot, 64, "session_slot");
    if (publisherId !== this.config.publisherId || applicationId !== this.config.applicationId) throw new HttpError(403, "application_mismatch", "Relay application binding does not match");
    const capabilities = stringArray(body.capabilities, 32, 128, "capabilities");
    if (capabilities.length === 0 || capabilities.some((capability) => !(capability in CAPABILITY_SCOPES))) throw new HttpError(400, "capability_invalid", "One or more Kick capabilities are invalid");
    const proofHash = stringValue(body.proof_sha256, 128);
    if (!/^[A-Za-z0-9_-]{43}$/.test(proofHash)) throw new HttpError(400, "proof_invalid", "Client proof commitment is invalid");
    const requestId = randomToken(24);
    const oauthState = randomToken(32);
    const pkce = pkcePair();
    const createdAt = nowSeconds();
    const record: AuthRequestRecord = {
      id: requestId,
      publisherId,
      applicationId,
      sessionSlot,
      capabilities: [...new Set(capabilities)].sort(),
      requestedScopes: scopesForCapabilities(capabilities),
      proofHash,
      oauthState,
      pkceVerifier: pkce.verifier,
      status: "pending",
      sessionId: "",
      resultBrokerCredential: "",
      failureCode: "",
      createdAt,
      expiresAt: createdAt + this.config.authRequestTtlSeconds,
    };
    await this.store.mutate((state) => {
      pruneState(state, createdAt);
      if (state.authRequests.filter((entry) => entry.status === "pending").length >= 100) throw new HttpError(503, "authorization_capacity", "Relay authorization queue is at capacity", true);
      state.authRequests.push(record);
    });
    sendJson(response, 201, {
      request_id: requestId,
      authorization_url: `${this.baseUrl}/v1/auth/requests/${requestId}/authorize`,
      expires_at_unix: record.expiresAt,
      poll_interval_msec: 1000,
    });
    return 201;
  }

  private redirectAuthorization(url: URL, response: ServerResponse): number {
    const id = url.pathname.split("/")[4] ?? "";
    const record = this.store.snapshot().authRequests.find((entry) => entry.id === id);
    if (!record || record.status !== "pending" || record.expiresAt <= nowSeconds()) throw new HttpError(410, "authorization_expired", "Authorization request is no longer available");
    const pkceChallenge = sha256Base64Url(record.pkceVerifier);
    const upstream = new URL(this.config.oauthAuthorizeUrl);
    upstream.searchParams.set("response_type", "code");
    upstream.searchParams.set("client_id", this.config.kickClientId);
    upstream.searchParams.set("redirect_uri", `${this.baseUrl}/v1/oauth/callback`);
    upstream.searchParams.set("scope", record.requestedScopes.join(" "));
    upstream.searchParams.set("code_challenge", pkceChallenge);
    upstream.searchParams.set("code_challenge_method", "S256");
    upstream.searchParams.set("state", record.oauthState);
    response.writeHead(302, { location: upstream.toString(), "cache-control": "no-store", "referrer-policy": "no-referrer" });
    response.end();
    return 302;
  }

  private async pollAuthorization(url: URL, request: IncomingMessage, response: ServerResponse): Promise<number> {
    const id = url.pathname.split("/")[4] ?? "";
    const proof = singleHeader(request, "x-redot-kicker-proof");
    const commitment = proofCommitment(proof);
    const snapshot = this.store.snapshot();
    const current = snapshot.authRequests.find((entry) => entry.id === id);
    if (!current) throw new HttpError(404, "authorization_not_found", "Authorization request was not found");
    if (!commitment || !secureEqual(commitment, current.proofHash)) throw new HttpError(401, "proof_invalid", "Authorization proof is invalid");
    if (current.expiresAt <= nowSeconds()) throw new HttpError(410, "authorization_expired", "Authorization request expired");
    if (current.status === "pending") {
      sendJson(response, 202, { status: "pending" });
      return 202;
    }
    if (current.status === "failed") throw new HttpError(400, current.failureCode || "authorization_failed", "Kick authorization did not complete");
    if (current.status === "consumed") throw new HttpError(410, "authorization_consumed", "Authorization result was already consumed");
    const consumed = await this.store.mutate((state) => {
      const record = state.authRequests.find((entry) => entry.id === id);
      if (!record || record.status !== "completed" || !record.resultBrokerCredential) throw new HttpError(410, "authorization_consumed", "Authorization result was already consumed");
      const session = state.sessions.find((entry) => entry.id === record.sessionId);
      if (!session) throw new HttpError(410, "session_missing", "Authorized relay session no longer exists");
      const credential = record.resultBrokerCredential;
      record.resultBrokerCredential = "";
      record.status = "consumed";
      record.oauthState = "";
      record.pkceVerifier = "";
      return { credential, session: structuredClone(session) };
    });
    sendJson(response, 200, { broker_session: consumed.credential, session: this.descriptor(consumed.session) });
    return 200;
  }

  private async oauthCallback(url: URL, response: ServerResponse): Promise<number> {
    const stateValue = url.searchParams.get("state") ?? "";
    const code = url.searchParams.get("code") ?? "";
    const denied = url.searchParams.get("error") ?? "";
    const record = this.store.snapshot().authRequests.find((entry) => entry.status === "pending" && entry.oauthState && secureEqual(entry.oauthState, stateValue));
    if (!record || record.expiresAt <= nowSeconds()) return sendBrowserPage(response, 400, "Authorization expired", "This authorization request is no longer available. Return to the game and try again.");
    if (denied || !code || code.length > 4096) {
      await this.failAuthRequest(record.id, "authorization_denied");
      return sendBrowserPage(response, 400, "Authorization not completed", "Kick did not authorize this connection. You can close this page.");
    }
    let grant: TokenGrant | null = null;
    try {
      const authorizedGrant = await this.kick.exchangeCode(code, record.pkceVerifier, `${this.baseUrl}/v1/oauth/callback`);
      grant = authorizedGrant;
      const identity = await this.kick.resolveIdentity(authorizedGrant.accessToken);
      const capabilities = record.capabilities.filter((capability) => capabilityGranted(capability, authorizedGrant.scopes));
      if (capabilities.length === 0) throw new HttpError(403, "scopes_denied", "Kick granted none of the requested capabilities");
      const brokerCredential = randomToken(32);
      const timestamp = nowSeconds();
      const session: SessionRecord = {
        id: randomToken(24),
        sessionSlot: record.sessionSlot,
        publisherId: record.publisherId,
        applicationId: record.applicationId,
        userId: identity.userId,
        username: identity.username,
        channelId: identity.channelId,
        channelSlug: identity.channelSlug,
        capabilities,
        scopes: authorizedGrant.scopes,
        brokerCredentialHash: sha256Base64Url(brokerCredential),
        brokerExpiresAt: timestamp + this.config.brokerSessionTtlSeconds,
        accessToken: authorizedGrant.accessToken,
        refreshToken: authorizedGrant.refreshToken,
        tokenType: authorizedGrant.tokenType,
        tokenExpiresAt: authorizedGrant.expiresAt,
        createdAt: timestamp,
        updatedAt: timestamp,
      };
      await this.store.mutate((relayState) => {
        const current = relayState.authRequests.find((entry) => entry.id === record.id);
        if (!current || current.status !== "pending") throw new HttpError(409, "authorization_race", "Authorization request is no longer pending");
        relayState.sessions.push(session);
        current.status = "completed";
        current.sessionId = session.id;
        current.resultBrokerCredential = brokerCredential;
        current.oauthState = "";
        current.pkceVerifier = "";
      });
      void this.processPendingRevocations();
      return sendBrowserPage(response, 200, "Kick account connected", "Authorization is complete. Return to the game and close this page.");
    } catch {
      if (grant) {
        const failedGrant = grant;
        await this.store.mutate((state) => state.pendingRevocations.push({ id: randomToken(12), accessToken: failedGrant.accessToken, refreshToken: failedGrant.refreshToken, attempts: 0, retryAfter: nowSeconds() }));
        void this.processPendingRevocations();
      }
      await this.failAuthRequest(record.id, "authorization_failed");
      return sendBrowserPage(response, 502, "Authorization failed", "The relay could not complete Kick authorization. Return to the game and try again.");
    }
  }

  private async rotateSession(request: IncomingMessage, response: ServerResponse, restore: boolean): Promise<number> {
    const body = await readJsonObject(request, this.config.maxJsonBodyBytes);
    requireSchema(body);
    const provided = brokerCredential(request);
    const expectedSlot = restore ? safeIdentifier(body.session_slot, 64, "session_slot") : "";
    const nextCredential = randomToken(32);
    const rotated = await this.store.mutate((state) => {
      const credentialHash = sha256Base64Url(provided);
      const session = state.sessions.find((entry) => secureEqual(entry.brokerCredentialHash, credentialHash));
      if (!session || session.brokerExpiresAt <= nowSeconds()) throw new HttpError(401, "authorization", "Broker session is invalid or expired");
      if (expectedSlot && session.sessionSlot !== expectedSlot) throw new HttpError(403, "slot_mismatch", "Broker session does not match the requested slot");
      session.brokerCredentialHash = sha256Base64Url(nextCredential);
      session.brokerExpiresAt = nowSeconds() + this.config.brokerSessionTtlSeconds;
      session.updatedAt = nowSeconds();
      return structuredClone(session);
    });
    sendJson(response, 200, { broker_session: nextCredential, session: this.descriptor(rotated) });
    return 200;
  }

  private async revokeSession(request: IncomingMessage, response: ServerResponse): Promise<number> {
    const body = await readJsonObject(request, this.config.maxJsonBodyBytes);
    requireSchema(body);
    if (body.revoke_kick_authorization !== true || body.delete_token_state !== true) throw new HttpError(400, "revocation_incomplete", "Session revoke requires Kick revocation and relay token-state deletion");
    const credential = brokerCredential(request);
    const removed = await this.store.mutate((state) => {
      const credentialHash = sha256Base64Url(credential);
      const index = state.sessions.findIndex((entry) => secureEqual(entry.brokerCredentialHash, credentialHash));
      if (index < 0) throw new HttpError(401, "authorization", "Broker session is invalid or expired");
      const [session] = state.sessions.splice(index, 1);
      if (!session) throw new HttpError(401, "authorization", "Broker session is invalid or expired");
      const revocationId = randomToken(12);
      state.pendingRevocations.push({ id: revocationId, accessToken: session.accessToken, refreshToken: session.refreshToken, attempts: 0, retryAfter: nowSeconds() });
      state.idempotencyEntries = state.idempotencyEntries.filter((entry) => entry.sessionId !== session.id);
      return { session: structuredClone(session), revocationId };
    });
    this.hub.closeSession(removed.session.id);
    await this.processPendingRevocations();
    if (this.store.snapshot().pendingRevocations.some((entry) => entry.id === removed.revocationId)) throw new HttpError(503, "remote_revocation_pending", "Local relay token state was deleted, but Kick revocation is pending", true);
    sendJson(response, 200, { data: { revoked: true, token_state_deleted: true } });
    return 200;
  }

  private async invokeOperation(url: URL, request: IncomingMessage, response: ServerResponse): Promise<number> {
    const operationId = decodeURIComponent(url.pathname.slice("/v1/kick/actions/".length));
    const contract = OPERATIONS.get(operationId);
    if (!contract) throw new HttpError(404, "operation_unknown", "Kick operation is not allowlisted");
    if (contract.unavailable) throw new HttpError(409, "operation_unavailable", "Kick declares this scope but no official route is currently available");
    const body = await readJsonObject(request, this.config.maxJsonBodyBytes);
    requireSchema(body);
    const query = recordValue(body.query, "query");
    const pathParameters = recordValue(body.path_parameters, "path_parameters");
    const upstreamBody = recordValue(body.body, "body");
    const idempotency = idempotencyKey(body.idempotency_key);
    if (idempotency && !contract.write) throw new HttpError(400, "idempotency_not_applicable", "Idempotency keys are accepted only for Kick write operations");
    if (containsSecretField(query) || containsSecretField(pathParameters) || containsSecretField(upstreamBody)) throw new HttpError(400, "secret_field_rejected", "Secret-bearing fields are not accepted by the relay action boundary");
    let session = this.authenticate(request);
    if (!session.capabilities.includes(contract.capability)) throw new HttpError(403, "capability_missing", "Broker session does not grant this Kick capability");
    if (!hasScopes(session, contract)) throw new HttpError(403, "scope_missing", "Broker session does not grant the required Kick scope");
    if (contract.confirm && body.confirmed !== true) throw new HttpError(409, "confirmation_required", "This Kick action requires explicit confirmation");
    this.enforceSessionBinding(contract.id, session, query, upstreamBody);
    const keyHash = idempotency ? sha256Base64Url(idempotency) : "";
    const requestHash = idempotency ? sha256Base64Url(JSON.stringify(canonicalJson({ query, path_parameters: pathParameters, body: upstreamBody, confirmed: body.confirmed === true }))) : "";
    if (idempotency) {
      const cached = await this.claimIdempotency(session.id, contract.id, keyHash, requestHash);
      if (cached) return sendUpstreamResponse(response, cached.responseStatus, cached.responseBody, cached.responseHeaders);
    }
    try {
      session = await this.ensureFreshSession(session.id);
      let result = await this.kick.invoke(session, contract, query, pathParameters, upstreamBody);
      if (result.status === 401 && !contract.write) {
        session = await this.ensureFreshSession(session.id, true);
        result = await this.kick.invoke(session, contract, query, pathParameters, upstreamBody);
      }
      const sanitized = sanitizeForClient(result.body);
      if (result.status >= 200 && result.status < 300) {
        if (idempotency) await this.completeIdempotency(session.id, contract.id, keyHash, requestHash, result.status, sanitized, result.headers);
        await this.trackSubscriptions(contract.id, session, query, result.body);
      } else if (idempotency) await this.releaseIdempotency(session.id, contract.id, keyHash, requestHash);
      return sendUpstreamResponse(response, result.status, sanitized, result.headers);
    } catch (error) {
      if (idempotency) await this.releaseIdempotency(session.id, contract.id, keyHash, requestHash).catch(() => undefined);
      throw error;
    }
  }

  private async claimIdempotency(sessionId: string, operationId: string, keyHash: string, requestHash: string): Promise<IdempotencyRecord | null> {
    const now = nowSeconds();
    return this.store.mutate((state) => {
      state.idempotencyEntries = state.idempotencyEntries.filter((entry) => entry.expiresAt > now);
      const existing = state.idempotencyEntries.find((entry) => entry.sessionId === sessionId && entry.operationId === operationId && secureEqual(entry.keyHash, keyHash));
      if (existing) {
        if (!secureEqual(existing.requestHash, requestHash)) throw new HttpError(409, "idempotency_conflict", "The idempotency key was already used for a different request");
        if (existing.status === "pending") throw new HttpError(409, "idempotency_in_progress", "The matching Kick write is still in progress", true);
        if (!existing.responseAvailable) throw new HttpError(409, "idempotency_result_unavailable", "The matching Kick write completed, but its oversized response cannot be replayed");
        return structuredClone(existing);
      }
      if (state.idempotencyEntries.length >= IDEMPOTENCY_MAX_ENTRIES) throw new HttpError(503, "idempotency_capacity", "The relay idempotency cache is at capacity", true);
      state.idempotencyEntries.push({
        keyHash,
        sessionId,
        operationId,
        requestHash,
        status: "pending",
        responseStatus: 0,
        responseBody: null,
        responseHeaders: {},
        responseAvailable: false,
        responseBytes: 0,
        createdAt: now,
        expiresAt: now + IDEMPOTENCY_TTL_SECONDS,
      });
      return null;
    });
  }

  private async completeIdempotency(sessionId: string, operationId: string, keyHash: string, requestHash: string, status: number, body: unknown, headers: Record<string, string>): Promise<void> {
    const encoded = JSON.stringify(body ?? null);
    const responseBytes = Buffer.byteLength(encoded);
    await this.store.mutate((state) => {
      const entry = state.idempotencyEntries.find((candidate) => candidate.sessionId === sessionId && candidate.operationId === operationId && secureEqual(candidate.keyHash, keyHash) && secureEqual(candidate.requestHash, requestHash) && candidate.status === "pending");
      if (!entry) throw new HttpError(503, "idempotency_state", "The relay could not preserve the Kick write result", true);
      const storedBytes = state.idempotencyEntries.reduce((total, candidate) => total + candidate.responseBytes, 0);
      const available = responseBytes <= IDEMPOTENCY_MAX_RESPONSE_BYTES && storedBytes + responseBytes <= IDEMPOTENCY_MAX_TOTAL_RESPONSE_BYTES;
      entry.status = "completed";
      entry.responseStatus = status;
      entry.responseBody = available ? body : null;
      entry.responseHeaders = available ? { ...headers } : {};
      entry.responseAvailable = available;
      entry.responseBytes = available ? responseBytes : 0;
    });
  }

  private async releaseIdempotency(sessionId: string, operationId: string, keyHash: string, requestHash: string): Promise<void> {
    await this.store.mutate((state) => {
      state.idempotencyEntries = state.idempotencyEntries.filter((entry) => !(entry.sessionId === sessionId && entry.operationId === operationId && entry.status === "pending" && secureEqual(entry.keyHash, keyHash) && secureEqual(entry.requestHash, requestHash)));
    });
  }

  private async eventTicket(request: IncomingMessage, response: ServerResponse): Promise<number> {
    const body = await readJsonObject(request, this.config.maxJsonBodyBytes);
    requireSchema(body);
    const session = this.authenticate(request);
    if (!session.capabilities.includes("events.receive")) throw new HttpError(403, "capability_missing", "Broker session does not grant event delivery");
    const subscriptions = this.store.snapshot().subscriptions.filter((entry) => entry.active && entry.channelId === session.channelId).map((entry) => entry.id).sort();
    if (subscriptions.length === 0) throw new HttpError(409, "subscription_degraded", "No healthy Kick event subscriptions exist for this channel");
    const socket = new URL(this.baseUrl);
    socket.protocol = socket.protocol === "https:" ? "wss:" : "ws:";
    socket.pathname = "/v1/events/socket";
    socket.search = "";
    const ticket = this.hub.issueTicket(session.id, subscriptions, socket.toString());
    sendJson(response, 200, { socket_url: ticket.socketUrl, ticket: ticket.ticket, expires_at_unix: ticket.expiresAt, subscription_ids: subscriptions });
    return 200;
  }

  private async receiveWebhook(request: IncomingMessage, response: ServerResponse): Promise<number> {
    const contentType = String(request.headers["content-type"] ?? "").toLowerCase();
    if (!contentType.startsWith("application/json")) throw new HttpError(415, "content_type", "Kick webhooks require application/json");
    const rawBody = await readBody(request, this.config.maxWebhookBodyBytes);
    try {
      await this.webhook.process(request.headers, rawBody);
    } catch (error) {
      if (error instanceof HttpError && error.code === "signature_invalid" && !this.config.publicKeyPem && await this.refreshPublicKey()) await this.webhook.process(request.headers, rawBody);
      else throw error;
    }
    response.writeHead(204);
    response.end();
    return 204;
  }

  private authenticate(request: IncomingMessage): SessionRecord {
    const credentialHash = sha256Base64Url(brokerCredential(request));
    const session = this.store.snapshot().sessions.find((entry) => secureEqual(entry.brokerCredentialHash, credentialHash));
    if (!session || session.brokerExpiresAt <= nowSeconds()) throw new HttpError(401, "authorization", "Broker session is invalid or expired");
    return session;
  }

  private descriptor(session: SessionRecord): Record<string, unknown> {
    const subscriptionIds = this.store.snapshot().subscriptions.filter((entry) => entry.active && entry.channelId === session.channelId).map((entry) => entry.id).sort();
    return {
      schema_version: 1,
      session_slot: session.sessionSlot,
      tenant_id: this.config.tenantId,
      application_id: this.config.applicationId,
      session_id: session.id,
      identity: { user_id: session.userId, username: session.username },
      channel: { id: session.channelId, slug: session.channelSlug },
      granted_capabilities: [...session.capabilities].sort(),
      granted_scopes: [...session.scopes].sort(),
      subscription_ids: subscriptionIds,
      broker_session_expires_at_unix: session.brokerExpiresAt,
      saved_at_unix: nowSeconds(),
    };
  }

  private async ensureFreshSession(sessionId: string, force = false): Promise<SessionRecord> {
    const existing = this.refreshLocks.get(sessionId);
    if (existing) return existing;
    const task = (async () => {
      const session = this.store.snapshot().sessions.find((entry) => entry.id === sessionId);
      if (!session) throw new HttpError(401, "authorization", "Broker session no longer exists");
      if (!force && session.tokenExpiresAt > nowSeconds() + this.config.tokenRefreshSkewSeconds) return session;
      const grant = await this.kick.refresh(session.refreshToken);
      return this.store.mutate((state) => {
        const current = state.sessions.find((entry) => entry.id === sessionId);
        if (!current) throw new HttpError(401, "authorization", "Broker session no longer exists");
        current.accessToken = grant.accessToken;
        current.refreshToken = grant.refreshToken;
        current.tokenType = grant.tokenType;
        current.tokenExpiresAt = grant.expiresAt;
        current.scopes = grant.scopes;
        current.capabilities = current.capabilities.filter((capability) => capabilityGranted(capability, grant.scopes));
        current.updatedAt = nowSeconds();
        return structuredClone(current);
      });
    })();
    this.refreshLocks.set(sessionId, task);
    try { return await task; }
    finally { this.refreshLocks.delete(sessionId); }
  }

  private async trackSubscriptions(operationId: string, session: SessionRecord, query: Record<string, unknown>, body: unknown): Promise<void> {
    if (operationId === "subscriptions.delete") {
      const ids = Array.isArray(query.id) ? query.id.map(String) : query.id === undefined ? [] : [String(query.id)];
      if (ids.length > 0) await this.store.mutate((state) => { state.subscriptions = state.subscriptions.filter((entry) => !ids.includes(entry.id)); });
      return;
    }
    if (operationId !== "subscriptions.create" && operationId !== "subscriptions.list") return;
    const observed = extractSubscriptions(body, session.channelId);
    const removed = await this.store.mutate((state) => {
      const removedIds: string[] = [];
      if (operationId === "subscriptions.list") {
        const ids = new Set(observed.map((entry) => entry.id));
        for (const existing of state.subscriptions) {
          if (existing.channelId !== session.channelId) continue;
          if (existing.active && !ids.has(existing.id)) removedIds.push(existing.id);
          existing.active = ids.has(existing.id);
        }
      }
      for (const subscription of observed) {
        const existing = state.subscriptions.find((entry) => entry.id === subscription.id);
        if (existing) Object.assign(existing, subscription);
        else state.subscriptions.push(subscription);
      }
      return removedIds;
    });
    if (removed.length > 0) for (const active of this.store.snapshot().sessions.filter((entry) => entry.channelId === session.channelId)) this.hub.closeSession(active.id, "subscription_degraded");
  }

  private async cleanupExpired(): Promise<void> {
    const now = nowSeconds();
    const expiredIds = await this.store.mutate((state) => {
      const expiredAuthSessionIds = new Set(state.authRequests.filter((request) => request.status === "completed" && request.expiresAt <= now).map((request) => request.sessionId));
      const expired = state.sessions.filter((session) => session.brokerExpiresAt <= now || expiredAuthSessionIds.has(session.id));
      const expiredSessionIds = new Set(expired.map((session) => session.id));
      for (const session of expired) state.pendingRevocations.push({ id: randomToken(12), accessToken: session.accessToken, refreshToken: session.refreshToken, attempts: 0, retryAfter: now });
      state.sessions = state.sessions.filter((session) => !expiredSessionIds.has(session.id));
      state.idempotencyEntries = state.idempotencyEntries.filter((entry) => !expiredSessionIds.has(entry.sessionId));
      pruneState(state, now);
      state.authRequests = state.authRequests.filter((request) => request.expiresAt > now);
      return expired.map((session) => session.id);
    });
    for (const id of expiredIds) this.hub.closeSession(id, "session_expired");
  }

  private async processPendingRevocations(): Promise<void> {
    if (this.revocationsRunning) return;
    this.revocationsRunning = true;
    try {
      for (const pending of this.store.snapshot().pendingRevocations.filter((entry) => entry.retryAfter <= nowSeconds())) {
        const refresh = await this.kick.revoke(pending.refreshToken, "refresh_token");
        const access = await this.kick.revoke(pending.accessToken, "access_token");
        await this.store.mutate((state) => {
          const current = state.pendingRevocations.find((entry) => entry.id === pending.id);
          if (!current) return;
          if (refresh && access) state.pendingRevocations = state.pendingRevocations.filter((entry) => entry.id !== pending.id);
          else {
            current.attempts += 1;
            current.retryAfter = nowSeconds() + Math.min(3600, 30 * (2 ** Math.min(current.attempts, 7)));
          }
        });
      }
    } finally {
      this.revocationsRunning = false;
    }
  }

  private async reconcileSubscriptions(): Promise<void> {
    const sessions = this.store.snapshot().sessions.filter((session) => session.capabilities.includes("events.manage"));
    const byChannel = new Map<string, SessionRecord>();
    for (const session of sessions) if (!byChannel.has(session.channelId)) byChannel.set(session.channelId, session);
    let healthy = true;
    const contract = OPERATIONS.get("subscriptions.list");
    if (!contract) return;
    for (const session of byChannel.values()) {
      try {
        const fresh = await this.ensureFreshSession(session.id);
        const result = await this.kick.invoke(fresh, contract, { broadcaster_user_id: fresh.channelId }, {}, {});
        if (result.status < 200 || result.status >= 300) throw new Error("subscription list rejected");
        await this.trackSubscriptions(contract.id, fresh, {}, result.body);
      } catch {
        healthy = false;
      }
    }
    this.subscriptionHealth = healthy;
  }

  private async refreshPublicKey(): Promise<boolean> {
    try {
      this.publicKeyPem = await this.kick.loadPublicKey();
      return true;
    } catch {
      this.logger.warn("public_key_refresh_failed");
      return false;
    }
  }

  private async failAuthRequest(id: string, code: string): Promise<void> {
    await this.store.mutate((state) => {
      const record = state.authRequests.find((entry) => entry.id === id);
      if (!record) return;
      record.status = "failed";
      record.failureCode = code;
      record.oauthState = "";
      record.pkceVerifier = "";
      record.resultBrokerCredential = "";
    });
  }

  private enforceSessionBinding(operationId: string, session: SessionRecord, query: Record<string, unknown>, body: Record<string, unknown>): void {
    for (const source of [query, body]) {
      for (const name of ["broadcaster_user_id", "channel_id"]) {
        if (!(name in source)) continue;
        const value = identifier(source[name]);
        if (!value || value !== session.channelId) throw new HttpError(403, "channel_mismatch", "Kick operation does not match the authorized channel");
      }
    }
    if (operationId === "subscriptions.list") {
      query.broadcaster_user_id = session.channelId;
      return;
    }
    if (operationId === "subscriptions.create") {
      body.broadcaster_user_id = session.channelId;
      const events = body.events;
      if (!Array.isArray(events) || events.length < 1 || events.length > 10) throw new HttpError(400, "subscription_invalid", "Kick event subscription list is invalid");
      for (const event of events) {
        if (!isRecord(event) || typeof event.name !== "string" || !SUPPORTED_EVENTS.has(event.name) || event.version !== 1) throw new HttpError(400, "subscription_invalid", "Kick event subscription is not in the frozen official catalog");
      }
      if (body.method !== undefined && body.method !== "webhook") throw new HttpError(400, "subscription_invalid", "Kick event subscriptions must use webhook delivery");
      body.method = "webhook";
      return;
    }
    if (operationId === "subscriptions.delete") {
      const ids = Array.isArray(query.id) ? query.id.map(String) : query.id === undefined ? [] : [String(query.id)];
      const owned = new Set(this.store.snapshot().subscriptions.filter((entry) => entry.channelId === session.channelId).map((entry) => entry.id));
      if (ids.length < 1 || ids.length > 100 || ids.some((id) => !owned.has(id))) throw new HttpError(403, "subscription_mismatch", "Kick subscription deletion is not owned by this authorized channel");
    }
  }
}

export function createRelayService(config: RelayConfig, store: StateStore, logger?: SafeLogger): RelayService {
  return logger ? new RelayService(config, store, logger) : new RelayService(config, store);
}

function requireSchema(body: Record<string, unknown>): void {
  if (body.schema_version !== 1) throw new HttpError(400, "schema_mismatch", "Relay request schema_version must be 1");
}

function brokerCredential(request: IncomingMessage): string {
  const header = singleHeader(request, "authorization");
  const match = /^Broker ([A-Za-z0-9_-]{20,256})$/.exec(header);
  if (!match?.[1]) throw new HttpError(401, "authorization", "A valid broker session is required");
  return match[1];
}

function singleHeader(request: IncomingMessage, name: string): string {
  const value = request.headers[name];
  return Array.isArray(value) ? "" : String(value ?? "");
}

async function readJsonObject(request: IncomingMessage, limit: number): Promise<Record<string, unknown>> {
  const contentType = String(request.headers["content-type"] ?? "").toLowerCase();
  if (!contentType.startsWith("application/json")) throw new HttpError(415, "content_type", "Relay JSON requests require application/json");
  const body = await readBody(request, limit);
  let parsed: unknown;
  try { parsed = JSON.parse(body.toString("utf8")); }
  catch { throw new HttpError(400, "json_invalid", "Relay request body is malformed JSON"); }
  if (!isRecord(parsed)) throw new HttpError(400, "json_invalid", "Relay request body must be an object");
  validateJsonShape(parsed);
  return parsed;
}

function readBody(request: IncomingMessage, limit: number): Promise<Buffer> {
  const declared = Number(request.headers["content-length"] ?? 0);
  if (Number.isFinite(declared) && declared > limit) throw new HttpError(413, "body_too_large", "Relay request body exceeds the configured limit");
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    let tooLarge = false;
    request.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > limit) {
        tooLarge = true;
        chunks.length = 0;
      } else if (!tooLarge) chunks.push(chunk);
    });
    request.on("end", () => tooLarge ? reject(new HttpError(413, "body_too_large", "Relay request body exceeds the configured limit")) : resolve(Buffer.concat(chunks)));
    request.on("error", reject);
  });
}

function sendJson(response: ServerResponse, status: number, value: unknown): void {
  const body = JSON.stringify(value);
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(body) });
  response.end(body);
}

function sendUpstreamResponse(response: ServerResponse, status: number, body: unknown, headers: Record<string, string>): number {
  for (const [name, value] of Object.entries(headers)) response.setHeader(name, value);
  if (status === 204 || body === null || body === "") {
    response.writeHead(status);
    response.end();
  } else if (typeof body === "string") {
    response.writeHead(status, { "content-type": "text/plain; charset=utf-8", "content-length": Buffer.byteLength(body) });
    response.end(body);
  } else sendJson(response, status, body);
  return status;
}

function sendBrowserPage(response: ServerResponse, status: number, title: string, message: string): number {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escapeHtml(title)}</title></head><body><main><h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p></main></body></html>`;
  response.setHeader("content-security-policy", "default-src 'none'; base-uri 'none'; frame-ancestors 'none'");
  response.writeHead(status, { "content-type": "text/html; charset=utf-8", "content-length": Buffer.byteLength(html) });
  response.end(html);
  return status;
}

function applySecurityHeaders(response: ServerResponse, requestId: string): void {
  response.setHeader("cache-control", "no-store");
  response.setHeader("pragma", "no-cache");
  response.setHeader("referrer-policy", "no-referrer");
  response.setHeader("x-content-type-options", "nosniff");
  response.setHeader("x-frame-options", "DENY");
  response.setHeader("cross-origin-resource-policy", "same-origin");
  response.setHeader("x-request-id", requestId);
}

function safeIdentifier(value: unknown, maxLength: number, name: string): string {
  if (typeof value !== "string" || value.length < 1 || value.length > maxLength || !/^[A-Za-z0-9._-]+$/.test(value)) throw new HttpError(400, "identifier_invalid", `${name} is invalid`);
  return value;
}

function stringValue(value: unknown, maxLength: number): string {
  return typeof value === "string" && value.length <= maxLength ? value : "";
}

function stringArray(value: unknown, maxItems: number, maxLength: number, name: string): string[] {
  if (!Array.isArray(value) || value.length > maxItems || value.some((item) => typeof item !== "string" || item.length < 1 || item.length > maxLength)) throw new HttpError(400, "array_invalid", `${name} is invalid`);
  return value as string[];
}

function recordValue(value: unknown, name: string): Record<string, unknown> {
  if (!isRecord(value) || Object.keys(value).length > 128) throw new HttpError(400, "object_invalid", `${name} must be a bounded object`);
  return value;
}

function idempotencyKey(value: unknown): string {
  if (value === undefined || value === "") return "";
  if (typeof value !== "string" || !/^[A-Za-z0-9._:-]{8,128}$/.test(value)) throw new HttpError(400, "idempotency_key_invalid", "Idempotency key must be 8-128 URL-safe characters");
  return value;
}

function canonicalJson(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalJson);
  if (isRecord(value)) return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalJson(value[key])]));
  return value;
}

function scopesForCapabilities(capabilities: readonly string[]): string[] {
  const scopes = new Set<string>();
  for (const capability of capabilities) for (const scope of CAPABILITY_SCOPES[capability] ?? []) scopes.add(scope);
  return [...scopes].sort();
}

function capabilityGranted(capability: string, scopes: readonly string[]): boolean {
  const required = CAPABILITY_SCOPES[capability];
  return required !== undefined && required.every((scope) => scopes.includes(scope));
}

function hasScopes(session: SessionRecord, contract: OperationContract): boolean {
  if (contract.scopes.length === 0) return true;
  return contract.scopeMode === "any" ? contract.scopes.some((scope) => session.scopes.includes(scope)) : contract.scopes.every((scope) => session.scopes.includes(scope));
}

function pruneState(state: { authRequests: AuthRequestRecord[]; replayEntries: Array<{ expiresAt: number }>; idempotencyEntries: Array<{ expiresAt: number }> }, now: number): void {
  state.authRequests = state.authRequests.filter((entry) => entry.expiresAt > now || entry.status === "completed");
  state.replayEntries = state.replayEntries.filter((entry) => entry.expiresAt > now);
  state.idempotencyEntries = state.idempotencyEntries.filter((entry) => entry.expiresAt > now);
}

function extractSubscriptions(value: unknown, channelId: string): SubscriptionRecord[] {
  const root = isRecord(value) ? value : {};
  const data = Array.isArray(root.data) ? root.data : [];
  const now = nowSeconds();
  const subscriptions: SubscriptionRecord[] = [];
  for (const item of data) {
    if (!isRecord(item)) continue;
    const id = typeof item.id === "string" ? item.id : typeof item.subscription_id === "string" ? item.subscription_id : "";
    const eventType = typeof item.event === "string" ? item.event : typeof item.event_type === "string" ? item.event_type : typeof item.name === "string" ? item.name : "";
    const eventVersion = Number(item.version ?? item.event_version);
    const observedChannel = identifier(item.broadcaster_user_id ?? item.channel_id) || channelId;
    if (!id || !eventType || !Number.isSafeInteger(eventVersion) || eventVersion < 1 || observedChannel !== channelId) continue;
    subscriptions.push({ id, channelId, eventType, eventVersion, active: true, updatedAt: now });
  }
  return subscriptions;
}

function identifier(value: unknown): string {
  if (typeof value === "string" && /^[0-9]{1,20}$/.test(value)) return value;
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) return String(value);
  return "";
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[character] ?? character);
}

function validateJsonShape(value: unknown, depth = 0, counter: { value: number } = { value: 0 }): void {
  counter.value += 1;
  if (depth > 24 || counter.value > 10_000) throw new HttpError(400, "json_shape", "Relay JSON structure exceeds depth or item limits");
  if (Array.isArray(value)) for (const item of value) validateJsonShape(item, depth + 1, counter);
  else if (isRecord(value)) for (const item of Object.values(value)) validateJsonShape(item, depth + 1, counter);
}

class FixedWindowLimiter {
  private readonly entries = new Map<string, { count: number; resetAt: number }>();

  allow(key: string, maximum: number, windowSeconds: number): boolean {
    const now = nowSeconds();
    const entry = this.entries.get(key);
    if (!entry || entry.resetAt <= now) {
      this.entries.set(key, { count: 1, resetAt: now + windowSeconds });
      if (this.entries.size > 10_000) for (const [candidate, value] of this.entries) if (value.resetAt <= now) this.entries.delete(candidate);
      return true;
    }
    entry.count += 1;
    return entry.count <= maximum;
  }
}
