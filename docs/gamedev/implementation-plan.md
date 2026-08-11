# redot-kicker implementation plan

**Status:** Deterministic Redot client and Node 24 LTS reference relay complete; live Kick/operator certification remains
**Updated:** 2026-08-11
**Target engine:** Redot `26.2.stable.official.4f5b14aba`
**Addon runtime:** typed GDScript
**Relay runtime:** TypeScript on Node.js 24 LTS, Dockerized for Linux x86-64

This plan targets a full-featured standalone Kick integration, not a reduced REST wrapper. It uses the structure and verified generic boundaries from `redot-tuber` as a planning and source-reuse reference while preserving Kick-native semantics. Kick's official event delivery requires a public HTTPS webhook, so the finished product necessarily includes a separately deployed relay boundary. The deterministic client implementation is complete, and the approved production relay is TypeScript on Node.js 24 LTS in a portable Linux x86-64 Docker image.

## 1. Destination

`redot-kicker` is a standalone Redot addon that game developers install in a project. An exported game can let a consenting user connect their own Kick account/channel, receive typed real-time Kick events, query official channel and livestream data, and perform the Kick actions that user authorized.

A finished first release covers the complete official Kick surface relevant to interactive games: OAuth and account identity, channels and livestream discovery, chat send/delete, event subscription lifecycle, chat/follow/subscription/gift/livestream/reward/moderation events where officially available, channel reward and redemption operations, moderation, media helpers, typed errors, rate-limit diagnostics, revocation, and data deletion. Unsupported or unavailable routes remain explicit capability gaps; the addon never uses private frontend endpoints or scraping.

The addon has two honest operating modes:

- `REST_ONLY`: account authorization, supported queries, and outbound actions work; official real-time events are unavailable.
- `RELAY_CONNECTED`: an approved public relay receives and verifies Kick webhooks, then delivers authorized events to the game over the frozen downlink protocol.

The first release targets Windows and Linux x86-64. macOS follows after both are solid; ARM64, web, and mobile are later compatibility tracks.

## 2. Audience and constraints

### Audiences

- **Integrating developer:** installs the addon, registers and owns a Kick application, selects capabilities, configures the approved relay, and builds Kick interactions into a game.
- **Game user / channel owner:** authorizes the exported game, sees the connected channel and available capabilities, and can disconnect, revoke, or clear local data.
- **Game systems:** consume typed signals/resources and call permission-checked actions without parsing raw HTTP, OAuth, or relay payloads.
- **Relay operator:** deploys and maintains the webhook/OAuth boundary, tenant isolation, subscription health, monitoring, privacy policy, and incident response.

### Fixed constraints

- Standalone install at `res://addons/redot-kicker/`; no runtime dependency on `redot-tuber`, `redot-twitcher`, or another streaming addon.
- Typed GDScript is the Redot runtime language. No C#, .NET, or GDExtension library is introduced.
- Official public Kick APIs and documented webhook contracts only. Private Pusher/frontend endpoints and the historical AGPL Kickbot are rejected.
- Full official functionality is the product goal. Feature availability remains capability-, scope-, account-, and relay-state-aware.
- A public HTTPS webhook receiver is mandatory for official real-time events. Direct localhost webhooks are not a release architecture.
- The relay is a visible product/security boundary with a versioned contract; it is not silently embedded in the addon.
- Each integrating developer or publisher owns the Kick application used by their shipped game. A maintainer-owned shared client secret is never distributed.
- Kick's current token flow requires a confidential client value. Shipping that secret in the game is rejected. The approved self-hosted single-tenant relay performs exchange/refresh and owns the Kick client secret and OAuth tokens.
- Persistent login is required on supported desktop targets. The approved design must use a non-secret `user://` session descriptor plus Windows Credential Manager and Linux Secret Service helpers, with no plaintext fallback.
- Each `KickClient` owns one active Kick account/channel and one stable non-secret session slot. Multiple accounts use independent clients and slots; no global auth/service singleton is allowed.
- The first certified desktop release has Windows/Linux feature parity and x86-64 helper coverage. macOS and ARM64 follow after that matrix is solid.
- Web and mobile need separate OAuth, relay handoff, secure-storage, and lifecycle designs and do not block the first desktop release.
- The addon and eventual standalone repository use the MIT License. Kani/Twitcher and Redot Tuber notices are preserved for copied or substantially adapted source.
- Stable distribution follows the Redot Tuber portfolio pattern: canonical immutable GitHub release plus a matching Redot Asset Library entry. Development repository visibility does not itself authorize public disclosure.
- Secrets, tokens, app credentials, relay credentials, user data, and raw webhook payloads never enter source, scenes, resources, `ProjectSettings`, examples, fixtures, screenshots, reports, or ordinary logs.
- No implementation beyond MS-001 starts until the deterministic contract/security gate passes.

### Approved architecture and remaining external gates

- Each integrating developer self-hosts one single-tenant relay/broker for one Kick application. The relay stores the client secret and OAuth access/refresh tokens and performs token exchange, refresh, revocation, and webhook subscription control.
- The Redot client stores only a versioned non-secret descriptor under `user://` and an opaque, scoped, revocable broker-session credential in Windows Credential Manager or Linux Secret Service. It never receives a Kick access token, refresh token, or client secret.
- Relay downlink and broker calls use TLS plus an expiring broker session bound to application, user, channel, and session slot. No managed multi-tenant service is part of the first-release architecture.
- The relay persists no raw webhook body after verification/dispatch. Bounded replay and deduplication state contains message identity and expiry only; ordinary diagnostics are structured and redacted. The integrating developer is the data controller and relay operator.
- The relay uses TypeScript on Node.js 24 LTS and ships as a Linux x86-64 Docker deployment. A specific hosting provider, infrastructure cost, monitoring backend, and incident contacts remain operator-specific and must be declared before live staging.
- A live Kick developer application, staging relay, and current endpoint/subscription limits.

