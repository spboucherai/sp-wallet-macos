// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/DeFi/PlanFlow.swift
// Description      : State machine of an any-to-any plan: quote candidate
//                    multi-leg routes (a read) → start one (stored by the
//                    server; nothing prepared or signed) → for each leg, when
//                    its turn comes: prepare it, verify it with the Core
//                    against the plan displayed, approve it with its own
//                    passkey prompt, wait until the chain settles it → next
//                    leg. After a pause the owner decides: retry, re-plan from
//                    the asset held, or stop. Nothing advances by itself and no
//                    leg is ever reported settled before the server read its
//                    output from the chain.
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

@MainActor @Observable final class PlanFlow {
    enum Busy: Equatable { case quoting, starting(String), refreshing, preparing, approving, retrying, replanning, stopping }

    /// The server's schema default and bounds for plans (services/api/src/plan-exec.ts `Pair`): 50 bps, 1…300.
    static let slippageRange = 1...300

    let model: AppModel
    var fromKey = ""
    var toKey = ""
    var amount = ""
    var slippageText = "0,5"
    /// Optional overall floor, in whole units of the destination asset: the plan pauses before a leg when the estimate is below it.
    var floorText = ""
    var newFloorText = ""

    private(set) var assets: [SwapAsset] = []
    private(set) var loaded = false
    private(set) var loadError: String?
    private(set) var quote: PlanQuote?
    private(set) var quotedAt: Date?
    private(set) var plan: PlanView?
    private(set) var recent: [PlanView] = []
    private(set) var busy: Busy?
    private(set) var operation: ApprovableOperation?
    private(set) var readError: String?
    var error: String?
    var reviewError: String?
    private var announced: Set<String> = []

    init(model: AppModel) { self.model = model }

    private var api: PlanAPI { PlanAPI(model.client) }
    var from: SwapAsset? { assets.first { $0.key == fromKey } }
    var to: SwapAsset? { assets.first { $0.key == toKey } }
    var normalizedAmount: String { SwapText.normalize(amount) }
    var parsedAmount: BaseUnits? { guard let d = from?.decimals else { return nil }; return try? BaseUnits.parse(normalizedAmount, decimals: d) }
    var slippageBps: Int? {
        guard let v = Double(SwapText.normalize(slippageText)), v.isFinite else { return nil }
        let b = Int((v * 100).rounded())
        return Self.slippageRange.contains(b) && abs(v * 100 - Double(b)) < 1e-6 ? b : nil
    }
    private func floorValue(_ text: String) -> String?? {
        let t = SwapText.normalize(text)
        if t.isEmpty { return .some(nil) }
        guard let d = (plan?.to ?? to)?.decimals, let u = try? BaseUnits.parse(t, decimals: d), !u.isZero else { return nil }
        return .some(t)
    }

    var formProblem: String? {
        guard let f = from, to != nil else { return "Choisissez l’actif de départ et l’actif d’arrivée." }
        if fromKey == toKey { return "Choisissez deux actifs différents." }
        if amount.trimmingCharacters(in: .whitespaces).isEmpty { return "Entrez un montant." }
        guard let a = parsedAmount, !a.isZero else { return "Montant invalide (au plus \(f.decimals) décimales)." }
        if let b = SwapText.balance(model, of: f), b.isAvailable, let u = b.units, a > u { return "Montant supérieur au solde lu sur la chaîne." }
        if slippageBps == nil { return "Tolérance invalide : entre 0,01 % et 3 %." }
        if floorValue(floorText) == nil { return "Plancher invalide." }
        return nil
    }
    private var request: PlanRequest? {
        guard formProblem == nil, let bps = slippageBps else { return nil }
        return PlanRequest(from: fromKey, to: toKey, amount: normalizedAmount, slippageBps: bps)
    }
    /// The quote on screen is for the form as it is now.
    var quoteIsCurrent: Bool {
        guard let q = quote, let a = parsedAmount else { return false }
        return q.from.key == fromKey && q.to.key == toKey && q.amountIn == a.description && q.slippageBps == slippageBps
    }

    // MARK: loading

    func load() async {
        guard model.phase == .signedIn else { return }
        do {
            async let a = SwapAPI(model.client).assets()
            async let open = api.list(openOnly: true, limit: 1)
            async let last = api.list(limit: 6)
            let (assets, o, l) = try await (a, open, last)
            self.assets = assets; loaded = true; loadError = nil
            recent = l.filter { !$0.isOpen }
            if plan == nil { plan = o.first }
            if let p = plan, p.isOpen { await refresh() }
        } catch { loadError = model.describe(error) }
    }

    private func adopt(_ p: PlanView) {
        plan = p; readError = nil
        guard !p.isOpen, !announced.contains(p.id) else { return }
        announced.insert(p.id)
        if p.isComplete { Notifier.post(title: "Parcours terminé", body: "Reçu : \(p.receivedDisplay.map { Fmt.amount($0, maxFraction: 8) } ?? "—") \(p.to.symbol) sur \(p.to.networkName ?? p.to.network).", id: "plan-\(p.id)") }
        else if p.state == .stopped { Notifier.post(title: "Parcours arrêté", body: "Les fonds restent où ils sont : \(Fmt.amount(p.holding.amountDisplay, maxFraction: 8)) \(p.holding.symbol) sur \(p.holding.networkName ?? p.holding.network).", id: "plan-\(p.id)") }
        Task { await model.refreshAll() }
    }

