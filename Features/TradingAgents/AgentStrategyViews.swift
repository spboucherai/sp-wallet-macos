// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/AgentStrategyViews.swift
// Description      : The strategy of an agent and its evidence: the versions
//                    pinned by the hash of their code, their backtest reports
//                    and the laboratory's verdicts. Every such figure is framed
//                    as RESEARCH — a simulation on historical data under stated
//                    assumptions, never a promise and never a track record —
//                    and the laboratory's own statement is shown verbatim,
//                    including when it found no edge.
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

/// The label that precedes every backtest figure.
struct BacktestLabel: View {
    var note: String?
    var body: some View {
        let kind = ModeKind(.research)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) { ModeTag(kind: kind); Text("BACKTEST").font(.caption.weight(.bold)).foregroundStyle(kind.color) }
            Text(note ?? "Backtest = simulation sur des données historiques, sous les hypothèses indiquées. Ce n’est ni un historique réel ni une promesse de rendement.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

/// The laboratory's out-of-sample verdict for a strategy, a study or a policy, as its files state it.
struct LabVerdictView: View {
    let verdict: LabVerdict
    var body: some View {
        let v = verdict, kind = ModeKind(.research)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Verdict du laboratoire — \(v.name)\(v.version.map { " \($0)" } ?? "")").font(.callout.weight(.semibold))
                ModeTag(kind: kind, compact: true)
                Text("BACKTEST").font(.caption2.weight(.bold)).foregroundStyle(kind.color)
            }
            if !v.available { Banner(.warning, "Résultat du laboratoire indisponible\(v.reason.map { " : \($0)" } ?? ".") Aucun chiffre n’est affiché.") }
            else {
                if let s = v.statement, !s.isEmpty { Banner(v.significant == true ? .info : .warning, "Énoncé du laboratoire : \(s)") }
                switch v.significant {
                case true?: Text("Selon la règle du laboratoire, le résultat hors échantillon dépasse son seuil. Cela reste une simulation : rien ne garantit qu’il se reproduise.").font(.callout).fixedSize(horizontal: false, vertical: true)
                case false?: Text("Selon la règle du laboratoire, AUCUN avantage statistiquement significatif n’a été trouvé hors échantillon.").font(.callout.weight(.medium)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                case nil: Text("Le laboratoire n’a pas tranché sur la significativité de ce résultat.").font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    ModeFigure(label: "Sharpe dégonflé", value: AgentText.number(v.deflatedSharpe, fraction: 3), kind: kind, reason: "non calculé")
                    ModeFigure(label: "Seuil du laboratoire", value: AgentText.number(v.deflatedSharpeThreshold, fraction: 3), kind: kind, reason: "non précisé")
                    ModeFigure(label: "Essais testés", value: AgentText.number(v.trialsTested, fraction: 0), kind: kind, reason: "non précisé")
                    if let ci = v.testSharpeCi, ci.count == 2 { ModeFigure(label: "IC du Sharpe (test)", value: "\(AgentText.number(ci[0]) ?? "—") à \(AgentText.number(ci[1]) ?? "—")", kind: kind) }
                }
                if let splits = v.splits {
                    ForEach(["train", "validation", "test"].filter { splits[$0] != nil }, id: \.self) { name in
                        if let s = splits[name] ?? nil {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(name == "train" ? "Entraînement" : name == "validation" ? "Validation" : "Test (hors échantillon)").frame(width: 170, alignment: .leading).foregroundStyle(.secondary)
                                Text("rendement net \(AgentText.ratio(s.netReturn) ?? "—") · Sharpe net \(AgentText.number(s.netSharpe) ?? "—") (brut \(AgentText.number(s.grossSharpe) ?? "—")) · repli max. \(AgentText.ratio(s.maxDrawdown) ?? "—") · \(AgentText.number(s.trades, fraction: 0) ?? "—") transactions").font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                            }
                            if let st = s.stop { Text("Ce segment a été interrompu par la limite de perte du moteur ou une liquidation : \(st.reason) [\(st.code)]").font(.caption).foregroundStyle(Theme.warning) }
                        }
                    }
                }
                if v.fillsAreModelled == true { Text("Les exécutions de ce backtest sont modélisées, non observées.").font(.caption).foregroundStyle(.secondary) }
                if v.installedHashMatches == false { Banner(.warning, "Le code installé sur le serveur ne correspond PAS à celui que le laboratoire a évalué.") }
                if v.results?.matchesManifest == false { Banner(.warning, "Le fichier de résultats ne correspond pas au manifeste du laboratoire.") }
                DisclosureGroup("Hypothèses, fenêtre et portée") {
                    VStack(alignment: .leading, spacing: 4) {
                        if let w = v.window { Field(label: "Fenêtre", value: "\(w.start ?? "?") → \(w.end ?? "?") · pas \(w.interval ?? "?")\(w.bars.map { " · \(Int($0)) barres" } ?? "")") }
                        if let s = v.scope { Field(label: "Portée", value: "\(s)\(v.liveCapable.map { $0 ? " · peut passer en réel" : " · ne peut pas passer en réel" } ?? "")") }
                        if let sy = v.symbols, !sy.isEmpty { Field(label: "Marchés", value: sy.joined(separator: ", ")) }
                        if let c = v.checks, !c.isEmpty { Field(label: "Contrôles", value: c.keys.sorted().map { "\($0) : \(c[$0]!)" }.joined(separator: " · ")) }
                        ForEach(v.assumptions ?? [], id: \.self) { a in Text("• \(a)").font(.callout).fixedSize(horizontal: false, vertical: true) }
                        if let h = v.codeSha256 ?? v.sha256 { Field(label: "Code (SHA-256)", value: h, mono: true) }
                    }.padding(.top, 6)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).modeFramed(kind)
        .background(kind.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AgentStrategySection: View {
    let model: AppModel
    let d: AgentDetailStore
    let templates: AgentTemplates?

    private var versions: [StrategyVersion] {
        switch d.detail { case .spot(let s): s.versions; case .perp(let p): p.versions; default: d.overview?.backtests.versions ?? [] }
    }
    private var template: AgentTemplate? { templates?.templates.first { $0.id == (d.agent?.template ?? d.summary?.template) } }

    var body: some View {
        let kind = ModeKind(.research)
        Card("Stratégie en service") {
            if let s = d.summary?.strategy {
                Field(label: "Nom et version", value: "\(s.name) \(s.version)", emphasis: true)
                Field(label: "Nature", value: s.kind == "rule" ? "Règle intégrée au serveur" : "Code du laboratoire, épinglé par son empreinte")
                Field(label: "État", value: s.status)
                Field(label: "SHA-256", value: s.sha256, mono: true)
                if let p = s.path { Field(label: "Chemin", value: p, mono: true) }
            } else { Text(d.overview == nil ? "—" : "Aucune version de stratégie n’est rattachée à cet agent.").foregroundStyle(.secondary) }
            Text("Le serveur n’écrit jamais de code de stratégie : une version est choisie dans la bibliothèque du laboratoire, testée, puis approuvée par vous. Un mandat réel épingle l’empreinte de la version approuvée.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if let t = template, let verdicts = t.labVerdicts, !verdicts.isEmpty {
            Card("Rapport du laboratoire") { ForEach(Array(verdicts.enumerated()), id: \.offset) { _, v in LabVerdictView(verdict: v) } }
        }
        Card("Versions et backtests", trailing: AnyView(HStack { if let j = d.job, !j.status.isFinished { ProgressView().controlSize(.small); Text("Backtest \(j.status.rawValue)…").font(.caption).foregroundStyle(.secondary) } })) {
            BacktestLabel(note: d.overview?.backtests.note)
            if versions.isEmpty { Text("Aucune version rattachée. Choisissez-en une dans la bibliothèque ci-dessous : son backtest démarrera.").foregroundStyle(.secondary) }
            ForEach(versions) { v in versionBlock(v, kind) }
            if let r = d.overview?.backtests.recorded, !r.isNull {
                DisclosureGroup("Rejeu enregistré de la règle (simulation)") { JSONFacts(value: r, depth: 3).padding(.top, 6).modeFramed(kind) }
            }
            if let n = d.notice { Banner(.info, n) }
            if let e = d.actionError { Banner(.danger, e) }
        }
        if d.agent?.resolvedKind == .spot || d.agent?.resolvedKind == .perp {
            Card("Bibliothèque du laboratoire") {
                if let lib = d.library {
                    if lib.isEmpty { Text("La bibliothèque du serveur est vide.").foregroundStyle(.secondary) }
                    ForEach(lib) { s in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(s.meta.name) \(s.meta.version)").fontWeight(.medium)
                                Text("Marchés : \(s.generic == true ? "ceux de l’agent (\(s.minSymbols ?? 1) à \(s.maxSymbols.map(String.init) ?? "?"))" : s.meta.universe.joined(separator: ", ")) · pas \(s.meta.interval)\(s.meta.maxLeverage.map { " · levier ≤ ×\(AgentCreateForm.plain($0))" } ?? "")").font(.caption).foregroundStyle(.secondary)
                                Text(s.sha256).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
                                if let r = s.readme, !r.isEmpty { Text(r).font(.caption).lineLimit(4).foregroundStyle(.secondary).textSelection(.enabled) }
                            }
                            Spacer()
                            ModeButton(title: "Rattacher et tester", kind: kind) { Task { await d.register(s) } }.disabled(!model.canOperate || d.busy != nil || d.agent?.mode == .live)
                        }
                        Divider()
                    }
                    Text("Rattacher une version lance son backtest. Cela n’approuve rien et ne donne aucune autorité.").font(.caption).foregroundStyle(.secondary)
                } else { Unavailable(what: "Bibliothèque", error: d.error("library")) }
            }
            .task { await d.loadLibrary() }
        }
    }

    @ViewBuilder private func versionBlock(_ v: StrategyVersion, _ kind: ModeKind) -> some View {
        let current = v.id == d.agent?.strategyVersionId
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(v.name) \(v.version)").fontWeight(.semibold)
                Text(v.status).font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.secondary.opacity(0.15), in: Capsule())
                if current { Text("en service").font(.caption.weight(.medium)).foregroundStyle(Theme.positive) }
                Spacer()
                Text(Fmt.date(v.createdAt)).font(.caption).foregroundStyle(.secondary)
            }
            Text(v.sha256).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            if v.isApproved { Text("Approuvée\(v.approvedAt.map { " le \(Fmt.date($0))" } ?? "")\(v.approvedBy.map { " par \($0)" } ?? "") — pour le papier ; l’approbation ne promet aucun résultat.").font(.caption).foregroundStyle(.secondary) }
            if let n = v.notes, !n.isEmpty { Text(n).font(.caption).foregroundStyle(.secondary) }
            if let p = v.perpSummary {
                if let pb = p.problem { Banner(.danger, "Cette version ne peut pas être approuvée : \(pb)") }
                if p.buyAndHoldIsSpot == false { Text("Référence « acheter et conserver » : prix du perpétuel lui-même (aucune bougie au comptant fournie).").font(.caption).foregroundStyle(Theme.warning) }
                if let m = p.metrics {
                    ForEach(["train", "validation", "test"].filter { m[$0] != nil }, id: \.self) { split in
                        if let x = m[split] ?? nil {
                            Text(split == "train" ? "Entraînement" : split == "validation" ? "Validation" : "Test (hors échantillon)").font(.caption.weight(.semibold)).foregroundStyle(kind.color)
                            JSONFacts(value: x, depth: 2)
                        }
                    }
                }
                if let l = p.liquidations, !l.isEmpty { Field(label: "Liquidations simulées", value: l.keys.sorted().map { "\($0) : \(l[$0]!)" }.joined(separator: " · ")) }
                DisclosureGroup("Modèle d’exécution, robustesse, biais des données, contrôles") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array([("Modèle d’exécution", p.executionModel), ("Parité avec le moteur", p.engineParity), ("Robustesse", p.robustness), ("Biais des données", p.dataBias), ("Contrôles", p.checks), ("Références", p.benchmarks)].enumerated()), id: \.offset) { _, b in
                            if let j = b.1, !j.isNull { Text(b.0).font(.caption.weight(.semibold)); JSONFacts(value: j, depth: 3) }
                        }
                    }.padding(.top, 6)
                }
            } else if v.simulation.isEmpty {
                Text(v.hasReport == false || v.status == "backtesting" ? "Backtest en cours ou pas encore de rapport : aucun chiffre." : "Aucun rapport de backtest pour cette version.").font(.callout).foregroundStyle(.secondary)
            } else {
                if let l = v.simulation.lookaheadCheck { Label("Contrôle d’anticipation (look-ahead) : \(l)", systemImage: l == "pass" ? "checkmark.circle" : "xmark.octagon").font(.caption).foregroundStyle(l == "pass" ? Theme.positive : Theme.negative) }
                Text("Métriques (\(v.simulation.label))").font(.caption.weight(.semibold)).foregroundStyle(kind.color)
                JSONFacts(value: v.simulation.metrics, depth: 3, empty: "Aucune métrique dans le rapport.")
                DisclosureGroup("Robustesse, références, hypothèses et contrôles") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array([("Robustesse", v.simulation.robustness), ("Références", v.simulation.benchmarks), ("Hypothèses", v.simulation.config), ("Contrôles", v.simulation.checks)].enumerated()), id: \.offset) { _, b in
                            if let j = b.1 { Text(b.0).font(.caption.weight(.semibold)); JSONFacts(value: j, depth: 3) }
                        }
                    }.padding(.top, 6)
                }
            }
            HStack(spacing: 10) {
                ModeButton(title: "Relancer le backtest", kind: kind, systemImage: "arrow.clockwise") { Task { await d.backtest(versionId: v.id) } }
                if !v.isApproved {
                    Button("Approuver cette version pour le papier") { Task { await d.approveVersion(v) } }
                        .disabled(v.perpSummary?.problem != nil || (v.perpSummary == nil && v.simulation.lookaheadCheck != "pass") || d.agent?.mode == .live)
                        .help("Sans passkey : approuver une version ne donne aucune autorité sur des fonds. Le serveur refuse une version sans rapport ou dont le contrôle d’anticipation a échoué.")
                }
                Spacer(minLength: 0)
            }.disabled(!model.canOperate || d.busy != nil)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).modeFramed(kind)
        .background(kind.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
