// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Swap/SwapFlow.swift
// Description      : State machine of a swap: pair and amount → live quotes
//                    from every provider (price discovery only: nothing is
//                    prepared or signed) → the ONE route this wallet can
//                    execute, as the server states it → firm preparation
//                    verified by the Core against the challenge → passkey →
//                    tracking until the chain says what was received.
//                    Same-network swaps (KyberSwap, Jupiter) and native
//                    cross-chain swaps (THORChain) share the flow; the executor
//                    is always the server's statement, never a guess.
// Module           : Features
// Repository       : https://git.spboucher.ai/sp-wallet-macos
// Created          : 2026-11-18
// Last Modified    : 2026-11-18
//
// =============================================================================
// AUTHOR & PROFESSIONAL AFFILIATION
// =============================================================================
//
// Author           : Simon-Pierre Boucher
// Position         : Professor of Finance
// Institution      : Université du Québec en Outaouais (UQO)
// Department       : Département des sciences administratives
// Organization     : SP Boucher
//
// Website          : https://spboucher.ai
// Git              : https://git.spboucher.ai
//
// =============================================================================
// OFFICIAL CONTACT DIRECTORY
// =============================================================================
//
// General          : info@spboucher.ai
// Professional     : contact@spboucher.ai
// Direct           : simon@spboucher.ai
// Research         : research@spboucher.ai
// Development      : dev@spboucher.ai
// Support          : support@spboucher.ai
// Security/Admin   : admin@spboucher.ai
// Notifications    : notifications@spboucher.ai
//
// Preferred Contact: support@spboucher.ai
//
// =============================================================================
// COPYRIGHT & INTELLECTUAL PROPERTY
// =============================================================================
//
// Copyright (c) 2026
// Simon-Pierre Boucher
//
// All rights reserved where applicable.
//
// This file is governed by the applicable project license,
// copyright notices, institutional agreements and relevant law.
//
// Unless expressly authorized by the applicable license or
// rights holder, copying, redistribution, sublicensing,
// publication and commercial exploitation are not permitted.
//
// Existing third-party rights and notices remain unaffected.
//
// =============================================================================
// CONFIDENTIALITY & SECURITY
// =============================================================================
//
// Classification   : Public
// Distribution     : Public repository; use is governed by the project license
// Security Contact : admin@spboucher.ai
//
// Access to this source does not independently grant permission
// to redistribute or disclose confidential materials.
//
// Do not embed credentials, private keys, access tokens,
// certificates or confidential personal information.
//
// =============================================================================
// LICENSE & MAINTENANCE
// =============================================================================
//
// License          : None specified (no license file in this repository)
// Maintainer       : Simon-Pierre Boucher
// Technical Contact: dev@spboucher.ai
//
// =============================================================================
// END OF SP BOUCHER SOURCE HEADER
// =============================================================================

import Foundation
import SPWalletCore

@MainActor @Observable final class SwapFlow {
    enum Step: Equatable { case form, preparing, review, approving, tracking }
    enum QuotePhase: Equatable { case idle, loading, done, failed(String) }

    /// The server's own schema defaults and bounds (services/api/src/swap-exec.ts and xswap.ts `Create`): 50 bps for a
    /// same-network swap, 100 bps for a THORChain swap, 1…300 bps accepted at preparation. No endpoint serves them.
    static let defaultSlippageBps = 50
    static let defaultNativeSlippageBps = 100
    static let slippageRange = 1...300
    static let slippagePresets = [10, 30, 50, 100, 200, 300]

    let model: AppModel
    var fromKey = "" { didSet { if fromKey != oldValue { pairChanged() } } }
    var toKey = "" { didSet { if toKey != oldValue { pairChanged() } } }
    var amount = ""
    /// Tolerance as typed, in percent ("0,5").
    var slippageText = "0,5" { didSet { if slippageText != oldValue { slippageTouched = true } } }
    private var slippageTouched = false

