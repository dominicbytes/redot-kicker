# Credential helper protocol (`RKCH/1`)

The helper receives one four-line request on standard input and returns one four-line response on standard output. Secrets are never passed through process arguments, environment variables, files, or logs.

```text
RKCH/1
ping|store|read|delete
BASE64_UTF8_TARGET
BASE64_UTF8_OPAQUE_BROKER_SESSION_OR_EMPTY
```

```text
RKCH/1
OK|NOT_FOUND|UNAVAILABLE|LOCKED|DENIED|PROTOCOL_ERROR
BASE64_UTF8_OPAQUE_BROKER_SESSION_OR_EMPTY
SAFE_NON_SECRET_DETAIL_OR_EMPTY
```

Targets are limited to 512 bytes and broker sessions to 4096 bytes. `store` replaces the target through the operating-system vault. Windows uses a generic Credential Manager target named `RedotKicker:<publisher>/<application>/<slot>`. Linux uses the default Secret Service collection and the `org.redotengine.redot_kicker` schema. There is no plaintext fallback.

The stored value is a scoped, revocable Redot Kicker broker session. It is never a Kick client secret, access token, or refresh token.
