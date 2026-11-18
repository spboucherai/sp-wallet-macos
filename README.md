# SP Wallet for macOS

Native macOS client (Swift 6, SwiftUI, AppKit — no web view) of the private multi-chain wallet **wallet.spboucher.ai**.
The isolated signer of the MacLustr cluster remains the only holder of the keys: this app displays, prepares and carries the
owner's passkey approvals; it never holds a private key or a recovery phrase.

- Bundle `ai.spboucher.spwallet` (team 3YM54G49SN), macOS 15+, universal, App Sandbox + Hardened Runtime, Developer ID, notarized.
- Development variant `SP Wallet Dev` (`ai.spboucher.spwallet.dev`): local throwaway stack only, software passkey, self-test.
- Engine room: the shared package `../SPWalletCore` (models, API client, canonical objects and passkey binding, address validation).

| Document | Content |
|---|---|
| `docs/FEATURE_MATRIX.md` | parity with the backend, feature by feature, with what was really verified |
| `docs/SECURITY_AUDIT.md` | what the client holds, the authorization path, hardening, known limits |
| `docs/TEST_REPORT.md` | what was run, results, what was not verified |
| `docs/FEATURE_GUIDE.md` | conventions for writing a feature |

## Build, test, release

```
python3 Scripts/provision.py          # bundle ids, Associated Domains, Developer ID profiles (existing certificate and API key)
Scripts/build.sh Debug                # development variant
Scripts/t.sh                          # unit tests
SPW_NATIVE_PORT=8760 ../SPWalletCore/Scripts/dev-stack.sh up-fork     # throwaway backend (test keys, Base = local fork)
Scripts/run-dev.sh --selftest         # end-to-end checks of the signed app   (--section <name> --shot out.png for a capture)
Scripts/release.sh && Scripts/verify-release.sh && Scripts/notarize.sh        # dist/SP Wallet.app, dist/SPWallet-<version>.dmg
```

Layout: `App/` shell and state · `Core/` app-side adapters (passkey sheet, app lock, snapshots, formatting) · `Components/` design
system and the transaction review · `Features/<Section>/` one folder per sidebar section · `Tests/` · `Scripts/` · `docs/`.

Author: Simon-Pierre Boucher — contact@spboucher.ai
