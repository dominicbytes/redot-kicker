# Redot Kicker relay

This directory contains the production relay/broker for Redot Kicker. It is a TypeScript service on Node.js 24 LTS, packaged for Linux x86-64 with Docker. One integrating developer deploys one relay for one Kick application; it is not a shared multi-tenant service.

The relay keeps the Kick client secret and OAuth tokens out of exported games. It owns OAuth state and PKCE, rotates opaque broker sessions, proxies only the 28 frozen official operations, receives and verifies Kick webhooks, and delivers authenticated WSS events to the matching Redot session.

The source is implemented and deterministically tested. A deployment is not certified for live users until its operator completes the live checklist below with a real Kick application, public TLS endpoint, test channel, monitoring, backup, privacy, and incident-response choices.

## Runtime and platform

- Node.js `24.18.0` (Node 24 LTS line)
- TypeScript, compiled before runtime
- Docker image base `node:24.18.0-alpine3.24`
- initial container target `linux/amd64`
- MIT license

Run source checks with:

```sh
npm ci --ignore-scripts
npm test
npm audit --omit=dev
```

## Kick application setup

Create a Kick developer application owned by the integrating developer. Configure these public HTTPS endpoints, replacing the example host:

- OAuth redirect: `https://kick-relay.example.com/v1/oauth/callback`
- webhook receiver: `https://kick-relay.example.com/v1/events/webhook`

The relay's `REDOT_KICKER_KICK_CLIENT_ID` and mounted client-secret file must belong to that application. The Redot addon's `publisher_id` and `application_id` must exactly match the relay configuration.

Do not put the Kick client secret in the image, Compose file, command line, environment value, game, repository, logs, or support bundles.

## Create local secret files

The example Compose file reads secrets from `relay/.secrets/`, which is ignored by Git and Docker. Create the directory with owner-only permissions. Put the Kick-issued client secret in `.secrets/kick_client_secret`, then generate a distinct 32-byte state-encryption key as 64 hexadecimal characters in `.secrets/master_key`.

On Linux, one suitable key-generation sequence is:

```sh
install -d -m 700 .secrets
umask 077
openssl rand -hex 32 > .secrets/master_key
```

Back up the master key in a separate secret manager. Losing it makes `state.enc` unrecoverable. Exposing it together with `state.enc` exposes the relay's OAuth token state.

## Configure and start

Edit `compose.example.yaml` with the public URL and stable identifiers, then copy it to an operator-owned deployment location or invoke it explicitly:

```sh
docker compose -f compose.example.yaml build --pull
docker compose -f compose.example.yaml up -d
docker compose -f compose.example.yaml ps
```

The example binds port 8080 only to loopback. Put a maintained reverse proxy or load balancer in front of it, terminate TLS there, redirect HTTP to HTTPS, and proxy WebSocket upgrades for `/v1/events/socket`. Do not expose the container port directly to the internet without TLS.

Check the redacted health endpoint:

```sh
curl --fail --silent https://kick-relay.example.com/v1/health
```

Healthy output contains only protocol state and aggregate counts. It never includes tenant identifiers, account names, credentials, tokens, request bodies, or URLs.

## Required configuration

| Variable | Purpose |
|---|---|
| `REDOT_KICKER_PUBLIC_BASE_URL` | Exact externally reachable HTTPS origin; loopback HTTP is allowed only for local tests |
| `REDOT_KICKER_TENANT_ID` | Stable relay-operator identifier |
| `REDOT_KICKER_PUBLISHER_ID` | Must match the addon's publisher ID |
| `REDOT_KICKER_APPLICATION_ID` | Must match the addon's application ID |
| `REDOT_KICKER_KICK_CLIENT_ID` | Kick developer application client ID |
| `REDOT_KICKER_CLIENT_SECRET_FILE` | Mounted file containing the Kick client secret |
| `REDOT_KICKER_MASTER_KEY_FILE` | Mounted file containing exactly 32 bytes encoded as base64url or 64 hex characters |
| `REDOT_KICKER_STATE_FILE` | Encrypted state path; defaults to `/var/lib/redot-kicker/state.enc` |

Optional bounded settings are defined in `src/config.ts`. Inline `REDOT_KICKER_CLIENT_SECRET` and `REDOT_KICKER_MASTER_KEY` values are deliberately rejected.

For deterministic offline startup or emergency signing-key pinning, `REDOT_KICKER_PUBLIC_KEY_FILE` may point to a mounted PEM public key. Normally the relay fetches Kick's official key at startup and refreshes it periodically and once on a signature failure.

