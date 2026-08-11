# G-001 retained evidence

## Canonical command

```powershell
& 'D:\Claude Vault\redot\.tools\redot\26.2-stable-windows\redot.windows.editor.x86_64.console.exe' --headless --path 'D:\Claude Vault\redot\plugins\redot-kicker' --script res://tests/run_ms001.gd --quit-after 2
```

## Final result

```text
Redot Engine LTS v26.2.stable.official.4f5b14aba
MS-001 PASS: 54 checks
```

The integration-lab main scene also completed a bounded `--quit-after 3` headless run with exit code 0 and no project parse, resource-load, runtime, or warning output.

## Evidence hashes

| Artifact | SHA-256 |
| --- | --- |
| `.test-output/ms001/latest.json` | `B9921B9A5FDC6638F9BB5AC6521146C06B650DF3089AD0540EAF349A8FD69707` |
| `kick_api_contract.json` | `41F984F7CCE1968887E6C518EA1012FC9EA25183D6B1F72C095E024201106833` |
| `relay_ingress.schema.json` | `1627F0D40E3EF82088BF629C35B5634295AE3C172A65B10FD900D01E10A79617` |
| `relay_downlink.schema.json` | `A3FBA5C01A67AF039BD5C54ED01CC5A0235677DA3555CB7269DF262B23A41466` |
| `broker_contract.json` | `FD2D6662F0729C6A0443A92CF1B1F36EEED9882482A2D61D34D3842BA3128455` |
| `fixture_ledger.json` | `93670350DF7F9B92A8BE6C31AC67036DC127D7B167F3BB04F816847981735875` |
| `tests/run_ms001.gd` | `3482E3D7A3FC8A60AA373F35958E4DB47CA5DACFAF8812788EA5262241640997` |

The generated RSA private key exists only in test-process memory. No key or credential is retained in these artifacts.