    private(set) var assets: [SwapAsset] = []
    private(set) var providers: SwapProviders?
    private(set) var execution: SwapExecutionInfo?
    private(set) var xswapInfo: XSwapExecutionInfo?
    private(set) var bridgeInfo: BridgeExecutionInfo?
    private(set) var loadError: String?
    private(set) var loaded = false

    private(set) var quotePhase: QuotePhase = .idle
    private(set) var routes: [SwapRoute] = []
    private(set) var best: [String: String] = [:]
    private(set) var answers: [SwapProviderAnswer] = []
    /// The executors the SERVER states for this pair (pinned tables); nil until a search started.
    private(set) var pairExecutors: [String]?
    private(set) var reachable: Bool?
    private(set) var quotedAt: Date?
    private(set) var requote = 0

    private(set) var step: Step = .form
    private(set) var operation: ApprovableOperation?
    private(set) var tracker: OperationTracker?
    private(set) var refreshing = false
    var error: String?
    private var idempotency: (key: String, fingerprint: String)?

    init(model: AppModel) { self.model = model }

    // MARK: derived

    var from: SwapAsset? { assets.first { $0.key == fromKey } }
    var to: SwapAsset? { assets.first { $0.key == toKey } }
    var normalizedAmount: String { SwapText.normalize(amount) }
    var parsedAmount: BaseUnits? { guard let d = from?.decimals else { return nil }; return try? BaseUnits.parse(normalizedAmount, decimals: d) }
    var balance: Balance? { from.flatMap { SwapText.balance(model, of: $0) } }
    var slippageBps: Int? {
        guard let v = Double(SwapText.normalize(slippageText)), v.isFinite else { return nil }
        let b = Int((v * 100).rounded())
        return Self.slippageRange.contains(b) && abs(v * 100 - Double(b)) < 1e-6 ? b : nil
    }
    var crossNetwork: Bool { guard let f = from, let t = to else { return false }; return f.network != t.network }

    /// What the server's capability lists say about the pair before any quote is asked.
    var capabilityHint: [String] {
        guard let f = from, let t = to, f.key != t.key else { return [] }
        if let e = pairExecutors { return e }
        var out: [String] = []
        if f.network == t.network { if let p = execution?.executor(on: f.network) { out.append(p) } }
        else {
            if f.symbol == "USDC", t.symbol == "USDC", bridgeInfo?.canBridge(from: f.network, to: t.network) == true { out.append("cctp") }
            if xswapInfo?.canSwap(from: f.ref, to: t.ref) == true { out.append("thorchain") }
        }
        return out
    }
    var isNativeCrossChain: Bool { capabilityHint.contains("thorchain") }
    /// USDC ↔ USDC between two CCTP networks is a bridge: prepared on its own screen, with its own speeds and fees.
    var isBridgePair: Bool { capabilityHint.contains("cctp") && !capabilityHint.contains("thorchain") }

    var sortedRoutes: [SwapRoute] {
        let top = best["best_price"]
        func min(_ r: SwapRoute) -> BaseUnits { (try? BaseUnits(r.minAmountOut)) ?? .zero }
        return routes.sorted { a, b in
            if (a.id == top) != (b.id == top) { return a.id == top }
            return min(a) > min(b)
        }
    }
    /// The route the action executes: the first one the server marks executable by this wallet (CCTP routes belong to the bridge screen).
    var executableRoute: SwapRoute? { sortedRoutes.first { r in r.statedExecutor != nil && r.statedExecutor != "cctp" } }

    func isExpired(_ r: SwapRoute, now: Date = Date()) -> Bool {
        guard let ms = r.expiresAt ?? r.card?.expiresAt else { return false }
        return now.timeIntervalSince1970 * 1000 >= Double(ms)
    }