## Redot client binding

Configure the addon with the same public relay URL, publisher ID, and application ID:

```gdscript
var config := KickClientConfig.new()
config.relay_base_url = "https://kick-relay.example.com"
config.publisher_id = "your-publisher"
config.application_id = "your-game"
```

The game opens the relay-owned authorization URL in the system browser. The game receives only an opaque, scoped broker credential. Windows Credential Manager or Linux Secret Service persists that credential; the relay persists Kick tokens only in its AES-256-GCM encrypted state file.

## Security behavior

- OAuth state, PKCE verifier, Kick tokens, and the client secret stay relay-side.
- Broker credentials are stored hashed by the relay and rotate on restore/rotation.
- Every action is checked against the frozen operation, capability, scope, confirmation, application, and channel binding.
- Explicit write idempotency keys are hashed and retained in encrypted bounded state for 24 hours. A replay receives the original sanitized response; reusing the key with a different request fails.
- Incoming Kick JSON preserves 64-bit identifiers losslessly.
- Webhook signatures are verified against the exact raw bytes before JSON parsing, then checked for freshness, replay, subscription type/version, and channel ownership.
- WSS tickets are hashed, short-lived, single-use, memory-only, and sent in an `Authorization: Ticket …` upgrade header.
- WebSocket queues, HTTP bodies, upstream responses, JSON depth, request rates, replay identities, and idempotency state are bounded.
- Raw webhook bodies, OAuth values, authorization headers, chat payloads, stream keys, and RTMP URLs are not logged or persisted as diagnostics.

See `../docs/relay/threat-model.md` and `../docs/relay/deployment-contract.md` for the protocol boundary.

## Persistence, backup, and deletion

The named volume contains one atomic encrypted `state.enc`. Back it up consistently and test restore with the matching master key. Store backup copies of ciphertext and key separately. The master key must not be rotated by replacing the file while retaining old ciphertext; first revoke/delete existing sessions or use an operator-controlled migration procedure.

User revocation removes the broker session and queues both refresh- and access-token revocation. Failed upstream revocations retry with bounded backoff. Expired and unclaimed authorization sessions are removed and queued for revocation. Operator account-deletion requests must also remove the matching encrypted state and backups according to the published retention policy.

The relay never persists raw webhook bodies. It persists only encrypted OAuth/session state, subscription metadata, bounded message IDs, pending revocations, and hashed idempotency records/results.

## Monitoring and incident response

Monitor container restarts, health status, pending revocations, webhook failures, subscription reconciliation, WSS disconnect/queue-overflow events, upstream latency/status, disk capacity, TLS expiry, and backup success. Logs are structured JSON and intentionally omit request and response bodies.

If the client secret or encrypted-state key may be exposed:

1. stop authorization and public ingress;
2. preserve redacted operational evidence, not request bodies or secrets;
3. rotate/revoke the Kick application secret and affected authorizations;
4. delete compromised broker sessions and encrypted state where required;
5. deploy a new master key only with fresh state;
6. notify affected users under the operator's published policy;
7. verify revocation and subscription cleanup before reopening.

## Upgrade and rollback

Before upgrading, record the current source commit/image ID, back up `state.enc`, verify the separate master-key backup, run `npm test`, build the exact `linux/amd64` image, and smoke-test `/v1/health`. Retain the prior image until the new relay completes OAuth, one read, one idempotent write, subscription reconciliation, webhook delivery, WSS delivery, restart/restore, and revocation checks.

Rollback by stopping the new container and starting the recorded prior image against a state format it supports. State schema version 1 is migration-compatible with relay files created before the idempotency cache was added. Never restore an older ciphertext snapshot without first considering token/session changes made after that backup.

## Live deployment certification

Before onboarding users, record evidence for all of the following:

- successful OAuth approval, denial, expiry, restore, rotation, revoke, and clear-data flows;
- current Kick scopes and every enabled official operation used by the game;
- subscription creation/list/deletion and automatic reconciliation;
- valid public webhook signature delivery and signing-key refresh;
- authenticated WSS delivery, reconnect, duplicate, outage, and queue-pressure behavior;
- relay restart with encrypted state restore and no plaintext secret artifacts;
- current rate-limit behavior and an operator alert threshold;
- TLS configuration, host ownership, monitoring, backup/restore, cost owner, privacy/retention statement, support contact, incident response, and deletion verification;
- Windows and Linux exported-game tests, including a real Linux desktop Secret Service session.

Deterministic fixtures prove the implementation boundary, not Kick's live service or a particular operator deployment.
