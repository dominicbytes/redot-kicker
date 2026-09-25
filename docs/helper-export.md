# Credential helpers in exported games

Enable Redot Kicker before exporting. The export hook registers the Windows/Linux x86-64 helper as an external sidecar, not as a file embedded in the PCK. Keep the redot-kicker directory beside the exported game executable:

    game.exe (or game on Linux)
    game.pck (if not embedded)
    redot-kicker/
      redot-kicker-credential-helper.exe (Windows)
      redot-kicker-credential-helper     (Linux)

Ship only the target platform's helper. Moving the game directory preserves runtime resolution, including paths with spaces and Unicode. Editor/source runs continue to use the addon's bin/<platform>/x86_64/ path. Unsupported operating systems and architectures resolve to an unavailable helper rather than an unrelated binary. The explicit helper path override remains available to integrators.

Linux packages must preserve mode 0755. The hook applies it on native Linux exports; when cross-exporting from Windows, set/preserve it during Linux package assembly before making the install directory read-only. Do not rely on a game changing permissions at startup. A missing or non-executable helper fails explicitly; there is no plaintext credential fallback.

Path selection, lowercase host feature-tag behavior, and required Redot API availability were tested, but the export callbacks were not executed and sidecar copying was not verified. Exact 26.3 export templates, successful editor/export completion, and clean Windows/Linux runtime certification are still required before release. No export preset, signing configuration, or user credential is changed.
