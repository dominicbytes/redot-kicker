# Capability matrix

The integrating game requests named capabilities. Redot Kicker derives the minimum official scopes and the relay enforces the same operation allowlist. Empty-scope operations still require an authorized broker session unless the contract explicitly says otherwise.

| Capability | Minimum scope | Relay event link | Operations |
|---|---|---:|---|
| `identity.read` | `user:read` | No | users, token introspection |
| `channel.read` | `channel:read` | No | get current/by ID/by slug channel |
| `channel.manage` | `channel:write` | No | update channel metadata |
| `categories.read` | none | No | v2 categories; deprecated v1 lookup |
| `livestreams.read` | none | No | v2 livestreams, by-user, stats; deprecated v1 list |
| `chat.write` | `chat:write` | No | send user/bot chat, reply |
| `chat.delete` | `moderation:chat_message:manage` | No | delete chat message |
| `events.receive` | `events:subscribe` | Yes | WSS downlink and relay public-key verification support |
| `events.manage` | `events:subscribe` | Yes | list/create/delete webhook subscriptions |
| `rewards.read` | `channel:rewards:read` | No | list rewards/redemptions |
| `rewards.manage` | `channel:rewards:write` | No | reward CRUD and accept/reject redemptions |
| `moderation.ban` | `moderation:ban` | No | ban, timeout, unban |
| `kicks.read` | `kicks:read` | No | KICKs leaderboard |
| `streamkey.read` | `streamkey:read` | No | **Unavailable:** official scope exists but the frozen OpenAPI exposes no route |

## Capability modes

- `DISCONNECTED`: no broker authorization; no privileged operations.
- `REST_ONLY`: broker authorization is healthy; official REST actions work, but event delivery is unavailable or degraded.
- `RELAY_CONNECTED`: broker authorization and authenticated WSS event downlink are healthy.

`events.receive` does not promise event delivery while the client is in `REST_ONLY`. Relay loss, queue pressure, subscription mismatch, or ticket failure returns the client to that honest degraded mode.

## Confirmations

Channel changes, chat deletion, event-subscription deletion, reward/redemption writes, and moderation writes require explicit confirmation. Confirmation is checked both before the request and at the relay operation boundary; it is not inferred from a button press elsewhere in the game.

The canonical operation definitions are `addons/redot-kicker/contracts/kick_api_contract.json` and `KickCapabilityRegistry.OPERATIONS`.
