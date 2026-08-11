# Redot Kicker credential helper

These minimal standalone helpers isolate operating-system vault access from GDScript while keeping the addon independent of a native runtime library.

- Windows x86-64: Windows Credential Manager (`CredWriteW`, `CredReadW`, `CredDeleteW`)
- Linux x86-64: Secret Service via `libsecret-1`

Build with CMake 3.20 or newer. The release manifest records the SHA-256 of each shipped executable. See `PROTOCOL.md` for the secret-safe stdin/stdout contract.

Source lineage: substantially adapted from the MIT-licensed Redot Tuber credential helper at commit `029c22d7d5a5a68abacd8d12aabfea0b8e6536d8`, with a new protocol identity, vault namespace, labels, and broker-session semantics.
