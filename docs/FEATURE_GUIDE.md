# SP Wallet macOS — guide for writing a feature

Native macOS client (Swift 6, SwiftUI, AppKit where needed, macOS 15+) of the SP Wallet backend. **No web view, ever.**
The engine room is the shared Swift package `../SPWalletCore` (owned by another session: READ-ONLY for you — never edit it; report
what is missing or wrong instead). Backend reference (READ-ONLY): `~/Desktop/Cluster/projets/sp-wallet-native` (TypeScript; web screens
in `apps/web/src/screens/*.tsx` show what the product does; `services/api/src` is the truth about what is really operational).

## Non-negotiable rules (a financial app)

1. **Never invent data.** No placeholder balance, price, position, PnL or status. Unknown = "—" or an explicit "Indisponible" state.
   A value read from a failed source is shown as unavailable, never as zero.
2. **Never infer success.** Only the server's state is shown, with its exact meaning. "broadcast"/"sent"/"submitted" is not
   "confirmed". A bridge is done only when the destination network confirmed. Use `ErrorText.state` / `StatusPill` for proposals.
3. **Every operation that moves funds or grants authority goes through the Core's verified approval path**: prepare → the Core
   verifies that the WebAuthn challenge is the SHA-256 of the canonical object (`VerifiedApproval`) → a REVIEW SHEET that renders the
   fields OF THAT VERIFIED OBJECT (not the server's summary) in full (full addresses, exact amounts, fees, minimum received, slippage,
   contracts called, spend approvals, expiry) + `BindingProof(digest:expiry:)` → an explicit button → `model.authenticator` (passkey).
   If the Core throws `ApprovalError.unsupported` the UI says the operation cannot be verified and offers NO way around it.
   Nothing is ever triggered by merely viewing a quote, a market or a screen. No auto-approve, no default-max leverage.
4. **Simulation / paper / testnet / real are visually distinct** (colour + label on every figure and every button). Never add figures
   across modes. Labels: `ProvenanceTag(p: .simulated)`, `.estimate`, `.verified`, `.stale`, `.unavailable`, `.ai`.
5. **Capabilities come from the server** (execution endpoints, capability lists, locks). A feature the server reports as off is shown
   as off WITH the server's reason; do not hide it and do not pretend it works. Never hard-code a list of networks/markets/venues.
6. Risk is spelled out before any leveraged or automated action: notional, leverage, margin, estimated liquidation price, fees,
   funding, loss risk, collateral at stake. Never promise profitability. Backtests and AI analyses are labelled as such.
7. Offline / signed-out (`!model.canOperate`): reads may show cached data with its date; every operation control is disabled.
8. Remote content (NFT media, metadata, names) is untrusted: images only through the backend's media proxy when the Core offers it,
   decode with ImageIO/NSImage, never execute, never render HTML/SVG scripts, never open non-https links, show unknown/unsafe flags.
9. No secret in logs, UserDefaults or files. API keys shown once are never persisted by the app.
10. UI text in **French** (code, identifiers and comments in English). File header on every file:
    `// Author: Simon-Pierre Boucher — contact@spboucher.ai` / `// File: <path>` / `// Description: <what and why>`.

## App conventions

- Screens receive `let model: AppModel` **as a parameter** (never `@Environment(AppModel.self)`: it crashes on macOS 27 inside
  Table cells, sheets, menus, toolbars). Pass it explicitly to every sub-view and sheet.
- `model.client` (`APIClient`) → build the Core APIs yourself: e.g. `SwapAPI(model.client)`. `model.authenticator` is the passkey.
  `model.canOperate`, `model.isOffline`, `model.networks?.value`, `model.portfolio?.value`, `model.accounts?.value`,
  `model.network(id)`, `model.address(on:)`, `model.price(symbol)`, `model.currency`, `model.settings`, `model.describe(error)`
  (French error text; always use it for errors), `await model.refreshAll()` after an operation changes balances.
- Building blocks in `Components/`: `Page(title, subtitle:) { }`, `Card(title, trailing:) { }`, `Field(label:value:mono:)`,
  `Banner(.info/.warning/.danger/.ok, text)`, `ProvenanceTag`, `EmptyState`, `AssetBadge`, `StatusPill(raw:)`, `ReviewLines(lines:)`
  with `ReviewLine(label:value:style:)`, `TransactionReview(intent:digest:network:ownAddresses:warnings:extra:)` (any `Intent`-based
  operation: transfer, swap, bridge, xswap, venue deposit, GMX), `BindingProof(digest:expiry:)`, `ProposalStatusView(proposal:)`,
  `NetworkPicker`, `AssetPicker`, `Fmt.amount/fiat/price/percent/date/relative/short/chunked`, `Theme.positive/negative/warning`,
  `copyToPasteboard`, `Notifier.post(title:body:)` (terminal outcomes only), `SnapshotStore.shared.save/load` (offline cache of
  read-only answers), `JSONValue.displayText`.
- Reference implementation of a complete operation flow: `Features/Send/SendFlow.swift` (state machine, idempotency key kept while
  the form does not change, lost-answer recovery without signing twice, tracking until terminal) and `Features/Send/SendView.swift`
  (form, review sheet, tracking). Follow that shape: an `@MainActor @Observable final class XxxFlow` + views.
- State: `@Observable` classes, `@State`/`@Bindable`. Swift 6 strict concurrency (`complete`): no data race warnings, no `@unchecked`
  shortcuts; network calls off the main thread via the Core's async APIs. No polling faster than needed; stop polling when the view
  disappears (`.task` cancellation) and when `!AppActivity.isActive`. Prefer the Core's streams (SSE / QuoteStream websocket) for
  live market data where they exist.
- Charts: Swift Charts. Tables: SwiftUI `Table` for long lists (virtualized); never build a 500-row `VStack`.
- Development-only code is inside `#if SPW_DEV` (never compiled in Release).
- Your files live ONLY in your feature folder(s) under `Features/<Name>/`. Do not edit `App/`, `Components/`, `Core/`, other
  features, `project.yml`, `Scripts/`. If you need a change there, describe it in your report. Your entry view replaces the stub in
  `Features/_Pending.swift`: delete ONLY your own stub line(s) from that file, keep the exact entry signature
  (`struct XxxView: View { let model: AppModel … }`).

## Build and check

`Scripts/build.sh Debug <your-suffix>` (own DerivedData; prints errors only; exit code 0 = success). Other agents work in parallel in
other feature folders: an error in a folder that is not yours is not yours to fix — re-run a little later. Zero warnings in your files.
A local throwaway backend runs at http://localhost:8760 (random test keys, Base = local anvil fork with 1 fake ETH, every live
trading lock OFF, real public market data). The owner session is created by the dev app. To see real response shapes, read the
Core's models/fixtures (`../SPWalletCore/Tests/SPWalletCoreTests/Fixtures/`) and the backend source rather than guessing.
Do NOT start/stop the stack, do NOT launch the app (one shared instance), do NOT contact production (wallet.spboucher.ai), do NOT
run git commit/push, do NOT run `pkill`.

## Report (what I need back)

- files written; the feature's capabilities and, for EACH, its real status in the backend as you verified it by reading the code:
  operational in production / behind a server lock (which) / paper or testnet only / read-only / not available — with the file:line
  that proves it;
- every place where the Core lacks something or seems wrong (exact symbol and what you expected);
- what you verified by compiling vs. what remains unverified (nothing was run against a backend unless you say how).