    var formProblem: String? {
        guard let f = from, let t = to else { return "Choisissez l’actif vendu et l’actif acheté." }
        if f.key == t.key { return "Choisissez deux actifs différents." }
        if amount.trimmingCharacters(in: .whitespaces).isEmpty { return "Entrez un montant." }
        guard let a = parsedAmount, !a.isZero else { return "Montant invalide (au plus \(f.decimals) décimales)." }
        if let b = balance, b.isAvailable, let u = b.units, a > u { return "Montant supérieur au solde lu sur la chaîne." }
        if slippageBps == nil { return "Tolérance de glissement invalide : entre 0,01 % et 3 %." }
        return nil
    }

    /// Identity of the quote search: the view restarts the stream when it changes and closes it when it disappears.
    var quoteKey: String { "\(fromKey)|\(toKey)|\(normalizedAmount)|\(slippageBps ?? -1)|\(requote)|\(model.canOperate)" }

    // MARK: loading

    func load() async {
        guard model.phase == .signedIn else { return }
        let swap = SwapAPI(model.client)
        do {
            async let a = swap.assets()
            async let p = swap.providers()
            async let e = swap.execution()
            (assets, providers, execution) = try await (a, p, e)
            loadError = nil; loaded = true
        } catch { loadError = model.describe(error) }
        // the two cross-chain capability lists only refine hints: their absence disables nothing by itself
        xswapInfo = try? await XSwapAPI(model.client).execution()
        bridgeInfo = try? await BridgeAPI(model.client).execution()
    }

    private func pairChanged() {
        guard !slippageTouched || slippageBps == nil else { return }
        // the server's default tolerance for the kind of swap this pair is
        slippageText = isNativeCrossChain ? "1" : "0,5"
        slippageTouched = false
    }

    func setSlippage(bps: Int) { slippageText = (Double(bps) / 100).formatted(.number.precision(.fractionLength(0...2))) }
    func setMax() { if let d = balance?.display { amount = d } }
    func flip() { let f = fromKey; fromKey = toKey; toKey = f; amount = "" }
    func refreshQuotes() { requote += 1 }

    // MARK: quotes (read-only)

    private func clearQuotes() { routes = []; best = [:]; answers = []; pairExecutors = nil; reachable = nil; quotedAt = nil }

    /// One server-sent stream per (pair, amount, tolerance). Asking for quotes prepares nothing and signs nothing.
    func runQuotes() async {
        guard step == .form else { return }
        clearQuotes()
        guard model.canOperate, let f = from, let t = to, f.key != t.key, let a = parsedAmount, !a.isZero, let bps = slippageBps else { quotePhase = .idle; return }
        quotePhase = .loading
        try? await Task.sleep(for: .milliseconds(600)) // a pause in typing
        if Task.isCancelled { return }
        let request = SwapQuoteRequest(from: f.key, to: t.key, amount: normalizedAmount, slippageBps: bps)
        do {
            for try await event in SwapAPI(model.client).quoteStream(request) {
                switch event {
                case .start(let s): pairExecutors = s.executors; reachable = s.reachable
                case .route(let r): routes.removeAll { $0.id == r.id }; routes.append(r)
                case .provider(let p): answers.append(p)
                case .done(let s):
                    routes = s.routes; best = s.best; answers = s.providers; pairExecutors = s.executors; reachable = s.reachable
                    quotedAt = Date(); quotePhase = .done
                case .failed(let code, let message): quotePhase = .failed(SwapText.describe(APIError(status: 200, code: code, message: message), model: model))
                case .unknown: break
                }
            }
            if Task.isCancelled { return }
            if quotePhase == .loading { quotePhase = .failed("La recherche de cotations s’est interrompue avant son résultat final.") }
        } catch is CancellationError {
        } catch { if !Task.isCancelled { quotePhase = .failed(SwapText.describe(error, model: model)) } }
    }

    // MARK: preparation and approval

