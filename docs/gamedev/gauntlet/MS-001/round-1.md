# G-001 round 1 — labeled self-review

**Date:** 2026-08-11
**Review independence:** none claimed; delegated reviewers were not requested
**Frozen bar:** [`frozen-bar.md`](frozen-bar.md)

| Lens | Finding | Severity | Resolution | Retest |
| --- | --- | --- | --- | --- |
| Protocol conformance | Kick's official signature string does not cover subscription/type/version headers. Those headers cannot be treated as independently signed claims. | High, upstream | Kept the exact official algorithm; require the known subscription mapping, developer-specific HTTPS endpoint, and signed-payload broadcaster match. Recorded the residual explicitly in the threat model. | Subscription/channel/tenant mismatch fixtures pass; no unsupported cryptographic claim remains. |
| Security/threat model | The first bounded replay map evicted the oldest identity even while it remained fresh, allowing a capacity attacker to re-admit a signed replay inside the timestamp window. | Critical | Changed replay protection to fail closed at capacity and evict only expired identities. Added a one-entry capacity fixture. | `replay_capacity` is explicit and the fresh identity remains stored. |
| Reliability/backpressure | The first downlink path remembered an event ID before confirming queue capacity, so an overflowed event could not be retried after pressure cleared. | High | Check capacity before remembering a new ID. Added drain-and-retry assertions. | Accepted event drains; overflow is visible; rejected event is accepted on retry; queue stays at its bound. |
| Developer experience | Failure results must be actionable without exposing a signature, body, chat content, token, code, or broker credential. | Medium | Kept stable safe reason codes/messages, added nested payload omission, and retained a typed unknown-event path. | Redaction and unknown-event assertions pass. |
| Unlensed read-only pass | `received_at` initially reused the Kick message timestamp instead of the relay's receipt clock. | Medium | Emit injected/system receipt time independently while preserving `occurred_at`. | Deterministic timestamp still passes and envelope semantics match the schema. |
| Installed-Redot compatibility | Redot 26.2 parsed fixture JSON numeric IDs as floating values, producing `123456789.0` and a false channel mismatch. | High | Normalize integral JSON numeric user IDs before comparing with the bound Kick channel ID. | Valid and wrong-channel fixtures both pass their intended outcomes. |

No finding was overridden. The critical and high findings were fixed before the gate result was recorded.

## Result

**PASS.** The final bounded harness reports 54/54 checks passing on `26.2.stable.official.4f5b14aba`. MS-001's deterministic contract/security work is complete. Production-relay and live-account evidence remain correctly outside this fixture gate.
