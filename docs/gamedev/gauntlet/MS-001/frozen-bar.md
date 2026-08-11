# G-001 frozen bar

**Frozen before implementation:** 2026-08-11
**Redot:** `26.2.stable.official.4f5b14aba`
**KickDevDocs:** `7f7afe7ace9424f722c8e6b06e32421099c8e7f6`
**Review mode:** labeled self-review; no independent delegated critics were requested

The gate passes only when the bounded `tests/run_ms001.gd` scenario proves all fixture-ledger outcomes, signature verification happens before parsing, authenticated events emit at most once, tenant/subscription/channel mismatches cannot enter game logic, unknown authenticated events remain connected, queue/replay structures stay within configured bounds, relay loss is visible, and diagnostics contain neither secrets nor raw event payloads.

Any false acceptance, duplicate game-facing emission, cross-binding delivery, unbounded queue/cache, secret/raw-payload leak, Redot parse/load/runtime error, unexplained warning, or unresolved critical self-review finding fails the gate and keeps MS-002 closed.
