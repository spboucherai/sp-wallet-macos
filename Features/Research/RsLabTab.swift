// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Research/RsLabTab.swift
// Description: The strategy laboratory's results as the server exposes them with its agent templates: out-of-sample backtests of strategies (per split, with the engine's stops and the gross-to-net breakdown), studies and their stated assumptions. Everything here is a simulation read from the lab's files — labelled as such on every block; a missing result file is shown as unavailable with its reason.
import SwiftUI
import SPWalletCore

@MainActor @Observable final class RsLabModel {
    let model: AppModel
    private(set) var templates: [AgentTemplate] = []
    private(set) var loadedAt: Date?
    private(set) var loading = false
    private(set) var error: String?

    init(model: AppModel) { self.model = model }

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do { templates = try await AgentsAPI(model.client).templates().templates; loadedAt = Date(); error = nil } catch { self.error = model.describe(error) }
    }
    var withVerdicts: [AgentTemplate] { templates.filter { !($0.labVerdicts ?? []).isEmpty } }
}

struct RsLabTab: View {
    let model: AppModel
    @State private var data: RsLabModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data {
                    HStack {
                        Text("Résultats du laboratoire de stratégies, lus par le serveur dans les fichiers du laboratoire.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        if data.loading { ProgressView().controlSize(.small) }
                        OpsAsOf(date: data.loadedAt, prefix: "Reçu")
                        Button { Task { await data.load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(data.loading)
                    }
                    Banner(.info, "Ce sont des BACKTESTS : ce qu’une stratégie aurait fait sur des données passées, sous le modèle d’exécution du laboratoire. Ce n’est ni un historique de performance, ni une prévision, ni un conseil. Un résultat hors échantillon favorable n’annonce pas un résultat futur.")
                    if let e = data.error {
                        if data.templates.isEmpty { Card { OpsUnavailable(what: "Résultats du laboratoire", reason: e) { Task { await data.load() } } } }
                        else { Banner(.warning, "Dernière lecture en échec (\(e)).") }
                    }
                    if data.loadedAt != nil && data.withVerdicts.isEmpty { EmptyState(symbol: "testtube.2", title: "Aucun résultat de laboratoire exposé", detail: "Le serveur ne joint de résultats de backtest à aucun de ses \(data.templates.count) modèles d’agents.") }
                    ForEach(data.withVerdicts) { t in RsLabTemplateCard(template: t) }
                } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
            }.padding(24).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if data == nil { let d = RsLabModel(model: model); data = d; await d.load() } }
    }
}

private struct RsLabTemplateCard: View {
    let template: AgentTemplate
    var body: some View {
        Card(template.name.text(locale: "fr"), trailing: AnyView(Text("\(template.family) · \(template.kind)").font(.caption).foregroundStyle(.secondary))) {
            Text(verbatim: template.summary.text(locale: "fr")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Array((template.labVerdicts ?? []).enumerated()), id: \.offset) { _, v in
                Divider()
                if !v.available { RsLabUnavailable(verdict: v) }
                else if v.kind == "strategy" { RsLabStrategy(verdict: v) }
                else { RsLabStudy(verdict: v) }
            }
        }
    }
}

private struct RsLabUnavailable: View {
    let verdict: LabVerdict
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProvenanceTag(p: .unavailable)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(verdict.kind == "study" ? "Étude" : verdict.kind == "policy" ? "Politique" : "Stratégie") « \(verdict.name) » : résultat indisponible").fontWeight(.medium)
                Text(verdict.reason ?? "Le serveur ne donne pas de raison.").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}

private struct RsLabStrategy: View {
    let verdict: LabVerdict
    private static let splits = ["train", "validation", "test"]

