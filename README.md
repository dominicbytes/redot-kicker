# Redot Kicker

Redot Kicker is a standalone, typed GDScript addon for connecting Redot games to a consenting player's Kick account and channel. It targets Redot 26.3-rc.1 on Windows and Linux x86-64 first. Windows 26.3 runtime regression tests cover event delivery and account/session isolation; this is not editor/export certification. The independently reproduced 26.3 headless-editor crash and clean Windows/Linux exported-game checks remain release gates.

This repository is **not a Twitcher fork** and will not be merged into Twitcher. Its interaction scope was informed by [dominicbytes/redot-twitcher](https://github.com/dominicbytes/twitcher); the original project is [kanimaru/twitcher](https://github.com/kanimaru/twitcher). Generic implementation foundations were adapted from the independent MIT-licensed Redot Tuber project with file-level provenance in [`docs/lineage/reuse-manifest.json`](docs/lineage/reuse-manifest.json).

## Current status

See the [Redot 26.3 update and validation notes](docs/validation-26.3.md) for these repairs and the remaining release gates.

The Redot client addon is implemented against the official Kick surface frozen on 2026-08-11:

- browser authorization through a confidential self-hosted broker;
- persistent opaque broker sessions in Windows Credential Manager and Linux Secret Service, with no plaintext fallback;
- one account/channel per `KickClient`, stable session slots, rotation, restore, revoke, and clear-data;
- all 28 frozen official operation contracts, including users, channels, categories, livestreams, chat, event subscriptions, rewards/redemptions, moderation, and KICKs;
- authenticated WSS event downlink, bounded queues, deduplication, degraded `REST_ONLY` mode, and typed signals for all ten current official event types;
- typed models, errors, cancellation, rate/retry diagnostics, media cache, editor setup, runtime connection UI, and examples;
- Windows x86-64 vault helper built and tested; Linux x86-64 helper built and protocol-tested, with live desktop Secret Service certification still required.
- production relay source in TypeScript on Node.js 24 LTS, with encrypted state, OAuth/PKCE, all 28 allowlisted operations, idempotent writes, signed webhook ingress, authenticated WSS downlink, and a hardened Linux x86-64 Docker deployment.

The implementation is deterministic-test complete, but live Kick and operator-deployment certification still require a developer application, public staging relay, test channel, Linux desktop Secret Service session, and the operator's TLS/hosting/monitoring/privacy choices. The version therefore remains `0.1.0-dev`; the addon does not claim a production release yet.

## Why a relay is required

Kick's confidential OAuth token exchange requires a client secret, and official real-time events arrive at a public HTTPS webhook. A distributed game cannot safely hold either boundary. Each integrating developer therefore self-hosts one single-tenant relay/broker for one Kick application:

```text
Redot game -- HTTPS/WSS --> developer relay -- OAuth/REST/webhooks --> Kick
     |                           |
     | opaque broker session    | Kick client secret and tokens
     v                           v
Windows Credential Manager   relay secret store
or Linux Secret Service
```

The game never receives a Kick client secret, access token, or refresh token. It stores a non-secret descriptor under `user://redot-kicker/sessions/` and an opaque scoped broker credential in the operating-system vault. WSS uses a separate short-lived, single-use ticket in an `Authorization` handshake header.

See [`docs/relay/deployment-contract.md`](docs/relay/deployment-contract.md), [`docs/relay/architecture.md`](docs/relay/architecture.md), and [`docs/relay/threat-model.md`](docs/relay/threat-model.md).

The deployable relay, Docker Compose example, and operator runbook are in [`relay/`](relay/README.md).

## Install

Copy `addons/redot-kicker/` into the target project as `res://addons/redot-kicker/`, then enable **Redot Kicker** under **Project > Project Settings > Plugins**. Do not add an autoload; each `KickClient` owns one isolated account/session.

The matching helper must remain at:

- `res://addons/redot-kicker/bin/windows/x86_64/redot-kicker-credential-helper.exe`
- `res://addons/redot-kicker/bin/linux/x86_64/redot-kicker-credential-helper`

Linux exports must preserve the helper's executable bit and provide a desktop Secret Service implementation.

## Minimal use

```gdscript
var client := KickClient.new()
add_child(client)

var config := KickClientConfig.new()
config.relay_base_url = "https://kick-relay.example.com"
config.publisher_id = "my-studio"
config.application_id = "my-kick-app"

var error := client.configure(config, PackedStringArray([
    "identity.read",
    "channel.read",
    "chat.write",
    "events.receive",
    "events.manage",
]), "primary")
if error == null:
    client.chat_message_received.connect(_on_kick_chat)
    client.connect_account()
```

On later launches, call `await client.restore_account()`. A connected client exposes service objects such as `client.channels`, `client.livestreams`, `client.chat`, `client.subscriptions`, `client.rewards`, `client.moderation`, and `client.kicks`.

Destructive calls require an explicit `confirmed = true` argument. The generic `client.invoke()` accepts only a frozen operation ID; no arbitrary Kick URL can cross the broker boundary.

See [`examples/basic_connection.tscn`](examples/basic_connection.tscn), [`docs/api.md`](docs/api.md), and [`docs/capability-matrix.md`](docs/capability-matrix.md).

## Security rules

- Never put a Kick client secret or token in a scene, resource, `project.godot`, command line, environment variable, fixture, screenshot, or log.
- Do not replace the broker with private Kick frontend routes, cookies, scraping, or Pusher channels.
- Treat `REST_ONLY` and `RELAY_CONNECTED` as different capability modes.
- Keep the relay single-tenant, verify webhook signatures against the exact raw body before parsing, and bind every event to its app/session/channel/subscription.
- Strip stream keys and RTMP URLs at the relay. The client also strips them defensively.
- Publish relay ownership, privacy, retention, revocation, monitoring, and incident details before onboarding users.

## Development

The deterministic checks run against the installed Redot build:

```powershell
& $env:REDOT_BIN --headless --path . --script res://tests/run_ms001.gd --quit-after 1200
& $env:REDOT_BIN --headless --path . --script res://tests/run_core_suite.gd --quit-after 1200
& $env:REDOT_BIN --headless --path . --script res://tests/run_http_transport_suite.gd --quit-after 2000
& $env:REDOT_BIN --headless --path . --script res://tests/run_media_suite.gd --quit-after 1200
& $env:REDOT_BIN --headless --path . --script res://tests/run_project_check.gd --quit-after 1200
```

The Credential Manager smoke test creates and deletes one Kicker-specific test record:

```powershell
& $env:REDOT_BIN --headless --path . --script res://tests/run_credential_helper_smoke.gd --quit-after 600
```

See [`docs/testing.md`](docs/testing.md) for the current certification boundary.

The relay checks run separately:

```powershell
Set-Location relay
npm.cmd ci --ignore-scripts
npm.cmd test
npm.cmd audit --omit=dev
docker build --platform linux/amd64 -t redot-kicker-relay:test .
```

## License and independence

Redot Kicker is MIT licensed. It is independent of and not endorsed by Kick, Redot Engine, Godot Engine, Twitcher, or the other referenced projects. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Notes

I vibe coded this in GPT Sol 5.6. Use at your own risk. Actual programmers are welcome to submit PR's and feedback.

## About Dominic Bytes

Greetings! I am Dominic Bytes, the synth walker. I hail from the distant future. Where brains occupy robot bodies, time travel is a trip to the corner store, and the neon glow of our attire is powered by the light of our souls. Join me on a 1.21 gigawatt powered journey of chill vibes with gaming, anime, movies, and more!

- [Website](https://dominicbytes.carrd.co/)
- [X](https://x.com/DominicBytes)
- [Twitch](https://www.twitch.tv/dominicbytes)
- [YouTube](http://www.youtube.com/@DominicBytes)
- [Kick](https://kick.com/dominicbytes)
