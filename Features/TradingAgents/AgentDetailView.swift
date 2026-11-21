// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/AgentDetailView.swift
// Description      : One agent: the header with its mode band, the life-cycle
//                    controls the server allows for its family (start in
//                    research or on paper, pause, resume, stop — never a
//                    passkey), and the sections of the detail. The real mode is
//                    never a simple "start": it is reached only through the
//                    mandate section, where the passkey approves a verified
//                    mandate.
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

import SwiftUI
import SPWalletCore

struct AgentDetailView: View {
    let model: AppModel
    let store: AgentsStore
    let id: String
    let onBack: () -> Void

    enum Section: String, CaseIterable { case overview = "Aperçu", strategy = "Stratégie", activity = "Activité", performance = "Performance", vault = "Coffre", perp = "Perpétuels", mm = "Tenue de marché", mandate = "Mandat et risques", config = "Configuration" }
    @State private var d: AgentDetailStore?
    @State private var section: Section = .overview
    @State private var spotFlow: SpotGoLiveFlow?
    @State private var confirmStop = false
    @State private var confirmStartLive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onBack) { Label("Tous les agents", systemImage: "chevron.left") }.buttonStyle(.link)
            if let d {
                if let a = d.agent { header(d, a); controls(d, a); sections(d, a) }
                else if let e = d.error("detail") { Banner(.danger, "Agent indisponible : \(e)"); Button("Réessayer") { Task { await d.refresh() } } }
                else { ProgressView() }
            } else { ProgressView() }
        }
        .task {
            if d == nil { d = AgentDetailStore(model: model, id: id) }
            if spotFlow == nil { spotFlow = SpotGoLiveFlow(model: model) }
            await d?.poll()
        }
        .sheet(isPresented: Binding(get: { spotFlow?.step == .review || spotFlow?.step == .approving }, set: { _ in })) {
            if let f = spotFlow, let a = f.approval { SpotMandateSheet(model: model, flow: f, approval: a) }
        }
        .onChange(of: spotFlow?.step) { _, s in if s == .done { Task { await d?.refresh(); await store.refresh() } } }
    }

    private func available(_ d: AgentDetailStore, _ a: Agent) -> [Section] {
        Section.allCases.filter { s in
            switch s {
            case .vault: a.hasVault
            case .perp: a.resolvedKind == .perp
            case .mm: d.isMarketMaking
            default: true
            }
        }
    }

    // MARK: header

    @ViewBuilder private func header(_ d: AgentDetailStore, _ a: Agent) -> some View {
        let kind = ModeKind(agent: a), s = d.summary
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(a.name).font(.title.weight(.semibold)).textSelection(.enabled)
                Spacer()
                if d.error("detail") != nil { ProvenanceTag(p: .stale, text: "Dernière lecture \(Fmt.relative(d.loadedAt))") }
                Button { Task { await d.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Relire sur le serveur")
            }
            ModeHeaderBand(kind: kind)
            if a.tradesRealMoney { Banner(.danger, "Cet agent négocie de l’argent réel sous mandat. Pour l’arrêter : « Arrêter » ci-dessous, « Révoquer le mandat » dans Mandat et risques, ou l’arrêt d’urgence en haut de l’écran — aucun n’exige de passkey.") }
            if !a.mission.isEmpty { Text(a.mission).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            VStack(alignment: .leading, spacing: 5) {
                Field(label: "État (serveur)", value: AgentText.phase(a.state) + (s.map { " · \(AgentText.lifecycle($0.state))" } ?? ""), emphasis: true)
                Field(label: "Type", value: "\(AgentText.kind(a.resolvedKind))\((s?.family ?? a.family).map { " · \(AgentText.family($0))" } ?? "")\(a.template.map { " · modèle \($0)" } ?? "")\((s?.engine ?? a.engine).map { " · moteur \($0)" } ?? "")")
                Field(label: "Stratégie", value: s?.strategy.map { "\($0.name) \($0.version) — \($0.kind == "rule" ? "règle intégrée" : "code épinglé par empreinte") · \($0.status)" } ?? (d.overview == nil ? "—" : "aucune version rattachée"))
                Field(label: "Marchés", value: a.universe.isEmpty ? "—" : a.universe.joined(separator: ", "))
                Field(label: a.resolvedKind == .spot ? "Réseau" : "Plateforme", value: "\(a.networkName ?? a.network)\(a.liveNetwork.map { " · réseau réel : \($0)" } ?? "") · pas \(a.interval)")
                Field(label: a.hasVault ? "Capital prévu" : (kind.mode == .live ? "Capital de référence" : "Capital SIMULÉ"), value: "\(Fmt.amount(a.capitalUsdc, maxFraction: 2)) USDC")
                Field(label: "Configuration", value: "version \(s?.configVersion ?? a.configVersion ?? 0)\(a.lastBar.map { " · dernière barre traitée \(Fmt.relative($0))" } ?? "")")
                if let w = d.overview?.worker?.lease { Field(label: "Travailleur", value: "\(w.owner) · battement \(Fmt.relative(w.heartbeatAt)) · \(w.active ? "bail actif" : "bail EXPIRÉ")") }
                if let r = a.stopReason ?? s?.stopReason, !r.isEmpty { Field(label: "Motif d’arrêt", value: r) }
            }
            if let e = d.error("overview") { Banner(.warning, "Vue d’ensemble indisponible : \(e)") }
        }
    }

    // MARK: life cycle

    @ViewBuilder private func controls(_ d: AgentDetailStore, _ a: Agent) -> some View {
        let kind = ModeKind(agent: a), s = d.summary
        let lifecycle = s?.state ?? .unknown, winding = s?.isWindingDown == true
        let modes = d.allowedModes
        Card("Cycle de vie") {
            if store.killSwitch?.engaged == true { Banner(.danger, "Arrêt d’urgence engagé : aucun agent ne peut ajouter de risque. Démarrer en réel sera refusé par le serveur.") }
            if winding { Banner(.warning, "Arrêt en cours : le mandat est révoqué, le moteur ferme les positions avec des ordres réducteurs.\(s?.windDown.map { " " + JSONFlat.rows($0).map { "\($0.key) : \($0.value)" }.joined(separator: " · ") } ?? "")") }
            if a.pausedFrom == "LIVE", a.resolvedKind == .spot { Banner(.warning, "Cet agent était en réel quand il a été mis en pause : son mandat a été révoqué au signataire. Le relancer en réel exige un NOUVEAU mandat approuvé avec votre passkey.") }
            if s == nil { Text("Commandes indisponibles tant que la vue d’ensemble du serveur n’est pas lue.").foregroundStyle(.secondary).font(.callout) }
            else {
                HStack(spacing: 10) {
                    if lifecycle != .active, !winding {
                        ForEach([AgentMode.research, .paper], id: \.self) { m in
                            if modes?.contains(m) ?? true { ModeButton(title: "Démarrer", kind: ModeKind(m), systemImage: "play.fill") { Task { await d.start(m) } } }
                        }
                        if lifecycle == .paused, a.pausedFrom != "LIVE" || a.resolvedKind != .spot {
                            ModeButton(title: "Reprendre", kind: a.pausedFrom == "LIVE" ? ModeKind(.live, liveNetwork: a.liveNetwork) : ModeKind(AgentMode(server: a.pausedFrom ?? a.mode.rawValue)), systemImage: "playpause.fill") { Task { await d.resume() } }
                        }
                    }
                    if lifecycle == .active, !winding { ModeButton(title: "Mettre en pause", kind: kind, systemImage: "pause.fill") { Task { await d.pause() } } }
                    if lifecycle != .stopped || a.mode == .live { ModeButton(title: winding ? "Redemander l’arrêt" : "Arrêter", kind: kind, systemImage: "stop.fill", prominent: a.mode == .live, role: .destructive) { confirmStop = true } }
                    if d.busy != nil { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }.disabled(!model.canOperate || d.busy != nil)
                Text(pauseNote(a)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                liveRow(d, a, s!)
            }
            if let n = d.notice { Banner(.info, n) }
            if let e = d.actionError { Banner(.danger, e) }
        }
        .confirmationDialog("Arrêter l’agent « \(a.name) » ?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Arrêter · \(kind.short)", role: .destructive) { Task { await d.stop() } }
            Button("Annuler", role: .cancel) {}
        } message: { Text(stopNote(a)) }
        .confirmationDialog("Démarrer en RÉEL sous le mandat en vigueur ?", isPresented: $confirmStartLive, titleVisibility: .visible) {
            Button("Démarrer · RÉEL", role: .destructive) { Task { await d.startLive() } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("L’agent enverra des ordres réels dans les bornes du mandat que vous avez déjà approuvé avec votre passkey. Ce bouton ne crée ni n’élargit aucun mandat : sans mandat en vigueur, le serveur refuse. Vous pouvez perdre les fonds engagés.") }
    }

    /// The real mode: its availability as the server states it, and the door to the mandate — never a direct start without one.
    @ViewBuilder private func liveRow(_ d: AgentDetailStore, _ a: Agent, _ s: AgentSummary) -> some View {
        let liveKind = ModeKind(.live, liveNetwork: a.liveNetwork)
        Divider()
        if d.allowedModes?.contains(.live) == false {
            Label("Mode réel indisponible pour cette famille d’agents\(d.overview?.familyModes?.liveReason.map { " : \($0)" } ?? ".")", systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if !s.live.capable {
            Label("Mode réel indisponible pour cet agent : \(s.live.reason ?? s.live.code ?? "raison non précisée par le serveur")", systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if a.mode != .live {
            HStack(spacing: 10) {
                ModeButton(title: "Passer en réel : approuver un mandat…", kind: liveKind, systemImage: "touchid") { section = a.resolvedKind == .perp ? .perp : d.isMarketMaking ? .mm : .mandate }
                if let m = s.mandate, s.state != .active || s.mode != .live {
                    ModeButton(title: "Démarrer sous le mandat en vigueur", kind: liveKind, systemImage: "play.fill") { confirmStartLive = true }.help("Mandat \(m.kind) \(m.id), déjà approuvé avec votre passkey.")
                }
                Spacer(minLength: 0)
            }.disabled(!model.canOperate || d.busy != nil)
            Text("Le réel n’existe que sous un mandat : ses bornes sont affichées en entier et approuvées avec votre passkey avant tout ordre.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pauseNote(_ a: Agent) -> String {
        switch (a.resolvedKind, a.mode) {
        case (.spot, .live): "Pause en réel : aucun nouvel ordre ET le mandat est révoqué au signataire (reprendre exigera un nouveau mandat). Arrêter révoque aussi le mandat. Aucune de ces commandes ne demande de passkey."
        case (.perp, .live): "Pause en réel : aucune nouvelle exposition ; les positions sont CONSERVÉES sur la plateforme et le mandat reste en vigueur. Arrêter révoque le mandat et ferme les positions avec des ordres réducteurs."
        default: "Démarrer, mettre en pause et arrêter n’ajoutent aucune autorité et ne demandent jamais de passkey."
        }
    }
    private func stopNote(_ a: Agent) -> String {
        guard a.mode == .live else { return "L’agent cesse de fonctionner. Rien n’est signé." }
        if a.resolvedKind == .perp { return "Le mandat est révoqué au signataire et les positions sont fermées avec des ordres réducteurs (résultat non garanti : prix de marché). L’agent reste « arrêt en cours » jusqu’à la fin." }
        if d?.isMarketMaking == true { return "Le mandat de cotation est révoqué ; les cotations sont retirées." }
        return "Le mandat est révoqué au signataire : plus aucun échange ne peut être signé. Les fonds restent dans le coffre ; vous pourrez les rapatrier depuis l’onglet Coffre."
    }

    // MARK: sections

    @ViewBuilder private func sections(_ d: AgentDetailStore, _ a: Agent) -> some View {
        let all = available(d, a)
        Picker("Section", selection: $section) { ForEach(all, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
        switch all.contains(section) ? section : .overview {
        case .overview: AgentOverviewSection(model: model, d: d)
        case .strategy: AgentStrategySection(model: model, d: d, templates: store.templates)
        case .activity: AgentActivitySection(d: d)
        case .performance: AgentPerformanceSection(d: d)
        case .vault: AgentVaultSection(model: model, d: d)
        case .perp: PerpAgentSection(model: model, d: d, store: store)
        case .mm: MarketMakingSection(model: model, d: d, store: store)
        case .mandate: if let f = spotFlow { AgentMandateSection(model: model, d: d, store: store, spotFlow: f) }
        case .config: AgentConfigSection(model: model, d: d)
        }
    }
}
