// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/AgentDetailStore.swift
// Description      : Everything one agent's detail screen reads and does. Reads
//                    are mode-scoped (one answer never mixes research, paper
//                    and real; the Core refuses an answer of another mode) and
//                    each read fails on its own, so a failed source shows as
//                    unavailable instead of empty. Life-cycle actions (start,
//                    pause, resume, stop, revoke, flatten) never need a passkey
//                    and never add authority; going real is a separate,
//                    passkey-approved flow.
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

@MainActor @Observable final class AgentDetailStore {
    let model: AppModel
    let api: AgentsAPI
    let id: String

    private(set) var detail: AgentDetail?
    private(set) var overview: AgentOverview?
    private(set) var loadedAt: Date?
    /// Which mode the mode-scoped lists and figures are shown for.
    var viewMode: AgentMode = .paper { didSet { if oldValue != viewMode { Task { await loadScoped() } } } }
    private(set) var signals: [AgentMode: [AgentSignal]] = [:]
    private(set) var journal: [AgentMode: [AgentJournalEntry]] = [:]
    private(set) var orders: [AgentMode: [AgentOrder]] = [:]
    private(set) var timeline: [AgentMode: [AgentTimelineItem]] = [:]
    private(set) var performance: [AgentMode: AgentPerformance] = [:]
    private(set) var configVersions: [AgentConfigVersion]?
    private(set) var elsewhere: FundsElsewhere?
    private(set) var returns: VaultReturns?
    private(set) var mandateDraft: MandateDraft?
    private(set) var library: [LibraryStrategy]?
    private(set) var job: AgentJob?
    /// Read failures by source ("detail", "orders.paper", "performance.live"…): shown where the data would have been.
    private(set) var errors: [String: String] = [:]

    private(set) var busy: String?
    var actionError: String?
    var notice: String?
    private var modeChosen = false
    private var returnKeys: [String: String] = [:]

    init(model: AppModel, id: String) { self.model = model; self.id = id; api = AgentsAPI(model.client) }

    var agent: Agent? { detail?.agent }
    var summary: AgentSummary? { overview?.summary }
    var isMarketMaking: Bool { (summary?.family ?? agent?.family) == "market_making" }
    var kind: ModeKind { agent.map { ModeKind(agent: $0) } ?? ModeKind(summary?.mode ?? .unknown) }
    /// The modes the server allows for this agent's family; nil = unknown.
    var allowedModes: [AgentMode]? { overview?.familyModes?.modes }
    var hasOpenWork: Bool { (returns?.withdrawals.contains { $0.state.isOpen } ?? false) || (job.map { !$0.status.isFinished } ?? false) || summary?.isWindingDown == true }

    func error(_ key: String) -> String? { errors[key] }
    private func note<T: Sendable>(_ key: String, _ r: Result<T, Error>) -> T? {
        switch r { case .success(let v): errors[key] = nil; return v; case .failure(let e): errors[key] = model.describe(e); return nil }
    }

    // MARK: reads

    func refresh() async {
        guard model.phase == .signedIn else { return }
        let api = api, id = id
        async let d = Result.catching { try await api.detail(id) }
        async let o = Result.catching { try await api.overview(id) }
        if let v = note("detail", await d) { detail = v; loadedAt = Date() }
        if let v = note("overview", await o) { overview = v }
        if !modeChosen, let m = agent?.mode ?? summary?.mode { modeChosen = true; viewMode = m == .unknown ? .paper : m }
        await loadScoped()
        if agent?.hasVault == true { await loadVault() }
        if let j = job, !j.status.isFinished, let v = try? await api.job(j.id) { job = v; if v.status.isFinished { notice = v.status == .done ? "Backtest terminé (simulation sur données historiques). Le rapport est dans l’onglet Stratégie." : "Backtest \(v.status.rawValue)\(v.error.map { " : \($0)" } ?? "")." } }
    }

    func loadScoped() async {
        let api = api, id = id, m = viewMode
        guard m != .unknown else { return }
        async let s = Result.catching { try await api.signals(id, mode: m, limit: 200).value }
        async let j = Result.catching { try await api.journal(id, mode: m, limit: 300).value }
        async let o = Result.catching { try await api.orders(id, mode: m, limit: 300).value }
        async let t = Result.catching { try await api.timeline(id, mode: m, limit: 200).value }
        if let v = note("signals.\(m.rawValue)", await s) { signals[m] = v }
        if let v = note("journal.\(m.rawValue)", await j) { journal[m] = v }
        if let v = note("orders.\(m.rawValue)", await o) { orders[m] = v }
        if let v = note("timeline.\(m.rawValue)", await t) { timeline[m] = v }
    }

    /// Performance of paper and of real, each read alone. Research has no performance: its figures are backtest reports.
    func loadPerformance() async {
        let api = api, id = id
        for m in [AgentMode.paper, .live] {
            if let v = note("performance.\(m.rawValue)", await Result.catching { try await api.performance(id, mode: m) }) { performance[m] = v }
        }
    }

    func loadVault() async {
        let api = api, id = id
        async let e = Result.catching { try await api.fundsElsewhere(id) }
        async let r = Result.catching { try await api.vaultReturns(id) }
        if let v = note("elsewhere", await e) { elsewhere = v }
        if let v = note("returns", await r) { returns = v }
    }

    func loadConfig() async {
        let api = api, id = id
        if let v = note("configVersions", await Result.catching { try await api.configVersions(id) }) { configVersions = v }
        if let v = note("mandateDraft", await Result.catching { try await api.mandateDraft(id, locale: "fr") }) { mandateDraft = v }
    }

