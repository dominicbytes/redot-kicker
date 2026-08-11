# redot-kicker preflight report

**Research date:** 2026-08-10
**Target:** standalone GDScript addon for Redot `26.2.stable.official.4f5b14aba`
**Verdict:** **CONDITIONAL GO**
**Implementation status:** not started

## Research scope and assumptions

This preflight asks whether an independently installable Redot addon can provide Kick integration similar in product scope to `redot-twitcher`: authentication, real-time stream/chat events, outbound actions, moderation/rewards where official routes exist, typed signals, editor setup, and media helpers.

The acceptance bar is official, public API behavior suitable for a distributed desktop addon. Private endpoints, frontend reverse engineering, or embedding a maintainer-owned confidential secret are not accepted as a stable basis. Desktop is the first target; browser exports are deferred because their OAuth and secret boundaries differ.

## Executive decision

Kick's official API is broad enough for a valuable addon: OAuth 2.1, channel and livestream data, chat send/delete, moderation, channel rewards, redemptions, and event subscriptions are documented. The blocker to a fully native Twitcher analogue is delivery, not API breadth. Kick sends events to a publicly reachable HTTPS webhook. A game running on a user's desktop cannot normally accept that traffic directly.

Proceed only with a two-part design:

1. `redot-kicker`: a pure-GDScript Redot addon for user authorization, REST calls, models/signals, editor setup, and a pluggable inbound-event transport.
2. A separately deployed public relay: receive Kick webhooks, verify Kick's RSA signature before parsing, deduplicate by message ID, and forward only the authorized application's events to the game over authenticated WebSocket or SSE.

The relay is a product and security boundary, not a hidden helper. Its hosting, tenancy, authentication, retention, privacy statement, abuse controls, and operational ownership must be decided before addon implementation passes Milestone 0. A local tunnel is acceptable for development but not an end-user architecture.

## Capability target

| Twitcher-like area | Official Kick support | Proposed v1 | Constraint |
| --- | --- | --- | --- |
| OAuth | Authorization code plus PKCE; token exchange also requires client secret | Bring-your-own Kick app credentials; loopback callback | Never distribute a shared client secret in addon code |
| Live events | Chat, follow, subscriptions/gifts, rewards, livestream state/metadata, moderation, gifted Kicks | Typed signals through relay transport | Public HTTPS webhook required |
| Chat actions | Send and delete documented | Include | Respect scopes and rate limits |
| Moderation | Ban, timeout, unban documented | Optional module | Request only when explicitly enabled |
| Rewards | Reward CRUD and redemption accept/reject documented | Include after core chat/events | Capability is a strong differentiator |
| Media | Payload/user/channel URLs where documented | URL model plus bounded cache | No implied ownership of remote media |
| Local-only operation | REST only | Supported for outbound/query mode | Cannot receive official real-time events |

## Recommended references by milestone/system

### M0 — contract, relay, and security spike

