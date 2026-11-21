// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Alerts/OpsMonitorTab.swift
// Description      : The monitoring screen: capital, result differences,
//                    exposure and the three risk books — real, testnet and
//                    simulated money always in separate blocks with their own
//                    label and never added together — each block with its own
//                    date and its own failure state. System health is in
//                    OpsHealthCards.swift.
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

struct OpsMonitorTab: View {
    let model: AppModel
    @State private var data: OpsMonitorModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data {
                    HStack {
                        Text("Lecture seule. Les montants en USD sont des estimations arrondies par le serveur ; rien ici n’est un montant à approuver.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        if data.refreshing { ProgressView().controlSize(.small) }
                        Button { Task { await data.refresh() } } label: { Label("Relire tout", systemImage: "arrow.clockwise") }.disabled(data.refreshing)
                    }
                    OpsCapitalCard(model: model, data: data)
                    OpsBooksCard(data: data)
                    OpsPnlCard(data: data)
                    OpsExposureCard(data: data)
                    OpsHealthCards(data: data)
                } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }.padding(24).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            let d = data ?? OpsMonitorModel(model: model); data = d
            await d.refresh()
            // the server caches each answer 10 to 30 s: a faster poll would read the same data
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if AppActivity.isActive, !model.isOffline { await d.refresh() }
            }
        }
    }
}

/// The frame of one monitoring block: title, the server's as-of date, the stale / failed state, then the content when there is a value.
struct OpsSectionCard<T: Sendable, Content: View>: View {
    let title: String
    let section: OpsSection<T>
    let asOf: (T) -> Date?
    let retry: () -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        Card(title, trailing: AnyView(HStack(spacing: 8) {
            if section.loading { ProgressView().controlSize(.small) }
            if let v = section.value { OpsAsOf(date: asOf(v) ?? section.fetchedAt, prefix: asOf(v) == nil ? "Reçu" : "Données du serveur") }
            if section.isStale { ProvenanceTag(p: .stale) }
        })) {
            if let v = section.value {
                if let e = section.error { Banner(.warning, "Dernière lecture en échec (\(e)). Les chiffres ci-dessous datent de la lecture précédente.") }
                content(v)
            } else if let e = section.error { OpsUnavailable(what: title, reason: e, retry: retry) }
            else { ProgressView().controlSize(.small) }
        }
    }
}

// MARK: - Capital

private struct OpsCapitalCard: View {
    let model: AppModel
    let data: OpsMonitorModel

