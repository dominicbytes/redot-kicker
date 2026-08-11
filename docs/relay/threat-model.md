# redot-kicker relay threat model

## Protected assets

- Kick application client secret.
- Kick access and refresh tokens.
- Opaque broker-session credentials.
- User/channel identity, chat, reward, subscription, and moderation data.
- Webhook authenticity, tenant/channel routing, and exactly-once game-facing delivery.

## Trust boundaries and controls

| Threat | Required control | Deterministic evidence |
| --- | --- | --- |
| Forged webhook | RSA PKCS#1 v1.5 SHA-256 verification using Kick's public key | Invalid-signature fixture rejected |
| Body mutation or parser differential | Verify exact raw bytes before JSON decoding | Mutated and malformed-invalid-signature fixtures rejected as signature failures |
| Replay/duplicate | Timestamp freshness plus bounded message-ID cache at relay and client | Replay and reconnect duplicate emit no second event |
| Cross-channel delivery | Subscription mapping plus broadcaster ID comparison | Subscription/channel mismatch fixtures rejected |
| Cross-tenant delivery | Single-tenant deployment plus binding checks on every envelope | Other-tenant envelope rejected |
| Secret extraction from game | No Kick secret/token ever returned; opaque broker session only in OS vault | Contract and secret scan |
| Broker-session theft | TLS, scope binding, expiry, rotation, revocation, server-side hashing | Wrong credential rejected; rotation/revoke contract |
| Arbitrary API proxy abuse | Allowlist frozen operation IDs and validate parameters/body limits | Unknown operation rejected in broker-client tests |
| Duplicate write after retry | Hashed request-bound idempotency records in encrypted bounded state | Exact replay produces one upstream request; key/input conflict rejected |
| Memory/queue exhaustion | Request/header/body, replay-cache, queue, retry, and response bounds | Oversize and overflow fixtures |
| Sensitive logs | Structured redaction and raw-payload omission | Redaction fixtures and release secret scan |
| Relay outage | Honest `REST_ONLY`/disconnected/degraded states and reconciliation | Relay-loss/reconnect fixtures |

## Residual risks

- A compromised self-hosted relay can access that developer application's secrets, tokens, and processed channel data. Single tenancy limits the blast radius but does not remove it.
- Kick's documented signature string covers message ID, timestamp, and raw body, but not the subscription, type, or version headers. The relay therefore treats those headers as routing metadata rather than independently signed claims, requires an exact known subscription mapping on a developer-specific HTTPS endpoint, and independently compares the signed payload's broadcaster with the authorized channel. This is an upstream protocol limitation, not something the desktop addon can cryptographically strengthen.
- The plugin cannot validate an operator's TLS, vault, backup, retention, monitoring, or incident-response quality. Live certification requires a concrete deployment review.
- Kick can change routes, scopes, event payloads, limits, or signing keys. Contract repinning and the unknown-event path reduce but do not eliminate drift risk.
- Endpoint responses and webhook bodies contain user data. Games must collect only needed capabilities and expose disconnect, revoke, and clear-data controls.