    func prepare() async {
        guard step == .form, model.canOperate, formProblem == nil, let f = from, let t = to, let bps = slippageBps,
              let route = executableRoute, let via = route.statedExecutor, !isExpired(route) else { return }
        guard let accounts = model.accounts?.value else { error = "Les adresses du portefeuille ne sont pas synchronisées ; l’opération ne peut pas être vérifiée."; return }
        error = nil; step = .preparing
        // the reference of the route displayed travels with the request: the server refuses when its firm route is below the minimum shown
        let ref = route.quoteReference
        let rule: MinimumOutputRule = ref == nil ? .asPrepared : .notBelowQuote
        let fp = "\(via)|\(f.key)|\(t.key)|\(normalizedAmount)|\(bps)|\(ref?.fingerprint ?? "-")"
        if idempotency?.fingerprint != fp { idempotency = (APIClient.newIdempotencyKey(), fp) }
        let key = idempotency!.key
        do {
            let prepared: PreparedOperation
            if via == "thorchain" {
                prepared = try await XSwapAPI(model.client).prepare(XSwapRequest(fromNetwork: f.network, fromAsset: f.asset, toNetwork: t.network, toAsset: t.asset, amount: normalizedAmount, slippageBps: bps, quote: ref),
                                                                    accounts: accounts, minimumOutput: rule, idempotencyKey: key)
            } else {
                guard f.network == t.network else { throw ApprovalError.inconsistent("un échange \(via) ne change pas de réseau") }
                prepared = try await SwapAPI(model.client).prepare(SwapRequest(network: f.network, fromAsset: f.asset, toAsset: t.asset, amount: normalizedAmount, slippageBps: bps, quote: ref),
                                                                   accounts: accounts, minimumOutput: rule, idempotencyKey: key)
            }
            if let op = prepared.approvable { operation = op; step = .review }
            else { idempotency = nil; begin(tracking: prepared.proposal) } // replay of a proposal that is no longer waiting for an approval
        } catch {
            self.error = SwapText.describe(error, model: model)
            // answered, even by a refusal: the next attempt is a new request. A lost answer keeps its key, so the retry finds the same proposal.
            if (error as? APIError)?.isOffline != true { idempotency = nil; requote += 1 }
            step = .form
        }
    }

    func approve() async {
        guard let op = operation, step == .review else { return }
        error = nil; step = .approving
        let api = SwapAPI(model.client)
        do {
            let p = try await api.approve(op, with: model.authenticator)
            idempotency = nil; begin(tracking: p)
        } catch PasskeyError.cancelled { step = .review }
        catch {
            // never sign twice: read what the server really did with this proposal
            self.error = (error as? APIError)?.isOffline == true ? "Réponse perdue pendant l’approbation. Lecture de l’état réel de l’opération…" : SwapText.describe(error, model: model)
            if let p = try? await api.proposal(op.proposal.id), p.state != .pendingApproval { idempotency = nil; begin(tracking: p) } else { step = .review }
        }
    }

    func reject() async {
        guard let op = operation else { return }
        _ = try? await SwapAPI(model.client).reject(op.proposal.id)
        idempotency = nil; operation = nil; error = nil; step = .form
        requote += 1
    }

    private func begin(tracking p: Proposal) {
        operation = nil
        tracker = OperationTracker(model: model, proposal: p)
        step = .tracking
        Task { await model.refreshActivity() }
    }

    /// THORChain: look now instead of waiting for the server's worker. Signs nothing.
    func refreshNow() async {
        guard let t = tracker, t.proposal.kind == "xswap", !refreshing, model.canOperate else { return }
        refreshing = true; defer { refreshing = false }
        do { t.update(try await XSwapAPI(model.client).refresh(t.proposal.id)); error = nil }
        catch { self.error = SwapText.describe(error, model: model) }
    }

    func reset() {
        tracker = nil; operation = nil; error = nil; amount = ""; idempotency = nil; step = .form
        clearQuotes(); quotePhase = .idle
    }
}