The live inputs do not block deterministic addon development. They block production-relay certification and the live MS-004 through MS-006 release matrix.

## 3. Design pillars

1. **Full-featured but capability-honest:** expose the official Kick surface without pretending REST-only clients have real-time events.
2. **Kick-native semantics:** preserve Kick reward, redemption, subscription, moderation, and livestream concepts instead of flattening them into Twitch-shaped types.
3. **Secure relay and credential boundaries:** verify before parsing, isolate tenants, minimize data, keep confidential values out of games, and never fall back to plaintext.
4. **Game-friendly typed API:** game code receives stable typed resources, signals, states, and errors rather than raw dictionaries and transport details.
5. **Observable reliability:** relay health, subscription loss, reconnect, deduplication, rate limits, authorization loss, and degraded modes are explicit and testable.
6. **Standalone reuse with provenance:** adapt audited generic foundations to save time, but retain no shared runtime or mechanically renamed platform subsystem.

## 4. Interaction rules

### Connection lifecycle

1. The game supplies a developer-owned application identifier, approved relay configuration, requested capability set, and stable non-secret session slot through a secret-safe runtime boundary.
2. `redot-kicker` derives the minimum scopes and explains which capabilities need REST, writes, moderation, rewards, or relay events.
3. The user authorizes in the system browser. State and PKCE are validated, while token exchange and refresh use the confidential-client boundary approved in MS-001.
4. The client resolves the authorized Kick identity/channel and enters `REST_ONLY` until an authenticated relay session and required subscriptions are healthy.
5. With a relay, the client subscribes through the approved control path and enters `RELAY_CONNECTED` only after tenant/channel authorization and health checks pass.
6. Refresh, relay reconnect, subscription reconciliation, rate pressure, authorization loss, and channel/offline transitions cause typed state changes rather than silent failure.
7. Disconnect stops only that client, removes its event subscriptions as configured, revokes when requested, clears memory, deletes its OS-vault record and descriptor, and invalidates relay sessions.

### Event rules

- The relay verifies Kick's official RSA signature against the exact raw body before decoding JSON.
- Stale timestamps, invalid signatures, replayed message IDs, unauthorized tenant/channel combinations, and over-limit bodies are rejected before downlink delivery.
- The versioned downlink envelope identifies the platform, schema version, subscription/event type, source message ID, authorized channel, occurrence/receipt time, payload version, and opaque relay session. It excludes signing headers and secrets the game does not need.
- The relay and client both deduplicate by stable source identity. Reconnect replay never fires game logic twice.
- Ordering is guaranteed only where the frozen contract can prove it. Events without an official total order expose occurrence/receipt metadata rather than inventing one.
- Unknown event types use a safe typed `unknown_event` path and never tear down the session.
- The official event catalog is frozen from the pinned Kick documentation before code generation; optional and newly added fields remain forward-compatible.
- Queue overflow, relay loss, subscription degradation, and dropped-event conditions are visible through diagnostics and state signals.

### Action rules

- Every action checks connection mode, authorization, scopes, channel ownership, required confirmation, and current rate/subscription state before sending.
- Chat send/delete, moderation, reward/redemption, subscription, and other write operations return typed success/failure with redacted diagnostics.
- Destructive actions require explicit confirmation at the addon boundary and an account-side verification step in live certification.
- Search/discovery is manually refreshed or conservatively cached; no per-frame or tight polling is allowed.

### Failure and recovery

- No app/relay configuration: remain disconnected and emit a typed configuration requirement.
- User denial or state mismatch: clear pending authorization state and return to disconnected without retry loops.
- Confidential-client broker unavailable: keep credentials secret, surface a recoverable broker error, and do not substitute an embedded secret.
- Relay unavailable: preserve valid REST capability, enter degraded `REST_ONLY`, and never claim event delivery.
- Refresh failure/revocation: stop privileged work, invalidate relay authorization, and require reauthorization.
- Subscription removed after webhook failures: enter degraded state, reconcile according to policy, and alert the integrating game.
- Rate limit: honor server metadata and bounded backoff; do not infer undocumented limits.
- Unknown or malformed payload: isolate the event, emit redacted diagnostics, and keep a healthy connection when safe.

## 5. Presentation

### Editor-facing

- A small setup/status tool explains Kick application registration, redirect requirements, relay modes, selected capabilities/scopes, supported platforms, and documentation links.
- The plugin never saves secrets to project content or silently adds an autoload.
- Everything registered in `_enter_tree()` is removed in `_exit_tree()`; enable/disable/re-enable is clean.
- Relay state distinguishes not configured, reachable, authenticated, subscription degraded, and healthy using text plus iconography rather than color alone.

### Runtime-facing

- Headless APIs are primary; optional theme-neutral Controls cover connect, consent status, identity, capability mode, relay health, disconnect/revoke, and clear-data.
- Keyboard and gamepad navigation, visible focus, readable scaling, and text status are required.
- Browser-launch failure exposes a copyable safe authorization URL; it never exposes state, verifier, secret, token, or relay credential values.

### Assets and media

No game art/audio pipeline is required. Any Kick branding or icons require current terms and recorded provenance. Remote avatar/reward/media content is bounded user/API data with clear-data support, not a redistributable addon asset.

## 6. Technical design

### Planned package boundary

```text
addons/redot-kicker/
  plugin.cfg
  plugin.gd
  editor/
  runtime/
  auth/
  transport/
  services/
  models/
  media/
  diagnostics/
  ui/
  contracts/
  tests/
  bin/
    windows/
    linux/
native/credential-helper/
relay/
examples/
docs/relay/
docs/lineage/
THIRD_PARTY_NOTICES.md
```

The production relay is a separate deployment artifact under `relay/`. Its approved topology is self-hosted and single-tenant; its runtime is TypeScript on Node.js 24 LTS, packaged for a generic Linux x86-64 Docker host. TLS may terminate at a trusted reverse proxy, but the relay still enforces the authenticated broker and WSS contracts. The Redot addon remains typed GDScript.

### Runtime responsibilities