    /// Reading a plan makes the server look at the current leg's proposal; it creates and signs nothing.
    func refresh() async {
        guard let id = plan?.id, model.phase == .signedIn else { return }
        do { adopt(try await api.plan(id)) } catch { readError = model.describe(error) }
    }

    /// While a leg is in flight (or an unused challenge is ageing): read the plan until the next decision is the owner's.
    func follow() async {
        while !Task.isCancelled {
            guard let p = plan, p.isOpen, p.next == .wait || (p.next == .approve && operation == nil) else { return }
            try? await Task.sleep(for: .seconds(p.next == .wait ? 5 : 20))
            guard !Task.isCancelled else { return }
            guard AppActivity.isActive, model.phase == .signedIn, busy == nil else { continue }
            await refresh()
        }
    }

    // MARK: quote and start

    func quotePlans() async {
        guard busy == nil, model.canOperate, let r = request else { return }
        busy = .quoting; defer { busy = nil }
        error = nil
        do { quote = try await api.quote(r); quotedAt = Date() }
        catch { quote = nil; self.error = SwapText.describe(error, model: model) }
    }

    /// Stores the chosen shape. Nothing is prepared or signed: the first leg becomes "ready".
    func start(_ candidate: PlanCandidate) async {
        guard busy == nil, model.canOperate, quoteIsCurrent, candidate.executable, let r = request, let floor = floorValue(floorText) else { return }
        busy = .starting(candidate.id); defer { busy = nil }
        error = nil
        do { adopt(try await api.start(r, plan: candidate.id, floor: floor)); quote = nil; amount = ""; floorText = "" }
        catch {
            self.error = SwapText.describe(error, model: model)
            // a lost answer, or a plan opened elsewhere: show the plan that is really open rather than starting a second one
            if let open = try? await api.list(openOnly: true, limit: 1).first { adopt(open) }
        }
    }

    // MARK: one leg = one verified passkey approval

    func prepareLeg() async {
        guard busy == nil, model.canOperate, let displayed = plan, displayed.isOpen else { return }
        guard let accounts = model.accounts?.value else { error = "Les adresses du portefeuille ne sont pas synchronisées ; l’étape ne peut pas être vérifiée."; return }
        busy = .preparing; defer { busy = nil }
        error = nil; reviewError = nil
        do {
            // verified against the plan AS DISPLAYED: same plan, same position, same leg, an amount within what the plan holds
            let prep = try await api.prepareLeg(of: displayed, accounts: accounts, minimumOutput: .asPrepared)
            adopt(prep.plan)
            if let op = prep.operation?.approvable { operation = op }
            else if prep.operation != nil { await refresh() }
        } catch {
            self.error = SwapText.describe(error, model: model)
            await refresh()
        }
    }

    func approveLeg() async {
        guard let op = operation, busy == nil else { return }
        busy = .approving; defer { busy = nil }
        reviewError = nil
        do {
            _ = try await api.approve(op, with: model.authenticator)
            operation = nil
            await refresh()
        } catch PasskeyError.cancelled {
        } catch {
            reviewError = (error as? APIError)?.isOffline == true ? "Réponse perdue pendant l’approbation. Lecture de l’état réel de l’étape…" : SwapText.describe(error, model: model)
            // never sign twice: if the proposal left "pending approval", follow the plan instead
            if let p = try? await api.proposal(op.proposal.id), p.state != .pendingApproval { operation = nil; self.error = reviewError; await refresh() }
        }
    }

    /// Withdraws the unused challenge of this leg. The plan then records the refusal and waits for a decision.
    func rejectLeg() async {
        guard let op = operation, busy == nil else { return }
        _ = try? await api.reject(op.proposal.id)
        operation = nil; reviewError = nil
        await refresh()
    }

    // MARK: decisions after a pause (none of them signs anything)

    enum FloorChoice { case unchanged, remove, set }

    func retry(_ choice: FloorChoice) async {
        guard busy == nil, model.canOperate, let id = plan?.id else { return }
        var change = PlanFloorChange.unchanged
        switch choice {
        case .unchanged: break
        case .remove: change = .remove
        case .set:
            guard let inner = floorValue(newFloorText), let v = inner else { error = "Nouveau plancher invalide."; return }
            change = .set(v)
        }
        busy = .retrying; defer { busy = nil }
        error = nil
        do { adopt(try await api.retry(id, floor: change)); newFloorText = "" } catch { self.error = SwapText.describe(error, model: model) }
    }

    func replan() async {
        guard busy == nil, model.canOperate, let id = plan?.id else { return }
        busy = .replanning; defer { busy = nil }
        error = nil
        do { adopt(try await api.replan(id)) } catch { self.error = SwapText.describe(error, model: model) }
    }

    func stop() async {
        guard busy == nil, model.canOperate, let id = plan?.id else { return }
        busy = .stopping; defer { busy = nil }
        error = nil
        do { adopt(try await api.stop(id)); operation = nil } catch { self.error = SwapText.describe(error, model: model) }
    }

    /// Leave a finished plan's summary and go back to the form.
    func dismissFinished() {
        guard let p = plan, !p.isOpen else { return }
        plan = nil; error = nil; operation = nil
        Task { await load() }
    }
}
