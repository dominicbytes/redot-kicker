# Third-party notices

`redot-kicker` is an independent MIT-licensed Redot addon for Kick. It is not affiliated with or endorsed by Kick, Redot Engine, Godot Engine, YouTube, Twitch, or the referenced projects.

Selected generic foundations were adapted from `dominicbytes/redot-tuber` commit `029c22d7d5a5a68abacd8d12aabfea0b8e6536d8`, which is MIT licensed. Redot Tuber in turn preserves notices for generic material adapted from `dominicbytes/twitcher` and the original [`kanimaru/twitcher`](https://github.com/kanimaru/twitcher), both MIT licensed. Per-file dispositions are recorded in `docs/lineage/reuse-manifest.json`.

Kick protocol behavior, routes, scopes, and events are derived only from the official [`KickEngineering/KickDevDocs`](https://github.com/KickEngineering/KickDevDocs) and official Kick OpenAPI document. Those references are documentation inputs and are not redistributed as source code.

`Sehelitar/Kick.bot` was used only as a feature/UX/negative-test inventory. Its AGPL code, private endpoints, cookie flow, and private Pusher protocol are not included or used as protocol authority.

The relay's production npm dependencies are `ws` 8.21.3 (MIT), `json-bigint` 1.0.0 (MIT), and its transitive dependency `bignumber.js` 9.3.1 (MIT). Their license files remain in the installed package tree. TypeScript and `@types` packages are development-only dependencies and are recorded exactly in `relay/package-lock.json`.
