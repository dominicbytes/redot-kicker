# Redot 26.3 development update

Target tested: Windows x64 Redot `26.3.rc.1.official.704b10a8e`. This is a source update, not a stable release or exported-game certification.

- Fixed first-event delivery in the actual WebSocket receiver.
- Isolated broker sessions for different accounts and installations sharing a local slot name; only the credential-authorized session is rotated or revoked.
- Bounded receive/delivery queues and rolling game-event deduplication; signed webhook replay protection remains fail-closed.
- Added Windows/Linux x64 credential-helper export hooks and executable-relative runtime paths. Export callbacks, copied sidecars and Linux package permissions still require actual exported-game testing.

Validation: seven Redot source-test processes passed with no errors/warnings (166 assertions plus a 71-script project check); Node 24.11.1 relay tests passed 19/19. Loopback WebSocket, HTTP and mocked platform/vault boundaries do not certify live Kick, desktop Secret Service or relay deployment.

The independently reproduced 26.3 headless-editor crash remains an external release blocker. Preserve version `0.1.0-dev`; do not infer full editor/export compatibility from script tests. See [helper export requirements](helper-export.md) and [testing](testing.md).
