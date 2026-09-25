# Helper export source lineage

The 2026-09-24 credential-helper path resolver, export hook, lifecycle wiring and focused path test were adapted from the MIT-licensed [dominicbytes/redot-tuber](https://github.com/dominicbytes/redot-tuber) UP-06 working-source exemplar. Copyright remains Dominic Bytes under this repository's MIT license. They are not copies from the older pinned donor commit in the original reuse manifest.

The Tuber exemplar was uncommitted at adaptation time (base commit `c7ca436192f167289c9d1d4e2638ca1a9a1199a2`); the exact source snapshot is identified by these SHA-256 values, not falsely attributed to that base commit:

| Tuber source | SHA-256 |
| --- | --- |
| addons/redot-tuber/auth/credential_helper_paths.gd | 9ec55e218a513164dc4917cb87d3510be429bebe5f2f6250676e84064cb4f969 |
| addons/redot-tuber/editor/credential_helper_export.gd | f0a786643d2cc4d08af0ced8c0663efaeaf373343301b46b0b485032ddb61aa1 |
| addons/redot-tuber/tests/run_helper_export_paths.gd | 828091c14b631cba782d52f2329f4ab5660f41dc80b972556c641d736d72efa3 |

Targets are the matching paths under this addon's own directory. Names, binary paths and plugin identifiers were adapted for this plugin; the lowercase feature selector and exact-Redot API tests were developed together across the four plugins. Existing helper-client path resolution and EditorPlugin registration use the shared layout. No donor runtime dependency is introduced. Future Tuber streaming-helper changes are not implied by this source record.
