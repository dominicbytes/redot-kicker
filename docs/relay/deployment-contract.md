# Relay deployment contract

**Protocol version:** 1
**Topology:** one self-hosted, single-tenant relay/broker per integrating developer and Kick application
**Implementation status:** client and reference relay are implemented; a concrete operator deployment and live Kick certification remain required

The relay owns the Kick client secret and OAuth access/refresh tokens. The Redot client receives only a scoped opaque broker session and never an upstream token.

## HTTPS endpoints

| ID | Method/path | Authentication | Purpose |
|---|---|---|---|
| `auth.begin` | `POST /v1/auth/requests` | client proof hash | Create a broker-owned state/PKCE authorization request |
| `auth.redirect` | `GET /v1/auth/requests/{id}/authorize` | unguessable request ID | Redirect the system browser to Kick OAuth |
| `auth.status` | `GET /v1/auth/requests/{id}` | raw one-time proof header | Return pending status or a single-use initial broker session |
| `oauth.callback` | `GET /v1/oauth/callback` | OAuth state | Complete Kick authorization on the relay |
| `session.restore` | `POST /v1/sessions/restore` | broker session | Validate/refresh the scoped session and return a rotated credential |
| `session.rotate` | `POST /v1/sessions/rotate` | broker session | Rotate the broker session independently of Kick tokens |
| `session.revoke` | `POST /v1/sessions/revoke` | broker session | Revoke session, Kick authorization, and relay token state |
| `api.invoke` | `POST /v1/kick/actions/{operation_id}` | broker session | Invoke one allowlisted frozen official operation |
| `events.ticket` | `POST /v1/events/tickets` | broker session | Mint a short-lived, single-use WSS ticket |
| `events.socket` | `GET /v1/events/socket` | WSS `Authorization: Ticket …` | Deliver downlink envelopes |
| `events.webhook` | `POST /v1/events/webhook` | Kick RSA signature | Receive verified official events |
| `health` | `GET /v1/health` | none | Return redacted service/protocol health only |

Broker credentials use `Authorization: Broker <opaque-value>`. Authorization polling uses `X-Redot-Kicker-Proof: <base64url-value>`. Neither value may appear in a URL, WebSocket subprotocol, log, trace attribute, metric label, or error response.

## Authorization request

The client generates 32 random proof bytes and sends only their base64url SHA-256 digest:

```json
{
  "schema_version": 1,
  "publisher_id": "studio",
  "application_id": "kick-app",
  "session_slot": "primary",
  "capabilities": ["identity.read", "events.receive"],
  "proof_sha256": "..."
}
```

The relay generates OAuth state and PKCE, stores both only for the request lifetime, and returns a same-relay safe URL such as `/authorize/{request_id}`. That URL redirects to Kick without exposing the desktop proof. Polling proves possession of the raw proof. Success consumes the request and returns the initial broker credential exactly once.

## Session descriptor

Every successful authorize/restore/rotate response includes a new `broker_session` and a non-secret `session` object using `KickSessionDescriptor` schema 1. It binds:

- tenant/publisher application;
- desktop session slot;
- broker session ID;
- Kick user and authorized channel;
- granted capabilities and scopes;
- allowed subscription IDs;
- broker-session expiry.

The relay rejects any attempt to change those bindings through action parameters. Rotation invalidates the prior broker credential after the new one is issued.

## Operation proxy

`POST /v1/kick/actions/{operation_id}` accepts only:

```json
{
  "schema_version": 1,
  "query": {},
  "path_parameters": {},
  "body": {},
  "confirmed": false,
  "idempotency_key": "optional"
}
```

The relay maps `operation_id` through the same frozen contract, validates fields and limits, enforces the session's scopes/channel/confirmation, injects the server-side Kick token, and calls only the documented method/path. Arbitrary URLs, headers, methods, and OAuth endpoints are rejected. Upstream token fields, stream keys, and RTMP URLs are stripped before the response leaves the relay.

An idempotency key is accepted only for write operations and must be 8-128 URL-safe characters. The relay hashes the key, binds it to the session/operation/canonical request, and retains the sanitized successful response in encrypted bounded state for 24 hours. An exact replay receives that result without a second upstream write. Reuse with different inputs fails closed. Oversized results retain a completed marker so the write is never repeated, but cannot be replayed as a response.

## Event ingress and downlink

Ingress verification uses the exact raw request body. The signed bytes are:

```text
Kick-Event-Message-Id + "." + Kick-Event-Message-Timestamp + "." + RAW_BODY
```

Verify SHA-256/RSA PKCS#1 v1.5 with Kick's official public key before JSON parsing. Enforce body size, timestamp freshness, replay ID, known subscription binding, expected event type/version mapping, and payload broadcaster/channel. Kick's signature does not cover the subscription/type/version headers, so those values must be checked against relay-owned subscription state.

The WSS downlink uses `relay_downlink.schema.json`. A ticket is single-use, short-lived, memory-only, scoped to one broker session, and carries the relay-authoritative list of healthy subscription IDs. The client fails closed when that list is empty and rejects every envelope outside it. Queues and replay caches are bounded; overflow becomes an observable degraded condition rather than silent loss. Raw webhook bodies are discarded immediately after verification/dispatch.

## Operational release gate

The reference runtime is TypeScript on Node.js `24.18.0`, packaged from `node:24.18.0-alpine3.24` for Linux x86-64. Before production use, the relay operator must record the image/source revision, hosting/TLS platform, secret store, persistence/backup policy, monitoring and alerting, rate/subscription limits, cost owner, privacy/retention policy, incident contact, rollback, and deletion verification. Live MS-004 through MS-006 certification cannot pass without those inputs and a real Kick developer application/test channel.
