# Data lifecycle

| Data | Location | Retention/deletion |
|---|---|---|
| Kick client secret | relay secret store only | rotated/deleted by relay operator |
| Kick access/refresh tokens | relay token store only | refresh lifecycle; deleted on revoke/account deletion |
| Opaque broker session | Windows Credential Manager or Linux Secret Service | replaced on rotation; deleted on disconnect/clear-data |
| Non-secret session descriptor | `user://redot-kicker/sessions/` | deleted on disconnect/clear-data |
| OAuth state/PKCE | relay memory or short-lived encrypted request store | consumed or expired; never sent to the game |
| WSS ticket | relay/client memory | single use and short expiry |
| Webhook raw body | relay memory | verification and dispatch only; never persisted |
| Replay identity | bounded relay/client cache | message ID plus expiry only |
| Write idempotency | encrypted relay state | hashed key/request plus sanitized result; 24-hour bounded TTL |
| Remote media | bounded memory; optional hashed disk cache | TTL/LRU eviction or `KickMediaCache.clear_data()` |

`clear_local_data(false)` deletes the local descriptor, OS-vault broker credential, event state, and media cache even if the relay is unavailable. `disconnect_account(true)` additionally asks the relay to revoke the Kick authorization and delete its token state; any remote failure is returned after local deletion so the game can direct the user/operator to retry.

Examples, tests, logs, screenshots, and support bundles must never contain credentials, Kick tokens, OAuth codes/state/verifiers, raw authorization headers, or unredacted chat/moderation payloads.
