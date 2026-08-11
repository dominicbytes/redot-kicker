# Redot Kicker addon

Install this directory at `res://addons/redot-kicker/` and enable **Redot Kicker** in Project Settings > Plugins.

`KickClient` is the public one-account-per-node facade. It authorizes through a developer-hosted single-tenant relay, persists only an opaque broker session in the OS vault, exposes typed service objects, and emits typed events over an authenticated WSS downlink. It never accepts a Kick client secret or Kick OAuth token.

Start with the repository's `examples/basic_connection.tscn`, `docs/api.md`, `docs/capability-matrix.md`, and `docs/relay/deployment-contract.md`.

Windows and Linux x86-64 are the initial targets. macOS and ARM64 are intentionally deferred until both initial platforms are certified.
