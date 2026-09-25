# Testing and certification

## Passing deterministic gates

- MS-001 webhook/security contract harness: valid signature, mutation, stale timestamp, replay, binding, unknown type/version, malformed payload, bounded queues, reconnect/degraded paths.
- Core suite: frozen operation/capability coverage, credential protocol separation, secret/stream-key stripping, all typed event types, authorization/restore/rotation/revoke, slot isolation, typed service calls.
- HTTP suite: TLS/plaintext policy, redaction, JSON parsing, rate metadata, GET-only retry, non-retried writes, concurrency, cancellation, and body bounds.
- Media suite: HTTPS/loopback policy, decode/type validation, cache reuse, bounds, and clear-data.
- Windows helper: real Credential Manager ping/store/read/delete/read-after-delete.
- Linux helper: x86-64 build and `RKCH/1` protocol response in an isolated environment without a Secret Service session.
- Relay: deterministic Node scenarios covering mounted-secret configuration, OAuth/PKCE, session restore/rotation/revoke, frozen contract drift, all proxy gates, write idempotency, subscription ownership, lossless 64-bit IDs, raw-body webhook verification/replay/binding, authenticated one-time WSS tickets, encrypted state, and input bounds.

## Required commands

Use the explicit target Redot 26.3-rc.1 binary without `-d`, with `--quit-after` of at least 2 and a wall-clock timeout. Its headless editor import currently crashes even for an empty project; run script gates with an existing generated script-class cache and report editor admission as blocked, not passed.

For the 26.3 remediation branch, `tests/run_streaming_repair_suite.gd` exercises the actual loopback WebSocket receiver, first-event deduplication, a 512-event burst, replay, and queue overflow/retry. `relay/tests/auth.test.ts` covers independent same-slot accounts/installations and credential-scoped restore/revoke. The separate Redot 26.3-rc.1 headless editor-import crash prevents treating script-test success as full editor compatibility.

## Still blocked on live inputs

- concrete production host/TLS/secret-manager/monitoring/privacy selections (the reference Node/Docker runtime is implemented);
- live Kick developer application and test accounts/channels;
- live OAuth denial/expiry/revocation and current rate limits;
- official subscription creation/removal/reconciliation;
- public webhook delivery, relay restart, WSS reconnect, duplicate/outage/queue pressure;
- Windows and Linux exported-game matrix, including a real Linux desktop Secret Service;
- immutable release archive and public distribution approval.

Fixtures cannot substitute for those live checks. Until they pass, the repository version remains pre-release and documentation must not claim production certification.