    var body: some View {
        OpsSectionCard(title: "Capital", section: data.capital, asOf: { $0.asOf }, retry: { Task { await data.reloadCapital() } }) { c in
            Text("Trois natures d’argent, jamais additionnées : le portefeuille (réel, sur la chaîne), les coffres d’agents (réels en mode LIVE, simulés en papier) et les comptes de dérivés (réels sur réseau principal, fonds de test sur testnet, simulés en papier). Il n’y a volontairement aucun total général.").font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], alignment: .leading, spacing: 12) {
                OpsFigure(kind: .real, title: "Portefeuille sur la chaîne", value: c.wallet.usd.map { OpsFmt.usd($0) } ?? "Indisponible",
                          note: walletNote(c.wallet), unavailable: c.wallet.usd == nil)
                OpsFigure(kind: .real, title: "Agents en réel (LIVE)", value: OpsFmt.usd(c.totals.agentsLiveUsd), note: "Somme des valeurs connues des agents LIVE")
                OpsFigure(kind: .real, title: "Dérivés — plateformes, réseau principal", value: OpsFmt.usd(c.totals.derivVenueUsd), note: "Somme des comptes lus")
                OpsFigure(kind: .testnet, title: "Dérivés — testnet", value: OpsFmt.usd(c.totals.derivTestnetUsd), note: "Fonds de test : sans valeur, jamais comptés comme capital")
                OpsFigure(kind: .paper, title: "Agents en papier", value: OpsFmt.usd(c.totals.agentsPaperUsd), note: "Simulation")
                OpsFigure(kind: .paper, title: "Dérivés en papier", value: OpsFmt.usd(c.totals.derivPaperUsd), note: "Simulation")
            }
            Text("Positions ouvertes : \(c.counts.openPositions.agents) (agents), \(c.counts.openPositions.derivatives) (dérivés) · ordres ouverts : \(c.counts.openOrders.agents) (agents), \(c.counts.openOrders.derivatives) (dérivés) · agents par état : \(c.counts.agents.keys.sorted().map { "\(OpsText.agentState($0)) \(c.counts.agents[$0] ?? 0)" }.joined(separator: ", ").opsIfEmpty("aucun"))")
                .font(.callout).foregroundStyle(.secondary)
            if !c.agents.isEmpty {
                Divider(); Text("Agents").font(.subheadline.weight(.semibold))
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    GridRow { Text("Agent"); Text("Nature"); Text("État"); Text("Capital alloué"); Text("Valeur"); Text("Positions"); Text("Valeur au") }.font(.caption).foregroundStyle(.secondary)
                    ForEach(c.agents) { a in
                        GridRow {
                            Text(a.name).lineLimit(1)
                            OpsBookTag(kind: a.real ? .real : .paper)
                            VStack(alignment: .leading, spacing: 0) { Text(OpsText.agentState(a.state)); if let r = a.stopReason { Text(r).font(.caption).foregroundStyle(Theme.warning).lineLimit(2) } }
                            Text(OpsFmt.usd(a.capitalUsd)).monospacedDigit()
                            Text(a.equityUsd.map { OpsFmt.usd($0) } ?? "Aucun relevé").monospacedDigit().foregroundStyle(a.equityUsd == nil ? .secondary : .primary)
                            Text("\(a.positions)").monospacedDigit()
                            Text(Fmt.date(a.asOf)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            if !c.derivatives.isEmpty {
                Divider(); Text("Comptes de dérivés").font(.subheadline.weight(.semibold))
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    GridRow { Text("Compte"); Text("Nature"); Text("Valeur"); Text("Marge utilisée"); Text("Latent"); Text("Pos. / ordres"); Text("Valeur au") }.font(.caption).foregroundStyle(.secondary)
                    ForEach(c.derivatives) { d in
                        GridRow {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(d.label) · \(d.venue)").lineLimit(1)
                                if let h = d.halt { Text("Arrêt : \(h)").font(.caption).foregroundStyle(Theme.negative) }
                                if let dv = d.divergence { Text("Divergence : \(dv)").font(.caption).foregroundStyle(Theme.negative) }
                            }
                            OpsBookTag(kind: d.kind == "paper" ? .paper : d.real ? .real : .testnet)
                            Text(d.equity.map { OpsFmt.usd($0) } ?? "Aucun relevé").monospacedDigit().foregroundStyle(d.equity == nil ? .secondary : .primary)
                            Text(OpsFmt.usd(d.marginUsed)).monospacedDigit()
                            Text(OpsFmt.signedUsd(d.unrealizedPnl)).monospacedDigit().foregroundStyle(Theme.change(d.unrealizedPnl))
                            Text("\(d.positions) / \(d.openOrders)").monospacedDigit()
                            Text(Fmt.date(d.asOf)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func walletNote(_ w: MonitorCapital.Wallet) -> String {
        var parts = ["\(w.assets) actifs"]
        if let cad = w.cad { parts.append("≈ " + cad.formatted(.currency(code: "CAD").precision(.fractionLength(2)))) }
        if w.usd == nil { parts.append("aucun prix disponible : le total n’est pas calculé") }
        if w.unpriced > 0 { parts.append("\(w.unpriced) soldes sans prix, hors total") }
        if w.unavailable > 0 { parts.append("\(w.unavailable) soldes illisibles, hors total") }
        return parts.joined(separator: " · ") + (w.isComplete ? "" : " — estimation incomplète")
    }
}

/// One headline figure with the nature of its money on it.
struct OpsFigure: View {
    let kind: OpsBookKind
    let title: String
    let value: String
    var note: String?
    var unavailable = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { OpsBookTag(kind: kind); Spacer(); ProvenanceTag(p: unavailable ? .unavailable : kind.isSimulated ? .simulated : .estimate) }
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(unavailable ? Theme.negative : .primary)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(kind.color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: kind.isSimulated ? [4, 3] : [])))
    }
}

// MARK: - Risk books (paper / testnet / real)

private struct OpsBooksCard: View {
    let data: OpsMonitorModel

    var body: some View {
        OpsSectionCard(title: "Livres de risque", section: data.summary, asOf: { $0.ts }, retry: { Task { await data.reloadSummary() } }) { s in
            Text("Trois livres séparés du service de risque. Chaque livre a sa propre date et son propre état ; aucun chiffre n’est additionné entre eux.").font(.callout).foregroundStyle(.secondary)
            OpsBookView(kind: .real, title: "Livre réel (réseau principal)", section: s.books.live)
            Divider()
            OpsBookView(kind: .testnet, title: "Livre testnet (fonds de test)", section: s.books.liveTestnet)
            Divider()
            OpsBookView(kind: .paper, title: "Livre papier (simulation)", section: s.books.paper)
            Divider()
            switch s.agentsPnl {
            case .ok(let p, let asOf):
                HStack { Text("Résultat des agents aujourd’hui, par mode").font(.subheadline.weight(.semibold)); Spacer(); OpsAsOf(date: asOf) }
                ForEach(p.today.keys.sorted(), id: \.self) { mode in
                    if let m = p.today[mode] {
                        HStack {
                            OpsBookTag(kind: OpsBookKind(mode: mode))
                            Text(m.abs.map { OpsFmt.signedUsd($0) } ?? "Aucun chiffre").monospacedDigit().foregroundStyle(m.abs == nil ? .secondary : Theme.change(m.abs))
                            Text("\(m.agents) agents\(m.partial ? " · fenêtre partielle" : "")\(m.reason.map { " · \($0 == "research_no_pnl" ? "la recherche n’a pas de résultat" : $0 == "no_snapshot" ? "aucun relevé" : $0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                Text("Jour selon le fuseau \(p.tz). \(p.note == "flows_included" ? "Écarts de valeur : un dépôt ou un retrait dans la journée y est compté." : p.note)").font(.caption).foregroundStyle(.secondary)
            case .failed(let code, _): OpsUnavailable(what: "Résultat des agents aujourd’hui", reason: OpsText.sectionError(code))
            }
        }
    }
}

private struct OpsBookView: View {
    let kind: OpsBookKind
    let title: String
    let section: DashboardSection<DashboardBook>

    var body: some View {
        switch section {
        case .failed(let code, _):
            HStack { OpsBookTag(kind: kind); OpsUnavailable(what: title, reason: OpsText.sectionError(code)) }
        case .ok(let b, let asOf):
            VStack(alignment: .leading, spacing: 6) {
                HStack { OpsBookTag(kind: kind); Text(title).font(.subheadline.weight(.semibold)); Spacer(); OpsAsOf(date: asOf) }
                if !b.isComplete { Banner(.warning, "Livre incomplet — sources illisibles : \(b.errors.joined(separator: " ; ")). Les chiffres ci-dessous n’incluent pas ces comptes.") }
                if b.isEmpty && b.isComplete { Text("Aucun compte ni position dans ce livre.").foregroundStyle(.secondary) }
                else {
                    HStack(spacing: 22) {
                        OpsMini(label: "Valeur des comptes", value: "\(Fmt.amount(b.equity, maxFraction: 2)) USD")
                        OpsMini(label: "Exposition brute", value: "\(Fmt.amount(b.grossExposure, maxFraction: 2)) USD")
                        OpsMini(label: "Levier du livre", value: b.leverage.map { "\(Fmt.amount($0, maxFraction: 2))×" } ?? "—")
                        if let p = b.pnl {
                            OpsMini(label: "Réalisé aujourd’hui", value: "\(Fmt.amount(p.realizedToday, maxFraction: 2)) USD")
                            OpsMini(label: "Latent aujourd’hui", value: "\(Fmt.amount(p.unrealizedToday, maxFraction: 2)) USD")
                        }
                    }
                    if !b.positions.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                            GridRow { Text("Position"); Text("Sens"); Text("Taille"); Text("Notionnel"); Text("Levier"); Text("Liquidation estimée"); Text("Latent") }.font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(b.positions.enumerated()), id: \.offset) { _, p in
                                GridRow {
                                    Text("\(p.asset) · \(p.venue)").lineLimit(1)
                                    Text(p.side == "long" ? "Long" : p.side == "short" ? "Short" : p.side)
                                    Text(Fmt.amount(p.size, maxFraction: 6)).monospacedDigit()
                                    Text("\(Fmt.amount(p.notional, maxFraction: 2)) USD").monospacedDigit()
                                    Text("\(Fmt.amount(p.leverage, maxFraction: 2))×").monospacedDigit()
                                    Text(p.liquidationPrice.map { "\(Fmt.amount($0, maxFraction: 4))\(p.liquidationDistanceBps.map { " (à \(Fmt.amount($0, maxFraction: 0)) pb)" } ?? "")" } ?? "—").monospacedDigit()
                                    Text("\(Fmt.amount(p.unrealizedPnl, maxFraction: 2)) USD").monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct OpsMini: View {
    let label: String; let value: String
    var body: some View { VStack(alignment: .leading, spacing: 1) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).monospacedDigit() } }
}

// MARK: - PnL

private struct OpsPnlCard: View {
    let data: OpsMonitorModel

    var body: some View {
        OpsSectionCard(title: "Écarts de résultat", section: data.pnl, asOf: { $0.asOf }, retry: { Task { await data.reloadPnl() } }) { p in
            Text("Différences de valeur entre deux relevés enregistrés (aujourd’hui, 7 jours, 30 jours ; jour selon le fuseau \(p.tz)). \(p.note == "flows_included" ? "Un dépôt ou un retrait dans la fenêtre est compté comme résultat." : p.note) Ce ne sont pas des performances de stratégie, et les lignes simulées ne se comparent pas aux lignes réelles.").font(.callout).foregroundStyle(.secondary)
            if p.agents.isEmpty && p.derivatives.isEmpty { Text("Aucun agent ni compte de dérivés.").foregroundStyle(.secondary) }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow { Text("Ligne"); Text("Nature"); Text("Aujourd’hui"); Text("7 jours"); Text("30 jours"); Text("Valeur"); Text("Au") }.font(.caption).foregroundStyle(.secondary)
                ForEach(p.agents) { a in
                    GridRow {
                        Text("Agent · \(a.name)").lineLimit(1); OpsBookTag(kind: a.real ? .real : .paper)
                        OpsPnlCell(f: a.today); OpsPnlCell(f: a.d7); OpsPnlCell(f: a.d30)
                        Text(OpsFmt.usd(a.equity)).monospacedDigit(); Text(Fmt.date(a.asOf)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(p.derivatives) { d in
                    GridRow {
                        Text("Dérivés · \(d.label)").lineLimit(1); OpsBookTag(kind: d.kind == "paper" ? .paper : d.real ? .real : .testnet)
                        OpsPnlCell(f: d.today); OpsPnlCell(f: d.d7); OpsPnlCell(f: d.d30)
                        Text(OpsFmt.usd(d.equity)).monospacedDigit(); Text(Fmt.date(d.asOf)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct OpsPnlCell: View {
    let f: MonitorPnlFigure?
    var body: some View {
        if let f {
            VStack(alignment: .leading, spacing: 0) {
                Text(OpsFmt.signedUsd(f.abs) + (f.pct.map { " (\(OpsFmt.fraction($0)))" } ?? "")).monospacedDigit().foregroundStyle(Theme.change(f.abs))
                if f.partial { Text("partiel, depuis \(f.from.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(Theme.warning) }
            }
        } else { Text("Aucun relevé").foregroundStyle(.secondary) }
    }
}

// MARK: - Exposure

private struct OpsExposureCard: View {
    let data: OpsMonitorModel

    var body: some View {
        OpsSectionCard(title: "Exposition par actif", section: data.exposure, asOf: { $0.asOf }, retry: { Task { await data.reloadExposure() } }) { e in
            Text(e.caveat == "spot_and_perp_differ" ? "Le net est une indication de direction, pas un ratio de couverture : le comptant et les perpétuels sont des instruments différents." : e.caveat).font(.callout).foregroundStyle(.secondary)
            table(title: "Réel", kind: .real, rows: e.real)
            Divider()
            table(title: "Simulé et testnet (comptes papier, agents papier, comptes testnet)", kind: .paper, rows: e.simulated)
        }
    }

    @ViewBuilder private func table(title: String, kind: OpsBookKind, rows: [MonitorExposure.Row]) -> some View {
        HStack { OpsBookTag(kind: kind); Text(title).font(.subheadline.weight(.semibold)) }
        if rows.isEmpty { Text("Aucune exposition.").foregroundStyle(.secondary) }
        else {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { Text("Actif"); Text("Comptant"); Text("Perp. long"); Text("Perp. short"); Text("Net (indicatif)"); Text("Brut"); Text("") }.font(.caption).foregroundStyle(.secondary)
                ForEach(rows) { r in
                    GridRow {
                        Text(r.asset).fontWeight(.medium)
                        Text(OpsFmt.usd(r.spotUsd)).monospacedDigit(); Text(OpsFmt.usd(r.perpLongUsd)).monospacedDigit(); Text(OpsFmt.usd(r.perpShortUsd)).monospacedDigit()
                        Text(OpsFmt.signedUsd(r.netUsd)).monospacedDigit(); Text(OpsFmt.usd(r.grossUsd)).monospacedDigit()
                        if r.priced { Text("") } else { Label("Incomplet : une position sans prix", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning) }
                    }
                }
            }
        }
    }
}

extension String {
    func opsIfEmpty(_ other: String) -> String { isEmpty ? other : self }
}
