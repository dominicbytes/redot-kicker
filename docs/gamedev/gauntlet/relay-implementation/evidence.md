# Deterministic relay implementation evidence

**Date:** 2026-08-11
**Reference runtime:** TypeScript on Node.js 24 LTS
**Container target:** Linux x86-64 (`linux/amd64`)
**Scope:** self-hosted, single-tenant Redot Kicker relay/broker

## Result

The reference relay implementation portion of MS-004 is complete and passes its deterministic source, security, persistence, packaging, and container gates. This evidence does not claim that an integrating developer's public deployment or Kick application has passed live certification.

| Gate | Result | Evidence |
|---|---|---|
| TypeScript compile and relay suite | PASS, 18/18 | `relay/npm test` |
| Frozen addon/relay contract identity | PASS, 28 operations and 10 event types | `relay/tests/contracts.test.ts` |
| OAuth/session/API/webhook/WSS security | PASS | auth, API, and event integration tests |
| Encrypted restart state and write idempotency | PASS | AES-256-GCM restart and one-upstream-write tests |
| Mounted-secret configuration | PASS | inline secret rejection and malformed-key/public-URL tests |
| Production dependency audit | PASS, 0 known vulnerabilities | `npm audit --omit=dev` |
| Compose normalization | PASS | `docker compose ... config --no-path-resolution --quiet` |
| Pinned Linux x86-64 image build | PASS | exact Node base tag and digest |
| Hardened container smoke | PASS | healthy, UID 1000, read-only root, all capabilities dropped, no-new-privileges |
| Runtime state/license/log inspection | PASS | authenticated ciphertext envelope, MIT license present, redacted structured logs |

## Frozen container inputs and output

- Node image: `node:24.18.0-alpine3.24`
- Node image digest: `sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd`
- Local deterministic image ID: `sha256:889dfbeda3dc3454becf6223f96b0923ce38623ba040448488635d423cfcf549`
- Architecture/OS: `amd64` / `linux`
- Image size: 57,819,504 bytes
- Runtime user: `node` (UID 1000 in smoke test)
- State envelope: `redot-kicker-state`, version 1, AES-256-GCM fields only (`algorithm`, `ciphertext`, `format`, `iv`, `tag`, `version`)

The image ID is local build evidence rather than a published immutable artifact. A release image/archive checksum must be generated from the final authorized release commit.

## Covered behavior

- Broker-owned OAuth state/PKCE, same-relay callback, single-use authorization result, token refresh, broker rotation/restore, and fail-closed revoke/delete semantics.
- Secret-file-only startup, 32-byte state key validation, atomic encrypted persistence with disk sync, restart recovery, expired/unclaimed-session cleanup, and bounded revocation retry.
- All 28 frozen official operation IDs with capability, scope, channel, destructive-confirmation, body/query/path, response-size, lossless uint64, redaction, and arbitrary-URL controls.
- Request-bound, hashed, encrypted 24-hour write idempotency that survives relay restart and rejects conflicting reuse.
- Subscription create/list/delete ownership, official response fields, reconciliation, and downlink closure on subscription loss.
- Exact-raw-body RSA webhook verification before JSON parsing, content-type/size/freshness/replay/type/version/channel checks, bounded payload shape, and signing-key refresh.
- Authenticated single-use WSS tickets, no credentials in URL/subprotocol, client-message rejection, packet/queue bounds, and deterministic shutdown.
- Redacted health/log output, non-root Docker runtime, read-only root filesystem compatibility, dropped capabilities, mounted secrets, persistent-state mount, and MIT license inclusion.

## Commands retained as evidence

```powershell
Set-Location relay
npm.cmd test
npm.cmd audit --omit=dev
npm.cmd pack --dry-run

Set-Location ..
docker build --platform linux/amd64 --tag redot-kicker-relay:test relay
docker compose -f relay/compose.example.yaml config --no-path-resolution --quiet
```

The final container smoke used generated synthetic secrets and a synthetic RSA public key mounted read-only. The container and those temporary files were removed after inspection; the local `redot-kicker-relay:test` image remains only as deterministic build evidence.

## Remaining live blockers

1. Developer-owned Kick application, test channel/accounts, and current scope/rate/subscription-limit observations.
2. Public staging host, DNS/TLS, secret manager, persistent backup/restore, monitoring/alerts, cost owner, privacy/retention statement, support contact, incident response, and deletion verification.
3. Live OAuth approval/denial/expiry/revoke, every enabled REST/write category, subscription create/delete/reconcile, official public webhook, signing-key rotation, WSS reconnect/outage/queue pressure, and relay rollback.
4. Exported Windows/Linux x86-64 game matrix, including a real Linux graphical Secret Service session and two-real-account isolation.
5. Immutable release artifacts and explicit public-release authorization.

No external/live gate is represented as passed.
