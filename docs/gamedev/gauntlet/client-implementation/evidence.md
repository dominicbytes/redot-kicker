# Deterministic client implementation evidence

**Date:** 2026-08-11
**Engine:** Redot `26.2.stable.official.4f5b14aba`
**Scope:** `redot-kicker` client addon and Windows/Linux x86-64 credential-helper artifacts

## Result

The deterministic Redot client portions of MS-002 through MS-006 are complete. Relay implementation evidence is recorded separately; this document does not claim live Kick certification.

| Gate | Result | Evidence |
| --- | --- | --- |
| MS-001 relay/security contract harness | PASS, 54/54 | `tests/run_ms001.gd`; `docs/gamedev/gauntlet/MS-001/evidence.md` |
| Auth, capabilities, models, events, services, and isolation | PASS, 40/40 | `tests/run_core_suite.gd` |
| Bounded HTTP transport | PASS, 17/17 | `tests/run_http_transport_suite.gd` |
| Bounded media cache and deletion | PASS, 8/8 | `tests/run_media_suite.gd` |
| Project-wide script load | PASS, 67 scripts | `tests/run_project_check.gd` |
| Enabled editor plugin and example scene | PASS | bounded Redot editor/runtime runs |
| Windows Credential Manager helper | PASS | ping, store, read, delete, and read-after-delete through `tests/run_credential_helper_smoke.gd` |
| Linux x86-64 helper build/protocol | PASS / desktop session pending | isolated Linux RKCH/1 protocol run; live Secret Service desktop certification still required |

## Frozen helper artifacts

- Windows x86-64 SHA-256: `EBEA518CB06FDFA7345D27085CC1D5E73F88482CC1B90D6490244651E10FA62A`
- Linux x86-64 SHA-256: `A3EC7E3A50198DF9ABE8EB0CEFFBD66AA2DDC1E19EBE877C28CD9CB356BB5A9E`
- Canonical manifest: `addons/redot-kicker/bin/manifest.json`

## Covered client behavior

- Confidential broker authorization, restore, rotation, revoke, and clear-data flows without Kick tokens or client secrets entering the game.
- Stable per-client session slots with duplicate-slot exclusion and account-state isolation.
- All 28 frozen official operation contracts behind capability and destructive-action gates.
- All 10 frozen official event types plus a safe unknown-event path.
- Single-use event tickets with relay-authoritative subscription bindings; authenticated WSS without credentials in URLs or subprotocols.
- Bounded HTTP concurrency, queues, retries, response sizes, cancellation, redaction, media caching, and event deduplication.
- Reversible editor plugin, runtime connection panel, example scene, API/capability/security/data/relay/testing documentation, MIT license, and lineage notices.

## Remaining release blockers

1. Concrete public relay hosting/TLS/secret-manager/monitoring/privacy/cost/support selections and deployment evidence.
2. Live Kick application OAuth, REST, webhook, event, subscription, rate-limit, and account-side verification.
3. Linux desktop Secret Service persistence in a supported graphical session.
4. Two-real-account isolation, exported Windows/Linux builds, immutable release/package verification, and explicit public-release approval.

No blocked live gate has been represented as passed.
