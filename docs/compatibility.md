# Compatibility

| Target | Status |
|---|---|
| Redot 26.2 / Windows x86-64 | deterministic addon gates pass; Credential Manager helper built and store/read/delete tested |
| Redot 26.2 / Linux x86-64 | helper built and headless protocol-tested; desktop Secret Service and exported-game certification pending |
| Relay / Linux x86-64 | Node.js 24 LTS Docker implementation and deterministic tests complete; container and live public deployment certification tracked separately |
| macOS | planned after Windows/Linux are solid |
| Windows/Linux ARM64 | planned after the initial x86-64 release |
| Web/mobile | not in the first desktop architecture |

The installed Redot build is authoritative. Upstream Godot documentation is a reference, not proof of Redot compatibility. The addon is typed GDScript; only the small standalone OS-vault helper is native.