- `KickClient`: public facade and state machine for exactly one account/channel and one persistent session slot.
- OAuth session: state, PKCE, browser launch, callback/session binding, code lifecycle, refresh/revoke orchestration, and capability calculation through the approved confidential-client boundary.
- Credential provider: non-secret session descriptor plus standalone Windows/Linux OS-vault helpers; unavailable/locked vault is typed and never enables plaintext.
- Kick API client: authenticated requests, typed errors, cancellation, retry/rate metadata, body limits, and redaction.
- Relay event source: authenticated WSS is the recommended downlink; MS-001 may select SSE only if evidence shows a better fit. Both remain behind one contract.
- Subscription service: create/delete/list/reconcile official event subscriptions and expose health/removal state.
- Services: identity/users, channels, livestreams/categories where documented, chat, rewards/redemptions, moderation, and event subscriptions.
- Models: typed Resources/RefCounted values for identity, channel, livestream, chat, follow, subscription/gift, reward/redemption, moderation, capabilities, relay state, rate limits, and errors.
- Media cache: HTTPS-only, bounded type/size/concurrency/retention behavior and clear-data support.
- Diagnostics: request class, rate/retry state, relay mode/latency, event lag, subscription health, queue pressure, and redacted errors.

### Relay responsibilities

- Terminate public HTTPS on a supported host and retain the exact raw request body for signature verification only as long as required to process it.
- Verify official signature, timestamp freshness, message identity, size, and replay policy before JSON parsing.
- Map subscriptions to one authorized application/tenant/channel and prevent cross-tenant observation.
- Deliver only the minimum versioned envelope over authenticated TLS downlinks with credential rotation and explicit expiry.
- Apply bounded queues/backpressure, deduplication, health checks, subscription reconciliation, and redacted dead-letter diagnostics.
- Publish its retention/privacy/abuse policy and operational ownership before staging users.
- Never log app secrets, OAuth codes/tokens, raw authorization headers, signing material, or unredacted chat/moderation payloads.

### Confidential-client and persistence architecture

The Kick client secret cannot be protected inside a distributed desktop game. The selected first-release boundary is a self-hosted single-tenant relay/broker per integrating developer. It holds one developer-owned Kick application secret, owns the OAuth access/refresh tokens, brokers code exchange and refresh, manages subscriptions, and receives official webhooks. A managed multi-tenant service is not selected.

The game receives only an opaque broker-session credential. That credential is scoped to the developer application, authorized Kick identity/channel, and stable client session slot; it expires, rotates, and can be invalidated independently of the Kick tokens. The Windows/Linux OS vault stores that opaque credential, while `user://` stores only a versioned non-secret descriptor. Embedding any Kick secret or token in game files, project settings, command-line arguments, environment variables, or ordinary `user://` storage is rejected.

Disconnect/revoke deletes the local descriptor and vault record, invalidates the broker session, and asks the relay to revoke and delete its associated Kick tokens. Clear-data remains meaningful even when the relay is unreachable: local state is removed immediately and the revocation failure is surfaced for retry/operator action.

### Redot Tuber and Twitcher reuse map

The primary generic reference is `redot-tuber` commit `029c22d7d5a5a68abacd8d12aabfea0b8e6536d8`. Its plan and implementation demonstrate the intended standalone repository boundary, per-client session slots, Windows Credential Manager and Linux Secret Service helpers, typed transport/errors, reversible editor setup, media limits, redaction, fixtures, and release evidence. `dominicbytes/twitcher` commit `5c80a758b1800ac74bdfa36cf2f0274013ba58dc` remains the upstream MIT lineage reference where Redot Tuber adapted generic foundations.

**Adapt only behind characterization/replacement tests:**

- reversible `EditorPlugin`, setup UI shell, optional runtime connection control, and compatibility-probe patterns;
- cancellation token, bounded HTTP transport, typed response/error models, redaction, media-cache, and deterministic loopback harness foundations;
- PKCE/state/loopback orchestration where compatible, but replace Google's public-client exchange with the approved Kick broker flow;
- non-secret session descriptors, per-client slot isolation, helper protocol, and Windows/Linux credential helpers;
- capability registry, typed facade, source-generation fixtures, quota/rate diagnostics, packaging, and lineage checks.

**Replace completely:**

- YouTube endpoints, scopes, discovery schemas, quota units, broadcasts/streams/chat models, streaming HTTP/polling transports, and Google consent assumptions;
- Twitch Helix, IRC, EventSub, rewards, private endpoints, generated Twitch schemas, global service ownership, implicit auth, and key-beside-cache storage;
- all AGPL Kickbot code and unofficial protocol knowledge.

### Sehelitar/Kick.bot disposition

