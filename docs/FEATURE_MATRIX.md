# SP Wallet macOS 1.0.0 — parity matrix (web / backend → native)

Audit of `sp-wallet` at `8dc85bd` (production, 2026-11-18). "Backend" = what the server code really does, read in
`services/api/src` and `services/isolated-signer`; production locks read on the API node the same day:
`SPW_DERIV_LIVE_MAINNET=on`, `SPW_DERIV_MANDATE_MAINNET=on`, `SPW_TRADING_API_EXECUTION=on`, `SPW_DERIV_GMX_LIVE=off`,
market-making locks absent (off), `SPW_BROADCAST=on`.

Native verification levels: **E2E** = exercised by the signed development variant against a throwaway stack (real API + real signer
process, test keys, Base on a local fork); **Seen** = screen observed loading live data from that stack; **Built** = compiled
(Swift 6 strict concurrency), flow not executed; **Prod** = observed against production.
Nothing in this table was executed with real funds. No real transaction was sent.

| # | Feature | Backend status | In production | Native app | Native verification |
|---|---|---|---|---|---|
| 1 | Networks (23: 8 EVM, BTC/LTC/DOGE/BCH, Solana, TRON, XRPL, Stellar, Cosmos, Sui, Aptos, NEAR, TON, Cardano, Polkadot Asset Hub) | implemented, tested | yes | Portfolio: id, native coin, address, balances, RPC state, capabilities; registry-driven | E2E (23 networks, 23 addresses) |
| 2 | Tokens (84 symbols, verified registry) | implemented; registry is server-side, **no custom token** | yes | Assets list/detail, contract, decimals, price chart; states that custom tokens are not supported | E2E / Seen |
| 3 | Balances, prices (CoinGecko + API Bricks cross-check) | implemented | yes | exact on-chain amounts; fiat always "≈ estimation"; stale / divergent / unavailable flags | E2E |
| 4 | Send (all networks) | implemented, tested; broadcast paths used for real by the owner on Ethereum | yes | form → draft → verified intent → review → passkey → tracking to finality | **E2E** incl. finalization, tampered intent, cancelled passkey, replay |
| 5 | Receive | implemented | yes | addresses, local QR, payment URI | Seen |
| 6 | Isolated signer, limits, anti-replay, expiry | implemented, tested | yes (m6ma) | never bypassed; limits and key id displayed read-only | E2E |
| 7 | Passkey authentication (WebAuthn) | implemented | yes | system passkey sheet (AuthenticationServices); association file deployed | **Prod: sign-in screen reached; Touch ID sign-in to be confirmed by the owner** |
| 8 | App lock (Touch ID) | n/a (local) | n/a | optional, authorizes nothing | Built |
| 9 | Swaps — KyberSwap (8 EVM), Jupiter (Solana) | implemented, tested on forks; one real swap by the owner (Ethereum) | yes | quotes stream, executable vs comparison-only routes, verified intent review, tracking | Seen (quotes UI); execution **Built** |
| 10 | Native cross-chain swaps (THORChain) | implemented; fails closed below 3 unanimous operators; never broadcast for real | yes | integrated in Swap; failure-closed explained | Built |
| 11 | Bridge — Circle CCTP V2 (7 EVM + Solana) | implemented, fork-tested; never broadcast for real | yes | both speeds, two legs, recovery (finish / retry-mint / reclaim / token account) with verified objects | Built |
| 12 | Any-to-any plans (≤ 3 legs) | implemented | yes | DeFi → plan flow, one passkey per leg | Built |
| 13 | DeFi lending / staking / LP / dApp connection | **not available** | no | stated as not available; no placeholder | — |
| 14 | NFT inventory, item pages, media proxy | implemented (delivery 1) | yes (OpenSea / Alchemy / Solana DAS) | gallery, collections, item page, ImageIO decoding, proxy-only media | Seen (empty inventory on the test wallet) |
| 15 | NFT transfers (ERC-721/1155, 4 Solana standards) | implemented (delivery 2); never executed on a real network | yes | verdict → verified NFT intent → passkey → tracking; allow-list and UTXO locks | Built |
| 16 | NFT market read | implemented (delivery 3) | yes | started by a button, labelled observed data | Built |
| 17 | NFT market write, item valuation, Ordinals transfer | **not available** | no | stated | — |
| 18 | Derivatives market data (Hyperliquid, GMX, dYdX, edgeX) | implemented, read-only | yes | markets table, instrument page, book, funding, live quote stream | **Seen (235 instruments, live stream)** |
| 19 | Paper accounts | implemented (simulation) | yes | separate SIMULATION mode | Built |
| 20 | Hyperliquid live (manual, passkey per order) | implemented; lock on in production; **no order ever accepted by the venue on a funded account from this code** | lock on | account, authorization, pre-trade risk panel, verified order object, collateral | Built — not validated end to end |
| 21 | GMX v2 | implemented; lock **off** in production | no (lock off) | read + reduce / halt / revoke only; opening absent | Built |
| 22 | dYdX, edgeX trading | **not available** (terms exclude Canada) | no | market data only, reason shown | — |
| 23 | Risk engine, limits, kill switch | implemented | yes | view, engage (no passkey), release / loosen by passkey over verified objects | Built; kill-switch bar Seen |
| 24 | Spot trading agents (research / paper / real by mandate) | implemented | yes (owner has paper agents) | list, detail, create, lifecycle, mandate approval with risk acknowledgements, revoke, vault | Seen (list, engine status); flows Built |
| 25 | Perp agents | paper implemented; live behind locks (on in production) | lock on | paper + live by mandate | Built |
| 26 | Market making | paper implemented; live locks **off** | no (locks off) | paper, evidence, pull / flatten; **live approval not offered** (the shared core cannot verify a quoting mandate) | Built |
| 27 | Trading API (keys, webhooks, usage) | implemented; execution lock on | yes | keys with passkey approvals, one-time secret sheet, webhooks, usage | Built |
| 28 | Alerts (66 kinds), settings, webhook | implemented | yes | list, live stream, macOS notifications, settings | **Seen (live stream, 4 alerts)** |
| 29 | Web Push | browser feature | yes | listed / removable; cannot be created from a native app (stated) | Built |
| 30 | Monitoring (capital, PnL, exposure, health, capabilities) | implemented | yes | per-section failure states, three books apart | Built |
| 31 | Research: markets explorer, candles, data quality | implemented | yes | explorer, local indicators labelled derived | **Seen (911 markets)** |
| 32 | Automated research jobs (Claude Code runner) | implemented; runner on M5M36 | yes | create with budgets, live log, results labelled AI analysis | Built |
| 33 | Activity history, CSV | implemented | yes | table, search, filters, CSV + **PDF** export, explorer links | E2E (history) / Built (exports) |
| 34 | Audit journal (hash chain) | implemented | yes | displayed with the server's integrity verdict | Seen |
| 35 | Emergency halt | implemented (one-way from clients) | yes | confirmation dialog, one-way explained | Built; scripted check available (`--selftest --halt`), not run on the shared stack |
| 36 | Offline mode | not in the web app | n/a | read-only consultation of the last snapshots, dated, behind the Mac owner's authentication; no operation | E2E (snapshot kept / session closed) |
| 37 | Portfolio value history | **not served by the backend** | no | local series of this Mac's own observations, labelled | Seen |
| 38 | Owner setup, recovery phrase | signer CLI only | — | not in the app, by design | — |

## Not built in 1.0.0 (documented, no placeholder in the app)

Market-making live approval · mandate creation for an API key · API-key expiry editing · editing spot agent limits after creation ·
GMX opening orders and GMX authorization · editing keyed risk limits · NFT floor-estimate opt-in · offline cache of derivatives /
monitoring / research data · automatic update of the app.
