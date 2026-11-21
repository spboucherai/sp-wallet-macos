// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/AgentDetailSections.swift
// Description      : The reading sections of an agent: alerts, positions,
//                    timeline, orders, signals, journal and performance. Every
//                    list and figure belongs to ONE mode, framed with that
//                    mode's colour and label; paper and real are shown side by
//                    side, never added. A source that failed is shown as
//                    unavailable, a missing statistic with the server's reason.
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
import Charts
import SPWalletCore

/// Chooses the mode of the mode-scoped lists; the band below names what is being looked at.
struct ModeScopePicker: View {
    @Bindable var d: AgentDetailStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode affiché", selection: $d.viewMode) {
                ForEach([AgentMode.research, .paper, .live], id: \.self) { Text(ModeKind($0, liveNetwork: d.agent?.liveNetwork).short).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 420)
            ModeHeaderBand(kind: ModeKind(d.viewMode, liveNetwork: d.agent?.liveNetwork))
        }
    }
}

struct Unavailable: View {
    let what: String
    let error: String?
    var body: some View {
        if let error { Banner(.danger, "\(what) indisponible : \(error)") } else { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Lecture…").foregroundStyle(.secondary) } }
    }
}

struct IndexedRow<T>: Identifiable { let id: Int; let value: T }

// MARK: overview

struct AgentOverviewSection: View {
    let model: AppModel
    let d: AgentDetailStore

    var body: some View {
        alerts
        positions
        Card("Chronologie (signal → décision → ordre → exécution → erreur)") {
            ModeScopePicker(d: d)
            let kind = ModeKind(d.viewMode, liveNetwork: d.agent?.liveNetwork)
            if let items = d.timeline[d.viewMode] {
                if items.isEmpty { Text("Aucun événement dans ce mode.").foregroundStyle(.secondary) }
                else {
                    Table(items.prefix(200).enumerated().map { IndexedRow(id: $0.offset, value: $0.element) }) {
                        TableColumn("Date") { r in Text(Fmt.dateSeconds(r.value.ts)).monospacedDigit() }.width(150)
                        TableColumn("Type") { r in Text(r.value.type) }.width(90)
                        TableColumn("Événement") { r in Text(r.value.title + (r.value.body.map { " — \($0)" } ?? "")).lineLimit(2).help(r.value.body ?? r.value.title).foregroundStyle(severityColor(r.value.severity)) }
                        TableColumn("Code") { r in Text(r.value.code ?? "") .font(.caption) }.width(140)
                    }.frame(height: min(CGFloat(items.prefix(200).count) * 30 + 34, 380)).modeFramed(kind)
                }
            } else { Unavailable(what: "Chronologie", error: d.error("timeline.\(d.viewMode.rawValue)")) }
        }
    }