[`Sehelitar/Kick.bot`](https://github.com/Sehelitar/Kick.bot) at pinned `main` commit `c542f4eff31cbba984a0723f7b17531da1334e77` is useful only as a feature, UX, and negative-test inventory. Its current implementation is AGPL-3.0-only, targets C#/.NET Framework and Streamer.bot, and relies on private Kick `/api/` routes, an embedded browser session cookie, and private Pusher channels rather than the official OAuth, REST, and webhook contracts selected for this product. No current code, schemas, endpoints, event names, cookie flow, or Pusher behavior may be copied or treated as protocol authority.

Candidate capabilities visible there—such as chat-mode controls, polls, clips, pinned messages, rewards, predictions, and multistream—must be checked individually against the current official Kick documentation in KICK-001. A capability enters the Redot Kicker matrix only when an official route/event, required scope, support mode, and lawful fixture can be pinned. Otherwise it is explicitly recorded as unavailable. The repository README says releases before `0.3.6` used MIT, but any future reuse proposal from those tags still requires a separate pinned, file-level license and protocol audit; none is approved by this plan.

Every copied or substantially adapted file is recorded in `docs/lineage/component-reuse.md` with source path, pinned commit, license, modification, and disposition. The finished addon has no runtime dependency on either donor.

### Public signals and state

The public API names are frozen before MS-002. At minimum, game code needs typed connection/capability, authorization, account/channel, livestream, chat, follow, subscription/gift, reward/redemption, moderation, relay health, subscription health, rate limit, queue pressure, unknown event, and error signals. Raw webhook/HTTP bodies are never part of the normal public API.

### Verified Redot constraints

- `HTTPRequest`/`HTTPClient` support the official REST surface and deterministic loopback harnesses.
- `WebSocketPeer` supports the recommended authenticated relay downlink.
- `TCPServer` and `OS.shell_open` support bounded desktop browser/callback flows where the approved broker contract needs them.
- `HashingContext`, `Crypto`, RSA, SHA-256, Base64, and random bytes support state/PKCE and synthetic signature fixtures.
- `OS.execute_with_pipe` supports the versioned credential-helper protocol without placing tokens in arguments.
- No verified cross-platform OS keychain exists in the installed Redot API, so standalone helper executables remain the accepted boundary.
- Installed Redot API data and successful runtime checks override newer Godot documentation.

## 7. Preflight research brief

The completed preflight investigated:

- official Kick OAuth, scopes, channels/livestreams, chat, moderation, rewards/redemptions, event subscriptions, event types, webhook security, and delivery constraints;
- whether direct event delivery is available to a desktop game;
- Redot HTTP, WebSocket, loopback, crypto/RSA, Base64, and process primitives;
- existing Redot/Godot addons and local historical implementations, including license/protocol suitability;
- the minimum relay, authentication, privacy, and operational boundary needed for a full-featured product.

Evidence had to be official/current or a clearly licensed local source, work with the installed Redot build, avoid private endpoints, and record a disposition. The detailed synthesis is in [`preflight-report.md`](preflight-report.md).

MS-001 refreshed the pinned Kick documentation before freezing contracts. Research stops when every supported endpoint/event/scope has a source and fixture disposition; the approved self-hosted relay and token-custody ADR is reflected in the contracts; deployment-specific live inputs are identified; and no unresolved question can change the MS-002 client architecture.

## 8. Preflight findings

- **Adopt:** official Kick OAuth/REST/events, capability-driven scopes, typed Kick-native models, public HTTPS webhooks, raw-body RSA verification, message-ID deduplication, and Redot's native HTTP/WebSocket/crypto primitives.
- **Adapt:** Redot Tuber's generic addon/editor, typed transport/error, PKCE/state, per-client session, OS-vault helper, media, diagnostics, test, packaging, and lineage foundations at the pinned commit.
- **Reject:** direct localhost webhook release design, private Pusher/frontend endpoints, shared embedded client secrets, project-resource credentials, current Sehelitar/Kick.bot code/protocols, the historical AGPL/unofficial Kickbot, and a universal Twitch-shaped streaming interface.
- **Conditional:** a full-featured release is viable only with an approved relay/broker and live Kick application evidence.
- **Distribution:** follow the separate-repository, separate-release, and separate-Asset-Library pattern; no combined streaming suite runtime.

Relevant source records are `SRC-001` through `SRC-020` in `source-of-truth.xlsx`.

## 9. Milestones

### MS-001 — Relay contract, confidential-client boundary, and security harness

**Status:** Complete. G-001 passed 54/54 deterministic checks on Redot 26.2 with no finding overrides.

**Runnable result:** a bounded Redot integration lab feeds lawful synthetic signed webhook fixtures through the frozen relay transformation and an authenticated mock downlink, then displays exactly one typed event or one explicit rejection/degraded state.

**Exit checks:** official contracts are repinned; valid/invalid signature, body mutation, stale timestamp, replay, duplicate, tenant/channel mismatch, unknown type/version, malformed payload, queue overflow, reconnect, and relay loss scenarios pass. The relay ownership/tenancy, OAuth exchange/refresh, token custody, privacy/retention, monitoring, and cost ADR is explicitly approved. Failure blocks MS-002.

### MS-002 — Installable addon, persistent authorization, and REST-only vertical slice

**Status:** Deterministic client work complete. Windows vault persistence passes; Linux desktop Secret Service and live broker/OAuth certification remain.

**Runnable result:** a clean Redot sample enables the addon, authorizes one Kick account through the approved broker, persists and restores that session securely, resolves the user's channel/livestream, and displays identity and capability state in `REST_ONLY` mode.

**Exit checks:** source-reuse manifest, clean enable/disable, state/PKCE/broker/callback denial paths, refresh/revoke, OS-vault restart, duplicate-slot rejection, two-client isolation, typed HTTP errors, secret scans, bounded run, and warnings/errors review pass on Windows and Linux x86-64.

### MS-003 — Complete official REST and outbound-action surface

**Status:** Deterministic official-operation surface complete. Live rate-limit and account-side verification remain.

**Runnable result:** the sample queries all supported channel/livestream/category/account data and performs documented chat and other non-relay actions through typed capability-gated services.

**Exit checks:** official contract fixtures, optional fields, pagination, validation, cancellation, rate/backoff metadata, denial/revocation, destructive confirmation, and live account-side verification pass for every shipped operation.

### MS-004 — Production relay, subscriptions, and complete typed event surface

**Status:** Client downlink, typed-event surface, and Node 24 LTS Docker relay are deterministic-test complete; live staging remains.

**Runnable result:** the approved staging relay receives verified Kick webhooks and an exported game receives the complete supported typed event catalog over the authenticated downlink, including reconnect and degraded subscription behavior.

**Exit checks:** deployed relay security gate, WSS/SSE decision, subscription create/delete/reconcile, tenant isolation, signature/replay rejection, deduplication, reconnect/resume, unknown types, ordering metadata, queue bounds, relay outage, subscription loss, and live event matrix pass.

### MS-005 — Rewards, moderation, media, and multi-account isolation

**Status:** Deterministic rewards, moderation, media, and client-isolation work complete. Live two-account and account-side cleanup verification remain.

**Runnable result:** authorized users exercise reward/redemption and moderation features, optional media retrieval, and two independent account/channel clients while events/actions remain isolated.

**Exit checks:** minimum scopes, confirmations, reward state transitions, ban/timeout/unban/delete flows, cache bounds/clear-data, two-client token/signal/relay/rate/revoke isolation, account-side cleanup, and full capability matrix pass.

### MS-006 — Editor/runtime UX, certification, and release

**Status:** Editor/runtime UX, documentation, examples, desktop helpers, and local package checks complete. Release certification and publication remain gated.

**Runnable result:** a new developer follows the documentation, deploys/configures the approved relay, connects a test channel in an exported game, exercises the full event/action matrix, packages Windows/Linux x86-64 builds, and installs the same immutable addon release through the approved distribution channels.

**Exit checks:** fresh-project setup, accessibility, privacy/retention/revocation/data deletion, relay operations/monitoring, token expiry, outage/recovery, source/license/lineage audit, rejected-protocol scan, clean plugin removal, bounded Redot runs, native-helper checksums, immutable GitHub release, and matching Redot Asset Library metadata pass.

## 10. Task breakdown

| ID | Milestone | Outcome | Dependencies | Expected files/systems | Acceptance and verification |
| --- | --- | --- | --- | --- | --- |
| KICK-001 | MS-001 | Repin official endpoint/event/scope/security contracts and disposition candidate features | Preflight; SRC-019 | `contracts/`, source ledger, fixture and capability manifests | Every supported route/event/scope maps to a pinned official source; every Kick.bot candidate is officially supported or explicitly unavailable; drift is classified |
| KICK-002 | MS-001 | Approve relay ownership, tenancy, hosting, cost, privacy, retention, monitoring, and incident ADR | KICK-001; RSK-001/004/005 | `docs/relay/architecture.md`, threat model | Single-tenant vs multi-tenant and operator duties are explicit; no hidden service assumption remains |
| KICK-003 | MS-001 | Approve OAuth exchange/refresh and token-custody design | KICK-002; RSK-002/007 | auth/relay protocol ADR | No client secret ships; restart, rotation, revoke, compromise, and deletion paths are complete |
| KICK-004 | MS-001 | Freeze versioned relay ingress/downlink contracts and lawful synthetic fixtures | KICK-001–003 | JSON schema, raw-body/signature fixtures, expected outcomes | Valid/invalid signature, replay, tenant mismatch, unknown version/type, size, and redaction cases are deterministic |
| KICK-005 | MS-001 | Build minimum deterministic Redot relay-contract harness | KICK-004 | `tests/run_ms001.gd`, integration-lab scene, mock downlink | One end-to-end fixture yields exactly one typed event; every rejection/degraded case is observable in a bounded run |
| KICK-006 | MS-001 | Run Gauntlet G-001 and record architecture approval | KICK-005 | QA evidence, ADR approval | All critics and deterministic retest pass within three rounds; otherwise MS-002 remains blocked |
| KICK-007 | MS-002 | Create reversible addon shell and provenance controls | MS-001; SRC-002/018 | addon root, `plugin.gd`, editor shell, lineage manifest | Enable/disable twice leaves no orphan state; every adapted file has a pinned source/disposition |
| KICK-008 | MS-002 | Adapt/harden Redot Tuber transport, errors, cancellation, redaction, and model foundations | KICK-007 | `transport/`, `models/`, `diagnostics/` | Concurrency, limits, cancel, timeout, retry/rate metadata, typed error, and secret-redaction fixtures pass |
| KICK-009 | MS-002 | Implement capability-to-minimum-scope registry | KICK-001; KICK-008 | `auth/`, capability models/docs | Each feature declares mode, scopes, relay dependency, and unavailable reason |
| KICK-010 | MS-002 | Implement browser/state/PKCE flow through approved confidential-client broker | KICK-003; KICK-008/009 | `auth/`, broker client, loopback/session binding | Success, denial, state mismatch, timeout, port conflict, browser failure, cancel, refresh, and revoke pass without embedded secret |
| KICK-011 | MS-002 | Adapt OS-vault helpers and non-secret session descriptors | KICK-003; KICK-010; SRC-018 | `auth/`, `bin/`, `native/credential-helper/` | Store/read/replace/delete/restart/locked/unavailable/corrupt/protocol-mismatch and no-plaintext checks pass on Windows/Linux x86-64 |
| KICK-012 | MS-002 | Implement one-account-per-`KickClient` facade and slot registry | KICK-009–011 | `runtime/`, auth/session models | Two clients do not share identity, token, signal, transport, rate, disconnect, revoke, or clear-data state |
| KICK-013 | MS-002 | Provide optional runtime connection/control UI | KICK-012 | `ui/` | Keyboard/gamepad, visible focus, text state, connect/cancel/disconnect/revoke/clear-data pass |
| KICK-014 | MS-002 | Deliver REST-only channel/livestream vertical slice | KICK-008; KICK-012 | channel/livestream service, example scene | Authorized identity and current channel/livestream display in a bounded clean-project run |
| KICK-015 | MS-003 | Generate/freeze typed official REST contracts and models | KICK-001; KICK-008 | contract generator, checked-in schemas/fixtures | Regeneration is deterministic; optional/unknown fields are safe; no Twitch/YouTube schema ships |
| KICK-016 | MS-003 | Implement identity, channel, livestream, category, and supported discovery services | KICK-015 | `services/`, models | Pagination/cache/manual refresh, denial, missing/offline, rate, and cancellation cases are typed |
| KICK-017 | MS-003 | Implement documented chat send/delete and other core actions | KICK-009; KICK-016 | chat/action services | Validation, scope, confirmation, success, denial, revocation, and account-side result pass |
| KICK-018 | MS-003 | Freeze rate/retry diagnostics from live evidence | KICK-016/017; RSK-003 | transport policy, diagnostics, QA | Defaults follow current server evidence; 429/retry metadata never causes a tight loop |
| KICK-019 | MS-004 | Implement official subscription lifecycle service | KICK-001; KICK-009; MS-003 | subscription models/services | Create/list/delete/reconcile, removed subscription, authorization, and limit cases pass |
| KICK-020 | MS-004 | Implement and deploy the separately approved relay service | KICK-002–004; explicit runtime/host approval | approved relay project/deployment | TLS, signature-before-parse, replay/tenant isolation, secrets, queues, retention, health, and rollback gates pass |
| KICK-021 | MS-004 | Implement authenticated relay downlink transport | KICK-004; KICK-020 | `transport/`, relay session auth | Connect/auth/rotate/reconnect/resume/cancel/expiry/outage and bounded-buffer cases pass |
| KICK-022 | MS-004 | Implement complete typed Kick event normalization | KICK-004; KICK-015; KICK-021 | `models/`, parser/generator fixtures, signals | Every frozen event type, optional field, unknown type/version, and timestamp path passes |
| KICK-023 | MS-004 | Implement deduplication, ordering metadata, relay/subscription health, and degraded mode | KICK-019–022 | runtime state/diagnostics | Replays never double-fire; loss/removal/overflow is visible; recovery follows policy |
| KICK-024 | MS-005 | Implement reward CRUD and redemption actions/events | MS-003/004 | reward/redemption services/models | Scope, state transitions, accept/reject, denial, duplicate, and cleanup pass |
| KICK-025 | MS-005 | Implement moderation actions/events | MS-003/004 | moderation services/models | Confirmation, privilege, target/state validation, timeout/ban/unban/delete, and cleanup pass |
| KICK-026 | MS-005 | Adapt bounded media cache and data clearing | KICK-022; SRC-018 | `media/`, lifecycle docs | HTTPS/type/item/aggregate/concurrency/TTL/LRU/corruption/delete tests pass |
| KICK-027 | MS-005 | Freeze public capability matrix and two-client isolation | KICK-024–026; KICK-012 | facade/models/docs/integration lab | Every action/event declares scopes, mode, relay need, errors, and isolation evidence |
| KICK-028 | MS-006 | Complete editor setup, examples, API docs, relay operations guide, MIT licenses, and lineage notices | MS-002–005 | `editor/`, examples, README/docs, licenses/notices | New developer reproduces setup; no endorsement or unsupported parity claim; clean disable passes |
| KICK-029 | MS-006 | Run live Windows/Linux x86-64 certification | KICK-028; live app/relay/accounts | retained QA evidence | Full auth/persistence/event/action/outage/rate/revoke/cleanup/accessibility matrix passes on both targets |
| KICK-030 | MS-006 | Package and verify stable release | KICK-029 | addon archive, helper manifest, GitHub release, Asset Library entry | Checksums, install root, metadata, private/public authorization, license/lineage, clean install/removal, and exact tested commit align |

## 11. QA strategy and Gauntlet gates

### Routine verification

- Pure fixture tests for scopes, contracts, models, event normalization, deduplication, redaction, rate/retry, state machines, and relay envelopes.
- Deterministic loopback HTTP/WSS lab for partial frames, disconnect, replay, delay, reordering, expiry, cancellation, queue pressure, and malformed data.
- Characterization tests for every adapted Redot Tuber/Twitcher component, followed by replacement tests for intentional Kick differences.
- Automated exclusions for Twitch/YouTube endpoints and models, Twitcher local token/key caches, global donor services, private Kick endpoints/Pusher channels/browser-cookie flows, current Sehelitar/Kick.bot and other AGPL Kickbot code, secrets, and untracked donor files.
- `redot_code_intel(action="validate")` or the available Redot validation equivalent before runtime checks.
- Bounded Redot runs with `--quit-after` of at least 2 and a wall-clock timeout; never unattended `-d`.
- Clean plugin enable/disable/re-enable, fresh-project install, and exported Windows/Linux x86-64 runs.
- Live Kick application/relay matrix for auth, persistence, refresh/revoke, subscriptions, every event/action category, rate pressure, relay outage, subscription removal, and account-side cleanup.
- Two-client tests proving no account, token, slot, signal, transport, subscription, rate, revoke, or clear-data cross-talk.
- Automated secret scanning of project files, credential-helper invocations, fixtures, logs, screenshots, reports, build artifacts, relay logs, and release archives.
- Accessibility checks for optional editor/runtime UI and performance checks for idle CPU, queue/cache bounds, reconnect churn, and node/resource cleanup.

### Frozen comparison oracles

| Oracle | Baseline | State | Permitted use |
| --- | --- | --- | --- |
| ORC-001 | KickDevDocs commit `7f7afe7ace9424f722c8e6b06e32421099c8e7f6` (2026-08-11) | OBSERVED | Endpoint/event/scope/webhook protocol authority |
| ORC-002 | Kick webhook-security and events documents, plus lawful synthetic RSA fixtures | OBSERVED | Signature, timestamp, message identity, replay, and subscription semantics |
| ORC-003 | Installed Redot `26.2.stable.official.4f5b14aba` API data and successful bounded runs | OBSERVED | Engine/API/runtime compatibility authority |
| ORC-004 | `redot-tuber` commit `029c22d7d5a5a68abacd8d12aabfea0b8e6536d8` | OBSERVED | Generic addon/auth/persistence/test/UX comparison only; never Kick protocol authority |
| ORC-005 | Live Kick developer app, staging relay, test channels, current limits | BLOCKED | Required for MS-004–MS-006 live certification; fixtures cannot substitute |
| ORC-006 | `Sehelitar/Kick.bot` commit `c542f4eff31cbba984a0723f7b17531da1334e77` | OBSERVED | Feature/UX/negative-test inventory only; never code, endpoint, event, auth, or protocol authority |

### G-001 — Relay security and contract identity gate

- **Risk:** high; defining security/transport boundary; maximum three rounds.
- **Canonical scenario:** Windows x86-64, pinned Redot build, local deterministic integration lab, one tenant/app/channel, synthetic RSA keypair, exact raw-body fixtures, authenticated mock WSS downlink, fixed event/reconnect script, retained output under `.test-output/ms001/`.
- **Measures:** every accept/reject outcome matches the fixture ledger; signature is checked before parse; zero duplicate typed emissions; zero cross-tenant delivery; unknown types stay connected; configured size/queue bounds are never exceeded; no secret or raw sensitive payload appears in diagnostics.
- **Critics:** protocol conformance, security/threat model, reliability/backpressure, developer experience, plus one unlensed read-only critic.
- **Pass:** all deterministic checks and critics pass, architecture ADR is approved, and retest output is stable. **Fail:** any false accept, duplicate, cross-tenant leak, unbounded resource, secret leak, or unresolved critical critic. **Blocked:** no approved ownership/confidential-client decision. Failure or blocked state prevents MS-002.

### G-002 — Authorization persistence and account-isolation gate

- **Risk:** high; maximum three rounds.
- **Canonical scenario:** Windows and Linux x86-64, pinned Redot build, two `KickClient` instances with distinct slots, broker success/denial/expiry fixtures, real OS-vault helpers, restart/refresh/revoke/clear-data sequence, no network for deterministic pass and live broker follow-up.
- **Measures:** state/PKCE and broker binding match ORC-001; no client secret enters the game; refresh/session restoration survives restart; revocation/deletion removes local and relay-side state; zero cross-client credential/signal/state leakage; unavailable vault has no plaintext fallback.
- **Critics:** OAuth/security, privacy/data lifecycle, multi-account isolation, accessibility/recovery UX, plus one unlensed critic.
- **Pass:** deterministic matrix passes on both OS targets and live certification is scheduled. **Fail:** secret exposure, unsafe fallback, state mismatch acceptance, incomplete deletion, or cross-talk. Failure blocks MS-003 and release.

### G-003 — Live event reliability and degraded-mode gate

- **Risk:** high; maximum three rounds.
- **Canonical scenario:** deployed staging relay, controlled Kick test channel, fixed event/action sequence, network disconnect/reconnect, duplicate delivery, relay restart, subscription removal, queue pressure, and token expiry; captures and redacted logs retained under the MS-004 QA evidence path.
- **Measures:** each official event arrives once with correct typed fields; reconnect and subscription recovery meet the frozen contract; loss/overflow is never silent; REST capability remains honest during relay outage; memory/queue use stays within configured bounds.
- **Critics:** protocol/event semantics, reliability/operations, game-integration behavior, performance, plus one unlensed critic.
- **Pass:** fixture and live matrices agree and critics pass. **Fail:** missed/duplicated events without explicit degradation, hidden subscription loss, tenant leakage, or unbounded recovery. Failure blocks rewards/moderation integration and release.

Visual raw-pixel comparison is not relevant. Canonical UI captures are paired with focus order, text status, layout bounds, scaling, and state-transition checks.

## 12. Risks and open questions

| Risk | State | Impact | Mitigation / decision deadline |
| --- | --- | --- | --- |
| RSK-001 relay ownership/tenancy | RESOLVED | Defines security, privacy, cost, support, and whether real-time functionality can ship | Self-hosted single-tenant relay/broker per integrating developer; no managed first-release service |
| RSK-002 app registration/client secret UX | RESOLVED | A distributed secret would compromise every shipped game | Developer-owned secret remains relay-side; the game uses broker endpoints and never receives it |
| RSK-003 current API/subscription limits | OPEN | Wrong defaults can throttle clients or remove subscriptions | Verify with a live app before KICK-018/MS-004 |
| RSK-004 relay privacy/retention | BLOCKED for staging users | Chat/moderation identity creates compliance and breach exposure | Data minimization, retention, deletion, policy, and operator approval in KICK-002 |
| RSK-005 subscription loss/relay operations | OPEN | Silent event loss breaks game behavior | Health, alerts, reconciliation, degraded mode, and runbook before MS-004 |
| RSK-006 desktop OS matrix | RESOLVED | Determines callback, vault, helper, and export testing | Windows/Linux x86-64 first; macOS and ARM64 later |
| RSK-007 refresh-token custody | RESOLVED | Changes local vault, relay compromise impact, revocation, and restart behavior | Relay owns Kick tokens; desktop OS vault stores only an opaque scoped broker session |
| RSK-008 managed relay abuse/isolation | NOT SELECTED | Cross-tenant data or cost abuse could affect all users | Managed multi-tenancy is outside the first-release architecture |
| RSK-009 official API/event drift | OPEN / controlled | Routes or fields may change between planning and release | Repin docs/contracts in KICK-001 and before each release; unknown-type path mandatory |
| RSK-010 donor and AGPL contamination | OPEN / controlled | Could import Sehelitar/Kick.bot or other reciprocal code, private protocols, or insecure storage | Pinned per-file reuse manifest, characterization tests, private-protocol/AGPL exclusion scans, notice audit |
| RSK-011 ordering/replay ambiguity | OPEN | Game logic may double-apply or misorder state | Preserve IDs/timestamps, deduplicate, document ordering scope, test reconnect and delayed delivery |
| RSK-012 relay availability and cost | OPEN / architecture controlled | External service outage/cost can disable events | Portable Node 24 LTS Linux x86-64 Docker deployment, REST_ONLY degradation, health/alerts, bounded queues, capacity test, explicit operator/SLA statement |
| RSK-013 public distribution approval | OPEN for release | Private development does not authorize public disclosure | Obtain explicit public-release approval before GitHub/Asset Library publication |

## 13. Release plan

### Planned artifacts

- Standalone addon source rooted at `addons/redot-kicker/`.
- Installable source archive containing only addon/runtime requirements and approved documentation/licenses/notices.
- Separate example project or clearly isolated example content.
- Versioned relay ingress/downlink schemas, synthetic fixture ledger, threat model, deployment/operations guide, and compatibility declaration.
- The separately approved relay deployment artifact with its own runtime/license/security/update record.
- Versioned Windows/Linux x86-64 credential-helper binaries, source, protocol manifest, licenses/notices, checksums, and supported-architecture table.
- API/capability matrix, developer-owned Kick app setup, relay setup, privacy/data lifecycle, incident/degraded-mode, and migration documentation.
- `docs/lineage/component-reuse.md` and `THIRD_PARTY_NOTICES.md` tracing adapted Redot Tuber/Twitcher files and rejected AGPL/private-protocol sources.
- Canonical immutable GitHub release and matching Redot Asset Library entry only after explicit public-release authorization.

### Version and compatibility

- Semantic versioning begins at `0.x`; `1.0.0` requires MS-006.
- The first release certifies exact Redot build(s) on Windows/Linux x86-64 with matching addon, helper, relay protocol, and staging evidence.
- Relay protocol changes are versioned independently enough to negotiate compatible addon/server ranges; breaking changes require migration and rollout ordering.
- macOS, ARM64, web, and mobile are separate later compatibility milestones.
- “Godot compatible” is not implied without separate evidence.

### Distribution gates

- MS-001 through MS-006 and all selected Gauntlets pass with retained evidence.
- Relay owner, host, tenancy, confidential-client custody, privacy/retention, monitoring, cost, and incident response are operationally accepted.
- No secret or user data appears in source/release artifacts, logs, fixtures, screenshots, reports, helper invocations, or examples.
- MIT license, official-doc reference terms, Kani/Twitcher/Redot Tuber lineage, non-endorsement language, and AGPL/private-protocol exclusions pass audit.
- Clean install/disable/removal, exported login/persistence, full live event/action matrix, relay outage/recovery, subscription reconciliation, revocation, data deletion, and account-side cleanup pass.
- Every shipped helper and relay artifact has version, source, license, checksum/signature, supported platform/protocol, rollback, and update evidence.
- The GitHub tag/archive and Redot Asset Library entry resolve to the exact tested commit/archive and install only under `res://addons/redot-kicker/`.
- Public publication occurs only after explicit visibility/disclosure approval.

## 14. Out of scope

- Private Kick frontend/Pusher endpoints, browser-session-cookie automation, scraping, reverse engineering, current Sehelitar/Kick.bot code/protocols, or the historical AGPL Kickbot.
- Direct localhost webhook delivery as an end-user release architecture.
- Shipping a maintainer/developer client secret inside a game or addon.
- Pretending `REST_ONLY` provides official real-time events.
- A shared lowest-common-denominator streaming runtime or dependency on another Redot streaming addon.
- Mechanically renaming Redot Tuber/Twitcher or carrying YouTube/Twitch models, endpoints, auth storage, branding, or global singletons.
- Introducing a second relay runtime or provider-specific deployment without a separate approved change.
- C#, .NET, or GDExtension inside the Redot plugin.
- Web/mobile, macOS, or ARM64 certification in the first Windows/Linux x86-64 release.
- Redistributing remote Kick media or branding without verified rights.
- Promising an SLA, managed service, or public repository before explicit approval.

## Decisions so far

- Full official Kick functionality is the goal; REST-only is a transparent degraded mode, not the finished parity claim.
- The product is a standalone typed-GDScript Redot addon with Kick-prefixed public APIs and no shared streaming runtime.
- Official public Kick APIs only; private endpoints and AGPL Kickbot code are rejected. Sehelitar/Kick.bot is retained solely as a pinned feature/UX/negative-test inventory.
- Real-time events require a separately deployed public webhook relay with signature verification, tenant isolation, authenticated downlink, and observable health.
- Each integrating developer owns the Kick application used by their game; no shared embedded client secret is allowed.
- The first-release relay/broker is self-hosted and single-tenant per integrating developer. The relay owns the Kick client secret and OAuth access/refresh tokens.
- The desktop OS vault stores only an opaque scoped broker-session credential; `user://` stores only a non-secret session descriptor.
- Persistent desktop login, one-account-per-client session slots, Windows/Linux x86-64 first, macOS/ARM64 later, MIT licensing, lineage tracking, and GitHub/Asset-Library release conventions follow the Redot Tuber baseline.
- Generic Redot Tuber foundations may be adapted from pinned commit `029c22d7d5a5a68abacd8d12aabfea0b8e6536d8` with characterization tests and per-file provenance; the finished addon has no donor runtime dependency.
- The separately deployed relay uses TypeScript on Node.js 24 LTS and a portable Linux x86-64 Docker image; a specific hosting provider remains the integrating developer's choice.

## Active implementation frontier

MS-001 froze the official contract ledger, ingress/downlink schemas, security invariants, lawful synthetic fixtures, and deterministic Redot harness against KickDevDocs commit `7f7afe7ace9424f722c8e6b06e32421099c8e7f6`. G-001 passed 54/54 checks after fixing fail-closed replay capacity, overflow retry, Redot numeric-ID normalization, and receipt-time semantics. The retained evidence is under `docs/gamedev/gauntlet/MS-001/`.

The deterministic Redot client frontier is complete: brokered persistent authorization, distinct OS-vault helpers, capability-gated official REST services, typed events, bounded HTTP/media/event transports, account isolation, setup/runtime UI, examples, documentation, and local package checks all pass their retained suites. Evidence is under `docs/gamedev/gauntlet/client-implementation/` and summarized in `source-of-truth.xlsx`.

The deterministic implementation portion of KICK-020 is complete, including the TypeScript/Node.js 24 LTS relay, pinned Linux x86-64 image, encrypted persistence, operation proxy, webhook/WSS boundary, tests, and operator runbook. The active frontier is the external portion of KICK-020 plus KICK-029: deploy a developer-owned public staging instance and run the live Kick/Windows/Linux certification matrix. Stable public release work in KICK-030 remains unauthorized.

After that deterministic gate, the remaining external work is Linux desktop Secret Service certification, live OAuth/API/webhook staging, two-real-account isolation, operator-specific monitoring/privacy approval, and release certification.
