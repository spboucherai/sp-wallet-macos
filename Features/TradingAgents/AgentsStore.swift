// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/AgentsStore.swift
// Description      : The shared read state of the agents section: the list of
//                    agents, the runtime of the agent engine (workers, leases,
//                    loops, queue), the kill switch as the server states it,
//                    the templates and the server locks. It only reads; the one
//                    operation it carries is the emergency stop (engage: no
//                    passkey; release: the Core's verified passkey approval).
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

@MainActor @Observable final class AgentsStore {
    let model: AppModel
    let api: AgentsAPI
    let risk: RiskAPI
    let developer: DeveloperAPI

    private(set) var agents: [Agent]?
    private(set) var agentsAt: Date?
    private(set) var agentsFromCache = false
    private(set) var agentsError: String?
    private(set) var runtime: AgentRuntimeStatus?
    private(set) var runtimeError: String?
    private(set) var templates: AgentTemplates?
    private(set) var templatesError: String?
    /// Every server lock with its state and the server's sentence (from the developer status route).
    private(set) var locks: [ExecutionLock]?
    private(set) var locksError: String?
    private(set) var loading = false

    // emergency stop
    private(set) var killBusy = false
    var killError: String?
    private(set) var release: RiskSwitchReleaseApproval?
    private(set) var releasing = false

    init(model: AppModel) {
        self.model = model
        api = AgentsAPI(model.client); risk = RiskAPI(model.client); developer = DeveloperAPI(model.client)
    }

    /// The kill switch as last stated by the server; nil = unknown (never assumed released).
    var killSwitch: AgentKillSwitchState? { runtime?.killSwitch }

    func lock(_ id: String) -> ExecutionLock? { locks?.first { $0.id == id } }

    func loadCache() async {
        guard agents == nil, let s: Snapshot<[Agent]> = await SnapshotStore.shared.load("agents.list") else { return }
        if agents == nil { agents = s.value; agentsAt = s.savedAt; agentsFromCache = true }
    }

    func refresh() async {
        guard model.phase == .signedIn, !loading else { return }
        loading = true; defer { loading = false }
        let api = api, developer = developer
        async let a = Result.catching { try await api.list() }
        async let r = Result.catching { try await api.runtimeStatus() }
        async let l = Result.catching { try await developer.status() }
        switch await a {
        case .success(let v): agents = v; agentsAt = Date(); agentsFromCache = false; agentsError = nil; await SnapshotStore.shared.save(v, as: "agents.list")
        case .failure(let e): agentsError = model.describe(e); if agents != nil { agentsFromCache = true }
        }
        switch await r {
        case .success(let v): runtime = v; runtimeError = nil
        case .failure(let e): runtimeError = model.describe(e)
        }
        switch await l {
        case .success(let v): locks = v.capabilities; locksError = v.capabilities == nil ? "Le serveur n’a pas publié l’état de ses verrous." : nil
        case .failure(let e): locksError = model.describe(e)
        }
        if templates == nil { await loadTemplates() }
    }

    func loadTemplates() async {
        do { templates = try await api.templates(); templatesError = nil } catch { templatesError = model.describe(error) }
    }

    /// Reads while the screen is visible and the app is active; nothing is fetched in the background.
    func poll() async {
        await loadCache()
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            if AppActivity.isActive, !model.isOffline { await refresh() }
        }
    }

    // MARK: emergency stop

    /// One click + confirmation, no passkey: no agent, key or mandate can add risk until the owner releases it.
    func engageKillSwitch() async {
        guard !killBusy else { return }
        killBusy = true; killError = nil; defer { killBusy = false }
        do {
            let s = try await api.engageKillSwitch(reason: "engagé par le propriétaire depuis l’app macOS")
            if !s.engaged { killError = "Le serveur n’a PAS confirmé l’arrêt d’urgence. Vérifiez l’état ci-dessous et réessayez." }
            else { Notifier.post(title: "Arrêt d’urgence des agents engagé", body: "Aucun agent, clé ou mandat ne peut ajouter de risque tant qu’il n’est pas levé.") }
        } catch { killError = model.describe(error) }
        await refresh()
    }

    /// Step 1 of a release: the switch as displayed is read from the risk engine, and the release intent must name that very engagement.
    func prepareRelease() async {
        guard model.canOperate, !killBusy else { return }
        killBusy = true; killError = nil; defer { killBusy = false }
        do {
            let state = try await risk.state()
            switch try await risk.prepareRelease(.killSwitch, displayed: state.switches.killSwitch) {
            case .notEngaged: killError = "L’arrêt d’urgence n’est pas engagé : il n’y a rien à lever."; await refresh()
            case .approval(let a): release = a
            }
        } catch { killError = model.describe(error) }
    }

    func cancelRelease() { release = nil; killError = nil }

    func approveRelease() async {
        guard let a = release, !releasing else { return }
        releasing = true; killError = nil; defer { releasing = false }
        do {
            let s = try await risk.release(a, with: model.authenticator)
            release = nil
            if s.killSwitch.on { killError = "Le serveur indique que l’arrêt d’urgence est toujours engagé." }
            else { Notifier.post(title: "Arrêt d’urgence levé", body: "Les agents ne reprennent pas seuls : chaque agent se relance explicitement.") }
            await refresh()
        } catch PasskeyError.cancelled {
        } catch {
            killError = model.describe(error)
            // the answer may have been lost: read the real state instead of signing again
            await refresh()
            if killSwitch?.engaged == false { release = nil; killError = nil }
        }
    }
}

extension Result where Failure == Error {
    /// Runs an async throwing read and keeps its outcome, so that several reads can fail independently.
    static func catching(_ body: @Sendable () async throws -> Success) async -> Result<Success, Error> where Success: Sendable {
        do { return .success(try await body()) } catch { return .failure(error) }
    }
}