    var body: some View {
        let v = verdict
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(v.strategy ?? "\(v.name)@\(v.version ?? "?")").font(Theme.mono).fontWeight(.semibold)
                RsFlag(text: scope(v), color: v.scope == "agent" && v.liveCapable == true ? .orange : .secondary, symbol: "scope")
                Spacer()
                ProvenanceTag(p: .simulated, text: "Backtest · laboratoire")
            }
            if let s = v.symbols, !s.isEmpty { Text(s.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow { Text(""); ForEach(Self.splits, id: \.self) { Text(RsJobText.split($0)).font(.caption).foregroundStyle(.secondary) } }
                row("Rendement net") { OpsFmt.fraction($0.netReturn) }
                row("Sharpe net / brut") { "\(RsFmt.metric($0.netSharpe)) / \(RsFmt.metric($0.grossSharpe))" }
                row("Repli maximal") { $0.maxDrawdown.map { OpsFmt.fraction(-abs($0)) } ?? "—" }
                row("Transactions simulées") { $0.trades.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—" }
                row("Résultat net (brut → net)") { $0.grossToNet?.netPnl.map { OpsFmt.signedUsd($0) } ?? "—" }
                row("dont frais / glissement / financement") { s in
                    guard let g = s.grossToNet else { return "—" }
                    return "\(OpsFmt.usd(g.fees)) / \(OpsFmt.usd(g.slippage)) / \(OpsFmt.signedUsd(g.funding))"
                }
            }
            ForEach(v.stoppedSplits ?? [], id: \.self) { name in
                if let stop = v.splits?[name]??.stop {
                    Label("\(RsJobText.split(name)) : arrêté par la limite de perte du moteur (\(stop.reason))", systemImage: "stop.circle").font(.callout.weight(.medium)).foregroundStyle(Theme.negative)
                }
            }
            HStack(spacing: 8) {
                ProvenanceTag(p: .estimate, text: "Estimation statistique")
                Text("Sharpe déflaté \(RsFmt.metric(v.deflatedSharpe, digits: 3)) pour un seuil de \(RsFmt.metric(v.deflatedSharpeThreshold)) · \(v.trialsTested.map { "\(Int($0)) essais" } ?? "essais inconnus")\(v.testSharpeCi.flatMap { $0.count == 2 ? " · IC du Sharpe de test [\(RsFmt.metric($0[0])) ; \(RsFmt.metric($0[1]))]" : nil } ?? "")").font(.callout).monospacedDigit()
            }
            Text(v.significant == true ? "Selon la règle du laboratoire, le résultat hors échantillon dépasse son seuil. Cela reste un backtest." : v.significant == false ? "Selon la règle du laboratoire, le résultat hors échantillon NE dépasse PAS son seuil : rien ne le distingue du hasard des essais." : "Le laboratoire n’a pas tranché la significativité de ce résultat.")
                .font(.callout).foregroundStyle(v.significant == false ? Theme.warning : .secondary)
            if let w = v.window { Text("Fenêtre : \(w.start?.prefix(10) ?? "—") → \(w.end?.prefix(10) ?? "—") · barres de \(w.interval ?? "—")\(w.bars.map { " · \(Int($0)) barres" } ?? "")").font(.caption).foregroundStyle(.secondary) }
            if let c = v.checks, !c.isEmpty { Text("Contrôles : " + c.keys.sorted().map { "\($0) \(c[$0] ?? "")" }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            if v.engineParityApplied == false { Text("Les règles du moteur réel n’ont PAS été appliquées à ce backtest.").font(.caption).foregroundStyle(Theme.warning) }
            if v.installedHashMatches == false { Text("Le code installé sur le serveur ne correspond pas à celui qui a été testé.").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning) }
            if v.results?.matchesManifest == false { Text("Le fichier de résultats ne correspond pas au manifeste du laboratoire.").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning) }
            if let r = v.results { Text("Source : \(r.dir)/\(r.file ?? "summary.json")\(r.fileSha256.map { " · sha256 \($0.prefix(12))…" } ?? "")").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }

    private func scope(_ v: LabVerdict) -> String {
        switch v.scope {
        case "agent": v.liveCapable == true ? "Univers exécutable par un agent" : "Univers d’agent, papier seulement"
        case "backtest_only": "Backtest seulement"
        case "research_only": "Recherche seulement"
        case let s?: s
        case nil: "Portée non précisée"
        }
    }
    private func row(_ label: String, _ value: @escaping (LabVerdict.Split) -> String) -> some View {
        GridRow {
            Text(label)
            ForEach(Self.splits, id: \.self) { name in
                if let s = verdict.splits?[name] ?? nil { Text(value(s)).monospacedDigit() } else { Text("non fourni").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct RsLabStudy: View {
    let verdict: LabVerdict
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(verdict.name).font(Theme.mono).fontWeight(.semibold); Spacer(); ProvenanceTag(p: .simulated, text: verdict.fillsAreModelled == true ? "Étude · exécutions modélisées" : "Étude du laboratoire") }
            if let s = verdict.statement { Text(verbatim: s).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            else { Text("L’étude ne fournit pas d’énoncé.").font(.callout).foregroundStyle(.secondary) }
            Text("Énoncé de l’étude, repris tel quel de son fichier de résultats.").font(.caption).foregroundStyle(.secondary)
            if let a = verdict.assumptions, !a.isEmpty { Text("Hypothèses : " + a.joined(separator: " ; ")).font(.caption).foregroundStyle(.secondary) }
            if verdict.fillsAreModelled == true { Text("Les exécutions de cette étude sont MODÉLISÉES, pas observées.").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning) }
            if let r = verdict.results { Text("Source : \(r.dir)/\(r.file ?? "—")\(r.matchesManifest == false ? " — ne correspond pas au manifeste" : "")").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