- **SRC-003:** [KickEngineering/KickDevDocs](https://github.com/KickEngineering/KickDevDocs), pinned during research at commit `04497042a71312e5c9b8fd3bc07703c7d0e2647f` (2026-07-03). Treat this repository as the protocol source of truth.
- **SRC-004:** [Events introduction](https://github.com/KickEngineering/KickDevDocs/blob/main/events/introduction.md). Use to define subscription lifecycle and the public webhook boundary.
- **SRC-005:** [Webhook security](https://github.com/KickEngineering/KickDevDocs/blob/main/events/webhook-security.md). Use for raw-body RSA verification, timestamp/message identifiers, and idempotency tests.
- **SRC-011:** [KickDevDocs issue #20](https://github.com/KickEngineering/KickDevDocs/issues/20). Use only as evidence that direct WebSocket delivery is planned/backlogged, not available.
- **SRC-001:** the installed Redot executable and generated API data at `D:\Claude Vault\redot\plugins\api\redot-26.2\4f5b14aba-single-windows-x86_64\extension_api.json`. It verifies native HTTP, WebSocket, TCP loopback, crypto/RSA, SHA-256, and Base64 primitives.

M0 must end with an approved relay threat model and a proof using synthetic signed fixtures. It must not execute downloaded candidate projects or use unofficial live endpoints.

### M1 — authentication and editor setup

- **SRC-006:** [Generating tokens: OAuth flow](https://github.com/KickEngineering/KickDevDocs/blob/main/getting-started/generating-tokens-oauth2-flow.md). Use for authorization, PKCE, redirect, refresh, and token exchange.
- **SRC-007:** [Scopes](https://github.com/KickEngineering/KickDevDocs/blob/main/scopes/scopes.md). Use to make permissions capability-driven and opt-in.
- **SRC-002:** [dominicbytes/twitcher](https://github.com/dominicbytes/twitcher), local path `D:\Claude Vault\redot\twitcher-redot`, commit `5c80a758b1800ac74bdfa36cf2f0274013ba58dc`. Use as MIT UX/packaging inspiration for an EditorPlugin, setup flow, and documented signals—not as a shared dependency.

### M2 — REST surface

- **SRC-009:** [Chat API](https://github.com/KickEngineering/KickDevDocs/blob/main/apis/chat.md). Use for outbound chat and message deletion.
- **SRC-010:** [Moderation API](https://github.com/KickEngineering/KickDevDocs/blob/main/apis/moderation.md). Use for explicit, permission-gated moderation helpers.
- **SRC-008:** [Channel rewards API](https://github.com/KickEngineering/KickDevDocs/blob/main/apis/channel-rewards.md). Use for reward and redemption resources/actions.
- **SRC-003:** the official docs repository also supplies current channels/livestream and event type contracts.

### M3–M5 — typed events, examples, and certification

- **SRC-004/SRC-005:** drive fixtures for all supported webhook event types, signature failures, duplicates, reordering, reconnects, and subscription loss.
- **SRC-002:** informs documentation density and example ergonomics only.
- A live Kick developer application and reachable staging relay are **not available evidence in this preflight**; they remain release-gate inputs.

## Redot adaptation notes

### Addon boundary

Use `res://addons/redot-kicker/` with a small `EditorPlugin`, a runtime client node, typed Resource/RefCounted models, and platform-prefixed names such as `KickClient`, `KickChatMessage`, and `KickRewardRedemption`. Remove every editor registration in `_exit_tree()`. Do not add an autoload silently.

The addon should expose distinct capability states:

- `REST_ONLY`: authorization and outbound/query actions work; no relay is configured.
- `RELAY_CONNECTED`: subscribed real-time events are available.
- per-scope flags for chat write, moderation, rewards, and events.

Avoid a universal streaming interface that erases Kick-specific reward and moderation semantics.

### Authentication and credentials

Generate PKCE verifier/challenge and OAuth state in Redot. Open the system browser and listen on a bounded loopback callback using `TCPServer`. The current Kick token exchange requires a client secret even when PKCE is used. Therefore v1 must require the developer integrating the addon to register their own Kick app and supply credentials at run time. A shared client ID/secret embedded in an open-source addon is not acceptable.

Tokens, secrets, webhook signing material, and relay credentials must not be saved in `.tres`, `.tscn`, `project.godot`, `ProjectSettings`, source, logs, crash text, examples, reports, or tests. The installed Redot build has encryption primitives but no verified OS keychain. Default to memory-only; make any `user://` persistence an explicit later decision.

### Webhook relay contract

The relay must verify the official RSA signature against the exact raw request body before decoding JSON. It must reject stale/replayed messages, deduplicate by official message ID, tolerate unknown event types, and record only redacted structured diagnostics. Each game connection needs tenant/app/channel authorization; a relay must not become a cross-stream data oracle.

Define a versioned downlink envelope with an explicit platform, subscription/event type, source message ID, occurrence/receipt times, and payload. Preserve the original event's semantic fields but do not forward headers/secrets the game does not need. Redot should reconnect with jitter and resume safely; duplicate events must not fire game logic twice.

### Reliability

Kick may remove event subscriptions after sustained webhook failures. The relay therefore needs health monitoring, subscription reconciliation, dead-letter diagnostics without secret-bearing payloads, and a user-visible degraded state in the addon. This operational requirement is why a relay choice blocks implementation rather than being postponed as deployment detail.

## Existing plugin and repository search

Queries covered GitHub repository search for `Redot Kick API`, `Redot Kick streaming addon`, `Godot Kick API`, `Godot Kick chat`, and Godot Asset Library combinations. On 2026-08-10 no relevant Redot integration or maintained Godot streaming-platform addon was found. This is a bounded search result, not proof that none exists.

False positives included [AlyssaSmt/Godot-kicker](https://github.com/AlyssaSmt/Godot-kicker), which is a hockey/game project rather than a Kick.com client.

The local `D:\Claude Vault\streamerbot\examples\kickbot` is **SRC-012**. It uses unofficial/private endpoints and is AGPL-3.0. It is rejected for reuse and protocol guidance. Its presence only proves prior interest in the problem; it does not validate today's official API.

## Rejected candidates and reasons

| Source | Disposition | Reason |
| --- | --- | --- |
| Local `examples/kickbot` | Reject | Unofficial/private protocol, AGPL-3.0, unsuitable for a stable official addon |
| Private Pusher/frontend endpoints | Reject | Unsupported, changeable, and contrary to the official API acceptance bar |
| Direct localhost webhook | Reject for release | Kick requires a publicly reachable HTTPS endpoint; NAT/firewall/local TLS make this non-productizable |
| Bundled maintainer client secret | Reject | A distributed client cannot keep it confidential and would couple every user to one application identity |
| `Godot-kicker` search false positive | Reject | Wrong product/domain |

## License and attribution obligations

- Kick's official documentation is a specification/reference; do not copy large documentation passages into source or product docs. Link and paraphrase.
- `dominicbytes/twitcher` is MIT and retains attribution to the original [kanimaru/twitcher](https://github.com/kanimaru/twitcher). If substantive code is adapted, preserve all required MIT notices and document provenance. Prefer independent implementation from the official Kick spec.
- The rejected local Kick example is AGPL-3.0. Do not copy code from it into this standalone addon.
- The eventual repository needs its own explicit license and a third-party notices file before release. The product name must not imply Kick endorsement.

## Adversarial evidence audit — `SELF_REVIEW`

Delegated reviewers were not requested, so these are separate labeled self-review passes, not independent review.

| Finding | Lens | Challenged claim | Evidence / missing proof | Result | Decision impact |
| --- | --- | --- | --- | --- | --- |
| KICK-001 | Feature/reference fit | Official Kick routes support a useful Twitcher-like REST surface | Official docs cover chat, moderation, rewards, channels, livestreams, and events | PASS | Supports project value |
| KICK-002 | Transport compatibility | A local-only Redot addon can receive real-time events | Official event docs require public HTTPS webhooks; WebSocket issue remains backlog | FAIL | Forces relay architecture and conditional verdict |
| KICK-003 | Missing assumptions | Relay deployment, tenancy, auth, retention, and ownership can be deferred | No approved relay design or live developer application was provided | BLOCKED | Blocks implementation beyond M0 and any release estimate |
| KICK-004 | Redot compatibility | Installed Redot can implement required client crypto/transports | Local 26.2 API data verifies HTTP, WebSocket, TCP, SHA-256, RSA, and Base64 | PASS | Native GDScript remains viable |
| KICK-005 | License/supply chain | Historical unofficial Kick code is a safe accelerator | Local example is AGPL-3.0 and uses private endpoints | FAIL | Reject code/protocol reuse |
| KICK-006 | Security | PKCE alone removes the need to handle a confidential value | Current official token flow still requires `client_secret` | FAIL | Require bring-your-own app credentials; never embed a shared secret |
| KICK-007 | Maintenance | Official WebSocket delivery can be assumed for near-term implementation | Issue #20 is planning evidence, not a released contract | FAIL | Do not build schedule or API around it |

No rejected audit finding was overridden. The material blocked finding is carried into `RSK-001` and the implementation gate.

## Open risks and unanswered questions

- **RSK-001 — BLOCKED:** Who owns and hosts the public webhook relay, and is it single-tenant/self-hosted or a managed multi-tenant service?
- **RSK-002 — OPEN:** What exact app-registration and client-secret handling instructions will be supportable for addon users?
- **RSK-003 — OPEN:** What are the current rate limits and subscription limits for the selected endpoints/account tier? Confirm with a live app before freezing retry defaults.
- **RSK-004 — OPEN:** What privacy/retention policy applies if the relay processes chat identity and moderation events?
- **RSK-005 — OPEN:** How will relay health and automatic subscription loss be surfaced and recovered?
- **RSK-006 — OPEN:** Which desktop platforms must loopback OAuth support at first release?

## Concrete implementation-plan changes

When `docs/gamedev/implementation-plan.md` is created, it should include these ordered outcomes:

1. **MS-001 — Relay contract and threat-model spike:** synthetic signed fixtures pass; replay, duplicate, wrong signature, tenant mismatch, unknown event, and relay-loss cases are specified. **Gate:** explicit architecture approval.
2. **MS-002 — Redot addon shell and BYO OAuth:** enable/disable cleanly, loopback/state/PKCE work, secret-safe settings and logs are verified.
3. **MS-003 — REST client:** channel/livestream queries and chat actions work with typed errors, rate-limit/backoff tests, and opt-in scopes.
4. **MS-004 — Relay event client:** authenticated downlink reconnects, deduplicates, exposes typed signals, and reports degraded subscriptions.
5. **MS-005 — Rewards and moderation:** permission-gated actions and redemption state transitions pass fixture and live tests.
6. **MS-006 — Documentation/example/certification:** a clean sample project, fresh-account setup, live event matrix, disconnect/reconnect, token expiry, redaction, and cleanup tests pass on the installed Redot build.

Do not estimate or begin MS-002–MS-006 until MS-001's relay decision is resolved.

## Preflight gate result

All research questions are answered or explicitly blocked. Every recommendation has a primary source, intended use, compatibility assessment, and license disposition. No candidate plugin or third-party code was executed. The report supports further design work but **does not authorize implementation yet** because the relay boundary is unresolved.

## 2026-08-11 implementation amendment

The product owner subsequently approved the recommended first-release architecture: each integrating developer self-hosts one single-tenant relay/broker for their own Kick application. The relay holds the Kick client secret and OAuth access/refresh tokens, performs exchange/refresh/revocation, receives and verifies webhooks, and authorizes an authenticated downlink. The desktop game stores only a versioned non-secret `user://` descriptor and an opaque scoped broker-session credential in Windows Credential Manager or Linux Secret Service.

This resolves preflight risks RSK-001, RSK-002, and RSK-007 and authorizes MS-001 implementation. Managed multi-tenancy is not selected. The production relay runtime/host, a live Kick developer application, staging infrastructure, and live limits remain external gates. Official contracts were repinned for MS-001 to KickDevDocs commit `7f7afe7ace9424f722c8e6b06e32421099c8e7f6` dated 2026-08-11; the earlier pin remains above as historical preflight evidence.

## 2026-08-11 relay-runtime amendment

The product owner approved TypeScript on the current Node.js LTS line, packaged as a portable Linux x86-64 Docker service. Node.js 24 is the current Active LTS line on the approval date, so the deterministic relay build pins Node.js `24.18.0` and the official `node:24.18.0-alpine3.24` image tag. The deployment remains self-hosted and single-tenant; no provider-specific managed service is selected. TLS termination, DNS, monitoring destinations, cost, and incident contacts remain operator-specific live-staging inputs.

The reference implementation now exists under `relay/` and pins the official base-image digest. Its deterministic Node suite, dependency audit, Compose validation, Linux x86-64 image build, non-root/read-only container smoke, redacted health/log checks, mounted-secret configuration, and encrypted-state envelope pass. This closes the implementation/runtime portion of the gate but does not select or certify an operator's public host, TLS, secret manager, monitoring, privacy policy, live Kick application, or current service limits.