    @ViewBuilder private var alerts: some View {
        let a = d.agent, list = alertItems
        Card("Alertes") {
            if list.isEmpty { Label("Aucune alerte signalée par le serveur pour cet agent.", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            ForEach(Array(list.enumerated()), id: \.offset) { _, x in Banner(x.0, x.1) }
            if let j = d.journal[d.viewMode]?.filter({ ["warning", "error", "critical"].contains($0.severity ?? "") }).prefix(8), !j.isEmpty {
                Text("Derniers avertissements du journal · \(ModeKind(d.viewMode, liveNetwork: a?.liveNetwork).short)").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(j)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: e.severity == "warning" ? "exclamationmark.triangle.fill" : "exclamationmark.octagon.fill").foregroundStyle(severityColor(e.severity))
                        Text(Fmt.dateSeconds(e.ts)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Text(e.title + (e.body.map { " — \($0)" } ?? "")).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var alertItems: [(Banner.Kind, String)] {
        var out: [(Banner.Kind, String)] = []
        guard let a = d.agent else { return out }
        if let r = a.stopReason, !r.isEmpty { out.append((.warning, "Motif d’arrêt : \(r)")) }
        for (label, v) in [("Suspension", a.hold), ("Signalement", a.flag), ("Fermeture en cours", a.flattening)] {
            if let v, !v.isNull, v.boolValue != false { out.append((.warning, "\(label) : \(JSONFlat.rows(v).map { "\($0.key) = \($0.value)" }.joined(separator: " · "))")) }
        }
        if case .spot(let s)? = d.detail {
            if let m = s.mandateStatus {
                if m.revoked { out.append((.info, "Le mandat de cet agent est révoqué au signataire.")) }
                else if m.expired { out.append((.warning, "Le mandat a expiré le \(Fmt.date(m.expiry)) : plus aucun échange n’est signé.")) }
                else if m.active, m.expiry.timeIntervalSinceNow < 3 * 86_400 { out.append((.warning, "Le mandat expire \(Fmt.relative(m.expiry)).")) }
            }
            if s.vault == nil, a.hasVault { out.append((.danger, "Les soldes du coffre n’ont pas pu être lus sur la chaîne. Ce n’est pas un coffre vide.")) }
        }
        if case .perp(let p)? = d.detail {
            if let h = p.account?.halt { out.append((.warning, "Disjoncteur du compte PAPIER : \(h)")) }
            if let e = p.live?.exit { out.append((.warning, "Sortie du réel (\(Fmt.date(e.ts))) : \(e.reason) [\(e.code)]")) }
            for h in p.live?.holds ?? [] { out.append((.warning, "Retenue \(h.symbol) (\(h.bar)) : \(h.reason) [\(h.code)]")) }
            if let w = p.windDown { out.append((.warning, "Fermeture en cours\(w.until.map { " jusqu’au \(Fmt.date($0))" } ?? "") : \(w.text ?? "") · \(w.openPositions.map(String.init) ?? "?") position(s), \(w.openOrders.map(String.init) ?? "?") ordre(s) ouverts.")) }
        }
        if let h = d.overview?.runtime?.hold, !h.isNull, h.boolValue != false { out.append((.warning, "Suspension du moteur : \(JSONFlat.rows(h).map { "\($0.key) = \($0.value)" }.joined(separator: " · "))")) }
        if let w = d.overview?.worker?.lease, !w.active, d.summary?.state == .active { out.append((.warning, "L’agent est actif mais le bail de son travailleur a expiré : il n’est peut-être traité par aucun processus.")) }
        for j in d.overview?.jobs.filter({ $0.status == .failed || $0.deadLettered == true }).prefix(3) ?? [] { out.append((.warning, "Tâche \(j.kind) en échec\(j.error.map { " : \($0)" } ?? "").")) }
        return out
    }

    @ViewBuilder private var positions: some View {
        switch d.detail {
        case .spot(let s):
            Card("Coffre — soldes réels", trailing: AnyView(ProvenanceTag(p: s.vault == nil ? .unavailable : .verified))) {
                if let v = s.vault {
                    if v.isEmpty { Text("Le coffre ne détient rien sur ce réseau.").foregroundStyle(.secondary) }
                    ForEach(v) { b in VaultBalanceRow(balance: b) }
                    Text("Ces soldes sont de l’argent réel quel que soit le mode de l’agent. Détail, dépôt et retour dans l’onglet Coffre.").font(.caption).foregroundStyle(.secondary)
                } else { Banner(.danger, "Soldes illisibles sur la chaîne pour l’instant. Ce n’est pas un solde nul.") }
            }
            if let p = s.paper {
                let kind = ModeKind(.paper)
                Card("Positions simulées", trailing: AnyView(ModeTag(kind: kind))) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(p.positions, id: \.symbol) { x in
                            HStack { AssetBadge(symbol: x.symbol, size: 24); Text(x.symbol).fontWeight(.medium); Spacer(); Text("\(Fmt.amount(x.units, maxFraction: 8)) · \(AgentText.usd(x.usd).map { "≈ \($0)" } ?? "valeur inconnue")").monospacedDigit() }
                        }
                        HStack { Text("Liquidités simulées (\(p.cashSymbol))"); Spacer(); Text(AgentText.usd(p.cashUsd) ?? "—").monospacedDigit() }
                        Text("Portefeuille PAPIER au \(Fmt.date(p.asOf)) : rien de ceci n’existe sur la chaîne et rien ne s’ajoute aux soldes réels du coffre.").font(.caption).foregroundStyle(.secondary)
                    }.modeFramed(kind)
                }
            }
        case .perp(let p):
            if let acct = p.account {
                let kind = ModeKind(.paper)
                Card("Positions du compte simulé", trailing: AnyView(ModeTag(kind: kind))) {
                    VStack(alignment: .leading, spacing: 8) {
                        JSONFacts(value: acct.state, depth: 1, empty: "État du compte simulé indisponible.")
                        Text("Positions (\(acct.positions.count))").font(.callout.weight(.medium))
                        JSONList(items: acct.positions, empty: "Aucune position simulée.")
                    }.modeFramed(kind)
                }
            }
            if let l = p.live, l.active || l.account != nil {
                let kind = ModeKind(.live, liveNetwork: l.network)
                Card("Compte réel sur la plateforme", trailing: AnyView(ModeTag(kind: kind))) {
                    JSONFacts(value: l.account, depth: 2, empty: "Le compte de la plateforme n’a pas été lu.").modeFramed(kind)
                }
            }
        case .runtime:
            if let b = d.overview?.runtime?.book {
                let kind = ModeKind(b.simulated ? .paper : d.summary?.mode ?? .unknown)
                Card("Carnet de l’agent", trailing: AnyView(ModeTag(kind: kind))) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ModeFigure(label: "PnL réalisé", value: AgentText.usd(b.realizedPnl), kind: kind, reason: "non rapporté")
                            ModeFigure(label: "Frais", value: AgentText.usd(b.fees), kind: kind, reason: "non rapporté")
                            ModeFigure(label: "Financement", value: AgentText.usd(b.funding), kind: kind, reason: "non rapporté")
                        }
                        Text("Positions").font(.callout.weight(.medium)); JSONFacts(value: b.positions, empty: "Aucune position.")
                        if let q = b.quotes, !q.isNull { Text("Cotations").font(.callout.weight(.medium)); JSONFacts(value: q) }
                        if let pr = b.pair, !pr.isNull { Text("Paire").font(.callout.weight(.medium)); JSONFacts(value: pr) }
                    }.modeFramed(kind)
                }
            } else { Card("Positions") { Text("Cet agent ne publie pas de carnet de positions.").foregroundStyle(.secondary) } }
        case nil: EmptyView()
        }
    }
}

func severityColor(_ s: String?) -> Color {
    switch s { case "error", "critical": Theme.negative; case "warning": Theme.warning; default: .primary }
}

struct VaultBalanceRow: View {
    let balance: VaultBalance
    var body: some View {
        HStack(spacing: 10) {
            AssetBadge(symbol: balance.assetSymbol, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(balance.assetSymbol) — \(balance.name)").fontWeight(.medium)
                Text(balance.role == "gas" ? "gaz (paie les frais, non négocié)" : balance.role == "cash" ? "monnaie de règlement" : "actif négocié").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Fmt.amount(balance.display, maxFraction: 8)) \(balance.assetSymbol)").monospacedDigit()
                Text(AgentText.usd(balance.usd).map { "≈ \($0)" } ?? "sans prix").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

// MARK: activity

struct AgentActivitySection: View {
    let d: AgentDetailStore
    enum Kind: String, CaseIterable { case orders = "Ordres", signals = "Signaux", journal = "Journal" }
    @State private var what: Kind = .orders

    var body: some View {
        let m = d.viewMode, kind = ModeKind(m, liveNetwork: d.agent?.liveNetwork)
        Card("Activité") {
            ModeScopePicker(d: d)
            Picker("Liste", selection: $what) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 320).labelsHidden()
            switch what {
            case .orders:
                if m == .research { Text("La recherche n’émet aucun ordre : ses résultats sont des rapports de backtest (onglet Stratégie).").foregroundStyle(.secondary) }
                if let rows = d.orders[m] {
                    if rows.isEmpty { Text("Aucun ordre dans ce mode.").foregroundStyle(.secondary) }
                    else {
                        Table(rows) {
                            TableColumn("Date") { o in Text(Fmt.dateSeconds(o.ts)).monospacedDigit() }.width(150)
                            TableColumn("Marché") { o in Text(o.instrument ?? "—") }.width(120)
                            TableColumn("Sens") { o in Text((o.side ?? "—") + (o.reduceOnly == true ? " · réducteur" : "")) }.width(110)
                            TableColumn("Taille / notionnel") { o in Text("\(Fmt.amount(o.size, maxFraction: 8)) / \(Fmt.amount(o.notional, maxFraction: 2))").monospacedDigit() }.width(170)
                            TableColumn("Exécuté") { o in Text(o.filledSize.map { "\(Fmt.amount($0, maxFraction: 8)) @ \(Fmt.amount(o.avgFillPrice, maxFraction: 6))" } ?? "—").monospacedDigit() }.width(170)
                            TableColumn("État") { o in Text(o.state).fontWeight(o.state == "FILLED" ? .semibold : .regular).foregroundStyle(["REJECTED", "FAILED"].contains(o.state) ? Theme.negative : .primary) }.width(100)
                            TableColumn("Motif") { o in Text(o.reason ?? o.detail ?? "").lineLimit(1).help(o.detail ?? o.reason ?? "") }
                        }.frame(height: min(CGFloat(rows.count) * 28 + 34, 420)).modeFramed(kind)
                        Text("Seul l’état FILLED est une exécution. \(m == .live ? "Ordres réels, tels que la plateforme ou la chaîne les a rapportés." : "Ordres et exécutions SIMULÉS : aucun argent n’a bougé.")").font(.caption).foregroundStyle(.secondary)
                    }
                } else { Unavailable(what: "Ordres", error: d.error("orders.\(m.rawValue)")) }
            case .signals:
                if let rows = d.signals[m] {
                    if rows.isEmpty { Text("Aucun signal dans ce mode.").foregroundStyle(.secondary) }
                    else {
                        Table(rows) {
                            TableColumn("Date") { s in Text(Fmt.dateSeconds(s.ts)).monospacedDigit() }.width(150)
                            TableColumn("Décision") { s in Text(s.decision ?? "—") }.width(110)
                            TableColumn("État") { s in Text(s.status ?? "—") }.width(90)
                            TableColumn("Fonds propres") { s in Text(Fmt.amount(s.equity, maxFraction: 2)).monospacedDigit() }.width(110)
                            TableColumn("Cibles") { s in Text(s.targets.map(JSONFlat.text) ?? "—").lineLimit(1).help(s.targets?.displayText ?? "") }
                            TableColumn("Raison") { s in Text([s.reasonCode, s.reason].compactMap { $0 }.joined(separator: " — ")).lineLimit(1).help(s.reason ?? "") }
                        }.frame(height: min(CGFloat(rows.count) * 28 + 34, 420)).modeFramed(kind)
                    }
                } else { Unavailable(what: "Signaux", error: d.error("signals.\(m.rawValue)")) }
            case .journal:
                if let rows = d.journal[m] {
                    if rows.isEmpty { Text("Journal vide dans ce mode.").foregroundStyle(.secondary) }
                    else {
                        Table(rows) {
                            TableColumn("Date") { e in Text(Fmt.dateSeconds(e.ts)).monospacedDigit() }.width(150)
                            TableColumn("Type") { e in Text(e.kind) }.width(100)
                            TableColumn("Entrée") { e in Text(e.title + (e.body.map { " — \($0)" } ?? "")).lineLimit(2).help(e.body ?? e.title).foregroundStyle(severityColor(e.severity)) }
                            TableColumn("Code") { e in Text(e.code ?? "").font(.caption) }.width(140)
                            TableColumn("Config.") { e in Text(e.configVersion.map { "v\($0)" } ?? "") }.width(50)
                        }.frame(height: min(CGFloat(rows.count) * 30 + 34, 420)).modeFramed(kind)
                    }
                } else { Unavailable(what: "Journal", error: d.error("journal.\(m.rawValue)")) }
            }
            HStack { Spacer(); Button("Relire") { Task { await d.loadScoped() } } }
        }
    }
}

// MARK: performance

struct AgentPerformanceSection: View {
    let d: AgentDetailStore

    var body: some View {
        Banner(.info, "Les performances sont lues mode par mode et ne sont JAMAIS additionnées. La recherche n’a pas de performance : ses chiffres sont des backtests (onglet Stratégie). Une performance passée, simulée ou réelle, ne promet rien.")
        ForEach([AgentMode.paper, .live], id: \.self) { m in
            let kind = ModeKind(m, liveNetwork: d.agent?.liveNetwork)
            Card(m == .paper ? "Performance sur papier" : "Performance en réel", trailing: AnyView(ModeTag(kind: kind))) {
                if let p = d.performance[m] { block(p, kind) } else { Unavailable(what: "Performance", error: d.error("performance.\(m.rawValue)")) }
            }
        }
        .task { await d.loadPerformance() }
    }

    @ViewBuilder private func block(_ p: AgentPerformance, _ kind: ModeKind) -> some View {
        let partial = !p.warnings.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            Text(p.label).font(.callout.weight(.medium)).textSelection(.enabled)
            Text("\(p.points) point(s)\(p.from.map { " du \(Fmt.date($0))" } ?? "")\(p.to.map { " au \(Fmt.date($0))" } ?? "") · \(p.orders) ordre(s) · \(p.closedTrades) transaction(s) clôturée(s)").font(.caption).foregroundStyle(.secondary)
            ForEach(p.warnings, id: \.self) { w in Banner(.warning, "Chiffres partiels — \(w.message) [\(w.code)]") }
            if p.points == 0 { Text("Aucune donnée dans ce mode : aucun chiffre n’est affiché.").foregroundStyle(.secondary) }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .topLeading)], alignment: .leading, spacing: 10) {
                    fig("PnL net", p.netPnlUsd, kind, partial, AgentText.usd, signed: true)
                    fig("Rendement total", p.totalReturn, kind, partial, AgentText.ratio, signed: true)
                    fig("Repli maximal", p.maxDrawdown, kind, partial, AgentText.ratio)
                    fig("Volatilité annualisée", p.volatility, kind, partial, AgentText.ratio)
                    fig("Sharpe", p.sharpe, kind, partial) { AgentText.number($0) }
                    fig("Sortino", p.sortino, kind, partial) { AgentText.number($0) }
                    fig("Taux de réussite", p.winRate, kind, partial, AgentText.ratio)
                    fig("Facteur de profit", p.profitFactor, kind, partial) { AgentText.number($0) }
                    fig("Rotation", p.turnover, kind, partial) { AgentText.number($0) }
                    fig("Frais", p.feesUsd, kind, partial, AgentText.usd)
                    fig("Financement", p.fundingUsd, kind, partial, AgentText.usd)
                    fig("Glissement", p.slippageUsd, kind, partial, AgentText.usd)
                }
                let curve = p.equityCurve.value
                if curve.count > 1 {
                    Chart(curve, id: \.ts) { pt in LineMark(x: .value("Date", pt.ts), y: .value("Fonds propres", pt.equity)).foregroundStyle(kind.color) }
                        .chartYScale(domain: .automatic(includesZero: false)).frame(height: 180)
                        .accessibilityLabel("Courbe des fonds propres, \(kind.title)")
                    Text("Fonds propres · \(kind.title)").font(.caption).foregroundStyle(kind.color)
                }
            }
        }.modeFramed(kind)
    }

    private func fig(_ label: String, _ f: ModedFigure, _ kind: ModeKind, _ partial: Bool, _ format: (Double?) -> String?, signed: Bool = false) -> ModeFigure {
        // the figure carries its own mode: it is shown under that mode's colour, whatever block it sits in
        ModeFigure(label: label, value: format(f.value), kind: ModeKind(f.mode, liveNetwork: kind.liveNetwork), reason: f.reason, partial: partial && f.value != nil, tint: signed ? f.value.map { Theme.change($0) } : nil)
    }
}
