// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Futures/FuturesView.swift
// Description      : Entry of the derivatives terminal. A permanent header
//                    shows the trading mode (simulation, testnet, real — colour
//                    and label, never mixed), the state of the live quote
//                    stream and the server's switches; the tabs below are the
//                    markets list, the instrument page with its order ticket,
//                    the account, the venue setup (authorization, leverage,
//                    collateral), the risk engine, GMX v2 and the read-only
//                    market explorer. Viewing any of them triggers nothing:
//                    every operation starts from an explicit button.
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

struct FuturesView: View {
    let model: AppModel
    @State private var store: FuturesStore?
    @State private var ops: FutLiveOps?
    @State private var ticket: FutTicketFlow?
    @State private var tab: Tab = .markets

    enum Tab: String, CaseIterable, Identifiable {
        case markets, trade, account, venue, risk, gmx, explorer
        var id: String { rawValue }
        var title: String {
            switch self {
            case .markets: "Marchés"; case .trade: "Instrument et ordre"; case .account: "Compte"; case .venue: "Plateforme et collatéral"
            case .risk: "Risque"; case .gmx: "GMX v2"; case .explorer: "Explorateur"
            }
        }
    }

    var body: some View {
        Group {
            if let store, let ops, let ticket {
                VStack(spacing: 0) {
                    FutHeader(model: model, store: store, tab: $tab)
                    Divider()
                    content(store: store, ops: ops, ticket: ticket)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .sheet(item: Binding(get: { ops.sheet }, set: { if $0 == nil, ops.sheet != nil { Task { await ops.dismiss() } } })) { s in
                    FutApprovalSheet(model: model, store: store, ops: ops, sheet: s)
                }
                .futPolling(every: 60, id: store.venue) { await store.refreshTickers() }
                .futPolling(every: 20, id: "\(store.mode.rawValue)|\(store.paperId?.rawValue ?? "")") { await store.refreshAccount() }
                .futPolling(every: 90, id: "locks") { await store.loadLocks() }
                .onAppear { store.startStream() }
                .onDisappear { store.stopStream() }
            } else {
                ProgressView("Chargement des marchés dérivés…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard store == nil else { return }
            let s = FuturesStore(model: model)
            let o = FutLiveOps(model: model, store: s)
            store = s; ops = o; ticket = FutTicketFlow(model: model, store: s, ops: o)
            await s.loadAll()
        }
    }

    @ViewBuilder private func content(store: FuturesStore, ops: FutLiveOps, ticket: FutTicketFlow) -> some View {
        switch tab {
        case .markets:
            FutMarketsView(model: model, store: store) { id in store.instrumentId = id; tab = .trade }
        case .trade:
            FutScroll { FutInstrumentView(model: model, store: store, ops: ops, ticket: ticket) { tab = $0 } }
        case .account:
            FutScroll { FutAccountView(model: model, store: store, ops: ops) { id in store.instrumentId = id; tab = .trade } }
        case .venue:
            FutScroll { FutVenueView(model: model, store: store, ops: ops) }
        case .risk:
            FutScroll { FutRiskView(model: model, store: store) }
        case .gmx:
            FutScroll { FutGMXView(model: model, store: store) }
        case .explorer:
            FutScroll { FutExplorerView(model: model, store: store) }
        }
    }
}

/// The standard scrolling body of a tab (the markets tab is a full-height table instead).
struct FutScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(20).frame(maxWidth: 1320, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FutHeader: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    @Binding var tab: FuturesView.Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Dérivés").font(.largeTitle.weight(.semibold))
                FutModeBadge(mode: store.mode)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(store.streamState == .live ? Theme.positive : Theme.warning).frame(width: 8, height: 8)
                    Text(store.streamText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.accessibilityElement(children: .combine)
            }
            HStack(spacing: 14) {
                Picker("Mode", selection: $store.mode) {
                    ForEach(FutMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
                Text(store.mode.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Section", selection: $tab) {
                ForEach(FuturesView.Tab.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if !model.canOperate { Banner(.warning, "Session ou portefeuille indisponible : consultation seulement, toutes les opérations sont désactivées.") }
            if let k = store.killSwitch, k.on { Banner(.danger, "Coupe-circuit global engagé\(k.reason.map { " — \($0)" } ?? "") : aucun nouvel ordre n’ajoute de risque. Annulations et ordres strictement réducteurs restent possibles.") }
            if let r = store.readOnlySwitch, r.on { Banner(.warning, "Mode lecture seule engagé\(r.reason.map { " — \($0)" } ?? "") : seules les annulations passent.") }
            if model.portfolio?.value.halted == true { Banner(.danger, "Arrêt d’urgence du signataire actif : plus rien ne peut être signé. Il se lève sur la machine du signataire uniquement.") }
            if let e = store.streamError { Banner(.warning, e) }
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .top) { Rectangle().fill(store.mode.color).frame(height: 4).accessibilityHidden(true) }
    }
}

/// The server locks that matter to live derivatives, with the server's reasons. Read from the capability list, the risk engine and the live configuration.
struct FutLocksCard: View {
    let store: FuturesStore
    static let capabilityIds = ["deriv_live_mainnet", "deriv_gmx_live", "trading_api_execution", "deriv_mandate_mainnet"]

    var body: some View {
        Card("Verrous du serveur") {
            if let caps = store.capabilities.value {
                ForEach(Self.capabilityIds, id: \.self) { id in
                    if let c = caps.first(where: { $0.id == id }) {
                        FutLockRow(name: c.id, on: c.on, reason: c.why + (c.on || c.missing.isEmpty ? "" : " — réglage(s) du serveur : \(c.missing.joined(separator: ", "))"))
                    } else if let l = store.executionLock(id) {
                        FutLockRow(name: l.id, on: l.on, reason: l.why)
                    } else {
                        FutLockRow(name: id, on: nil, reason: "Le serveur ne publie pas ce verrou.")
                    }
                }
            } else {
                Banner(.warning, "Capacités du serveur illisibles\(store.capabilities.error.map { " : \($0)" } ?? "") — les contrôles réels restent fermés tant que le serveur ne répond pas.")
                ForEach(store.riskState.value?.locks ?? []) { l in FutLockRow(name: l.id, on: l.on, reason: l.why) }
            }
            if let c = store.config.value, let m = c.mainnet {
                Divider()
                FutLockRow(name: "Hyperliquid mainnet (configuration des comptes réels)", on: m.enabled, reason: m.reason ?? (m.enabled ? nil : m.code))
                if let mm = c.mandateLive.mainnet { FutLockRow(name: "Mandats autonomes sur mainnet", on: c.mandateLive.available && mm.enabled, reason: mm.reason ?? c.mandateLive.reason) }
            } else if let e = store.config.error {
                Text("Configuration des comptes réels illisible : \(e)").font(.callout).foregroundStyle(Theme.negative)
            }
            Text("Ces verrous sont des réglages du serveur : l’app les lit et ne peut pas les modifier. Annulations et clôtures réductrices ne passent jamais par eux.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The jurisdiction notice of the venue, as the server publishes it, with the owner's own acknowledgement for this session.
struct FutJurisdictionCard: View {
    @Bindable var store: FuturesStore
    var body: some View {
        Card("Avis de juridiction — Hyperliquid", trailing: AnyView(FutModeBadge(mode: store.mode))) {
            if let j = store.jurisdiction.value {
                let ack = store.locale == "fr" ? j.fr : j.en
                Text(ack.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let v = ack.version { Text("Version \(v)").font(.caption).foregroundStyle(.secondary) }
                    if let s = ack.source { Text("Source : \(s)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    if !ack.textMatchesHash { ProvenanceTag(p: .unavailable, text: "Empreinte du texte incohérente") }
                }
                Toggle("J’ai lu cet avis. Information générale, pas un avis juridique.", isOn: $store.jurisdictionRead).toggleStyle(.checkbox)
                if !store.jurisdictionRead { Text("Les opérations réelles (ordre, levier, dépôt, retrait, autorisation) restent désactivées tant que cette case n’est pas cochée. Annuler, clôturer et arrêter restent toujours possibles.").font(.caption).foregroundStyle(.secondary) }
            } else {
                Banner(.danger, "Avis de juridiction indisponible\(store.jurisdiction.error.map { " : \($0)" } ?? "") — aucune opération réelle n’est proposée sans lui.")
            }
        }
    }
}