    func loadLibrary() async {
        let api = api, perp = agent?.resolvedKind == .perp
        if let v = note("library", await Result.catching { perp ? try await api.perpStrategyLibrary() : try await api.strategyLibrary() }) { library = v }
    }

    /// Polls while the screen is visible: faster while something is in flight (a vault return, a backtest, a wind-down).
    func poll() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(hasOpenWork ? 4 : 20))
            guard !Task.isCancelled else { return }
            if AppActivity.isActive, !model.isOffline, busy == nil { await refresh() }
        }
    }

    // MARK: operations (none needs a passkey; none adds authority)

    private func run(_ name: String, _ body: () async throws -> String?) async {
        guard busy == nil, model.canOperate else { return }
        busy = name; actionError = nil; notice = nil
        do { notice = try await body() } catch { actionError = model.describe(error) }
        busy = nil
        await refresh()
    }

    /// Research and paper only. Real is reached by approving a mandate, or by starting under a mandate already in force (see `startLive`).
    func start(_ mode: AgentMode) async {
        guard mode == .research || mode == .paper else { return }
        let api = api, id = id
        await run("start") { let s = try await api.start(id, mode: mode); return "Agent démarré — état du serveur : \(AgentText.phase(s.phase)), mode \(ModeKind(s.mode).short)." }
    }

    /// Starts in real under a mandate ALREADY approved by the owner and in force. It can never create or approve one: without it the server answers `mandate_required`.
    func startLive() async {
        let api = api, id = id
        await run("startLive") { let s = try await api.start(id, mode: .live); return "État du serveur : \(AgentText.phase(s.phase)), mode \(ModeKind(s.mode).short)." }
    }

    func pause() async {
        let api = api, id = id
        await run("pause") { let s = try await api.pause(id); return "Agent en pause — état du serveur : \(AgentText.phase(s.phase))." }
    }

    func resume() async {
        let api = api, id = id
        await run("resume") { let s = try await api.resume(id); return "Agent relancé — état du serveur : \(AgentText.phase(s.phase)), mode \(ModeKind(s.mode).short)." }
    }

    func stop() async {
        let api = api, id = id
        await run("stop") {
            let s = try await api.stop(id)
            return s.isWindingDown ? "Arrêt demandé : le mandat est révoqué et les positions sont en cours de fermeture (ordres réducteurs seulement). L’agent reste « arrêt en cours » jusqu’à la fin." : "Agent arrêté — état du serveur : \(AgentText.phase(s.phase))."
        }
    }

    /// Spot: revokes the mandate at the signer and stops the agent. Final; a new mandate needs the passkey again.
    func revokeSpotMandate() async {
        let api = api, id = id
        await run("revoke") { let a = try await api.revokeMandate(id); return "Mandat révoqué au signataire — état du serveur : \(AgentText.phase(a.state))." }
    }

    func flattenPaper() async {
        let api = api, id = id
        await run("flatten") { let r = try await api.flattenPerpPaper(id); return "Compte PAPIER : \(r.orders.count) ordre(s) réducteur(s) simulé(s), \(r.positionsLeft) position(s) restante(s)." }
    }

    func register(_ s: LibraryStrategy) async {
        let api = api, id = id
        await run("register") { let r = try await api.registerStrategy(id, s); return "Version \(s.meta.name) \(s.meta.version) rattachée (état : \(r.status)). Son backtest démarre ; rien n’est approuvé." }
    }

    func approveVersion(_ v: StrategyVersion) async {
        let api = api, id = id
        await run("approveVersion") { _ = try await api.approveStrategyVersion(agentId: id, versionId: v.id); return "Version \(v.name) \(v.version) approuvée pour le papier. Cela ne donne aucune autorité sur des fonds." }
    }

    func backtest(versionId: String?) async {
        let api = api, id = id
        guard busy == nil, model.canOperate else { return }
        busy = "backtest"; actionError = nil; notice = nil
        do { let r = try await api.requestBacktest(id, versionId: versionId); job = r.job; notice = "Backtest en file (\(r.label)) : simulation sur données historiques." } catch { actionError = model.describe(error) }
        busy = nil
    }

    /// The WHOLE balance of one asset of the vault, to the owner's own address — the only destination the signer signs for a vault.
    func returnToOwner(asset: String, network: String?) async {
        let api = api, id = id, k = "\(network ?? "")|\(asset)"
        let key = returnKeys[k] ?? UUID().uuidString.lowercased(); returnKeys[k] = key
        await run("return") {
            let r = try await api.returnToOwner(id, asset: asset, network: network, idempotencyKey: key)
            return (r.duplicate == true ? "Ce retour existait déjà (rien de nouveau n’a été signé). " : "") + "Retour de \(Fmt.amount(r.amount)) \(r.symbol) : \(AgentText.returnState(r.state)). Suivez-le ci-dessous jusqu’à la confirmation de la chaîne."
        }
        if actionError == nil { returnKeys[k] = nil }
    }

    func updateConfig(config: [String: JSONValue]?, risk: [String: JSONValue]?) async -> Bool {
        let api = api, id = id
        await run("config") { let r = try await api.updateConfig(id, config: config, risk: risk); return "Configuration enregistrée : version \(r.configVersion)." }
        if actionError == nil { await loadConfig() }
        return actionError == nil
    }

    func setPerpRisk(_ risk: PerpAgentRisk, liftHalt: Bool) async -> Bool {
        let api = api, id = id
        await run("perpRisk") { _ = try await api.setPerpRisk(id, risk: risk, liftHalt: liftHalt); return "Limites de la simulation enregistrées." }
        return actionError == nil
    }
}
