# Public API

## `KickClient`

One `KickClient` owns one authorized Kick identity/channel and one stable session slot. Create separate clients with separate slots for multiple accounts.

```gdscript
var error := client.configure(config, capabilities, "primary")
var authorized := await client.connect_account()
var restored := await client.restore_account()
var revoked_error := await client.disconnect_account(true)
```

Core methods:

- `configure(config, capabilities, session_slot, credential_client?, descriptor_store?)`
- `connect_account()` / `begin_account_authorization()` / `wait_for_account_authorization()`
- `restore_account()` / `rotate_broker_session()`
- `connect_relay()` / `disconnect_relay()`
- `disconnect_account(revoke)` / `clear_local_data(revoke)`
- `invoke(operation_id, query, path_parameters, body, confirmed, idempotency_key, cancellation)`

`invoke()` is an escape hatch within the frozen official surface. It accepts an operation ID such as `channels.get`; it cannot send an arbitrary method or URL.

## Service objects

- `identity`: `get_current`, `get_users`, `introspect`
- `channels`: `get_current`, `get_by_user_ids`, `get_by_slugs`, `update`
- `categories`: cursor-based v2 `list`, plus clearly named deprecated v1 methods
- `livestreams`: cursor-based v2 `list`, `get_by_user_ids`, `stats`, deprecated v1 list
- `chat`: `send_message`, `delete_message`
- `subscriptions`: `list`, `create`, `delete`
- `rewards`: reward `list/create/update/delete`, redemption `list/accept/reject`
- `moderation`: `ban`, `timeout`, `unban`
- `kicks`: `leaderboard`
- `media`: bounded `fetch_texture` and `clear_data`

Read operations return `KickApiResult`, or `KickApiPage` for cursor-paginated methods. Results carry typed data where a stable official model exists, plus typed `KickApiError`, HTTP status, request ID, retry-after, and rate-limit metadata.

## Signals

Lifecycle:

- `connection_state_changed(previous, current, reason)`
- `authorization_url_ready(url)`
- `account_connected(descriptor, restored)` / `account_disconnected()`
- `capability_mode_changed(mode)`
- `rate_limit_observed(operation_id, remaining, reset_unix, retry_after_seconds)`
- `queue_pressure(queued, capacity)` / `error_occurred(error)`

Events:

- `event_received`
- `chat_message_received`
- `channel_followed`
- `subscription_event_received`
- `reward_redemption_updated`
- `livestream_updated`
- `moderation_event_received`
- `kicks_gifted`
- `unknown_event_received`

All use a typed `KickEvent`. It includes common broadcaster/actor users and normalized event-specific fields while preserving a copied payload for forward-compatible optional fields. Unknown event types stay isolated and never tear down the connection.

## Cancellation and retries

Pass a `KickCancellationToken` to any supported operation. GET-like upstream operations may retry bounded transient failures. Writes do not automatically retry, preventing duplicate chat, moderation, or reward actions. The relay must independently deduplicate any explicitly retryable broker request.
