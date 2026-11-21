// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Research/RsJobDetailView.swift
// Description      : One research job: its real state, budgets and consumption,
//                    the live log, and its results kept apart by nature —
//                    observed data (how the candles were split, what the runner
//                    measured), the AI agent's own statements, the server's
//                    backtests, the statistical estimates, and the laboratory's
//                    simulated equity curve. A claimed number is always shown
//                    next to the measured one, never instead of it.
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

import Charts
import SwiftUI
import SPWalletCore

struct RsJobDetailView: View {
    let model: AppModel
    let data: RsJobsModel
    @State private var pane = "results"
    @State private var confirmCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let job = data.selectedJob {
                header(job)
                Divider()
                if pane == "log" { RsJobLogView(data: data).task(id: data.selectedId) { await data.followLog() } }
                else { results(job) }
            } else if let e = data.detailError { OpsUnavailable(what: "Recherche", reason: e) { Task { await data.loadDetail() } }.padding(20); Spacer() }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .confirmationDialog("Annuler cette recherche ?", isPresented: $confirmCancel) {
            Button("Demander l’annulation", role: .destructive) { Task { await data.cancel() } }
            Button("Ne pas annuler", role: .cancel) {}
        } message: { Text("Une recherche en file est annulée tout de suite. Une recherche en cours est arrêtée par l’exécuteur à son prochain rapport : elle reste « en cours » jusque-là. Les jetons déjà consommés ne sont pas rendus.") }
    }

    private func header(_ job: ResearchJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RsJobStateDot(state: job.state).padding(.top, 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RsJobText.state(job.state)).font(.title3.weight(.semibold))
                    Text(RsJobText.stateNote(job.state)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let r = job.reason { Text("Motif donné par le serveur : \(r)").font(.callout).foregroundStyle(job.state == .submitted ? Color.secondary : Theme.negative).textSelection(.enabled) }
                    if job.cancelRequested && !job.state.isFinal { Text("Annulation demandée — l’exécuteur ne l’a pas encore appliquée.").font(.callout).foregroundStyle(Theme.warning) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Annuler la recherche…", role: .destructive) { confirmCancel = true }
                        .disabled(!job.state.isCancellable || job.cancelRequested || data.cancelling || !model.canOperate)
                        .help(job.state.isCancellable ? "" : "Le serveur n’accepte l’annulation que d’une recherche en file, en préparation ou en cours.")
                    OpsAsOf(date: data.detailAt, prefix: "Reçu")
                }
            }
            if let e = data.actionError { Banner(.danger, e) }
            if let e = data.detailError, data.detail != nil { Banner(.warning, "Dernière lecture en échec (\(e)).") }
            Picker("Vue", selection: $pane) { Text("Résultats").tag("results"); Text("Journal en direct").tag("log") }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
        }.padding(16)
    }

    private func results(_ job: ResearchJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Banner(.info, "Tout ce qui suit est de la recherche : des backtests (simulations sur des données passées) et une analyse générée par IA. Ce ne sont ni des résultats de trading, ni une prévision, ni un conseil. Le capital indiqué est virtuel.")
                RsJobRequestCard(job: job, agent: data.detail?.agent)
                if let d = data.detail {
                    if d.dataReady == false || d.dataError != nil { Banner(.danger, "Jeu de données indisponible\(d.dataError.map { " : \($0)" } ?? ".")") }
                    else if d.dataReady == nil && !job.state.isFinal { Text("Le jeu de données est en cours de gel sur le serveur.").font(.callout).foregroundStyle(.secondary) }
                    if let h = d.holdout { RsHoldoutCard(holdout: h) }
                    if let u = job.usage { RsUsageCard(usage: u, budgets: job.budgets) }
                    if let s = d.server { RsServerReportCard(report: s) }
                    if let s = d.submission { RsSubmissionCard(submission: s) }
                    if let r = d.report { RsLabReportCard(report: r) }
                    if let v = d.version { RsVersionCard(version: v, agent: d.agent) }
                    if d.results.isEmpty && job.state.isFinal { Text("Cette recherche n’a produit aucun résultat.").foregroundStyle(.secondary) }
                    else if d.server == nil && d.submission == nil && !job.state.isFinal { Text("Aucun résultat pour l’instant : ils apparaîtront quand l’agent aura soumis une stratégie et que le serveur l’aura évaluée.").foregroundStyle(.secondary) }
                } else if data.detailError == nil { ProgressView().controlSize(.small) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Blocks

private struct RsJobRequestCard: View {
    let job: ResearchJob
    let agent: ResearchJobDetail.Agent?
    var body: some View {
        Card("Demande") {
            Text(verbatim: job.mission).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Field(label: "Marché", value: "\(job.kind == "perp" ? "Perpétuels" : job.kind == "spot" ? "Comptant" : job.kind) · \(job.universe.joined(separator: ", ")) · barres de \(job.interval)")
            Field(label: "Capital virtuel", value: OpsFmt.usd(job.capitalUsd) + " — simulation, pas des fonds")
            Field(label: "Destination", value: agent.map { "Agent « \($0.name) » (\($0.state))" } ?? (job.agentId == nil ? "Bibliothèque (brouillon sans agent)" : "Agent \(job.agentId ?? "")"))
            Field(label: "Plafonds fixés", value: "\(job.budgets.wallSeconds / 60) min · \(job.budgets.maxTrials) essais · \(job.budgets.maxDiskMb) Mo · \(job.budgets.maxModelTokens.formatted()) jetons · \(OpsFmt.usd(job.budgets.maxModelUsd)) de modèle")
            Field(label: "Outils de l’agent", value: job.tools.joined(separator: ", "))
            Field(label: "Stratégie visée", value: job.strategy, mono: true)
            Field(label: "Créée / terminée", value: "\(Fmt.date(job.createdAt)) / \(job.finishedAt.map { Fmt.date($0) } ?? "pas terminée")")
            Field(label: "Exécuteur", value: job.runnerId.map { "\($0) · pris en charge \(Fmt.relative(job.claimedAt)) · dernier signe de vie \(Fmt.relative(job.heartbeatAt))" } ?? "aucun pour l’instant")
            Field(label: "Laboratoire", value: job.labCommit.map { "commit \($0)" } ?? "version non épinglée", mono: job.labCommit != nil)
        }
    }
}

private struct RsHoldoutCard: View {
    let holdout: ResearchHoldout
    var body: some View {
        Card {
            RsBlockHeader(title: "Découpage des données", provenance: ResearchHoldout.provenance)
            Text("Chandeliers enregistrés, gelés pour cette recherche. L’agent n’a vu que la période de développement ; le serveur garde la période de test pour sa propre évaluation.").font(.callout).foregroundStyle(.secondary)
            Field(label: "Développement (vu par l’agent)", value: "\(day(holdout.start)) → \(day(holdout.devEnd)) · \(holdout.devBars.formatted()) barres")
            Field(label: "Test (jamais vu par l’agent)", value: "\(day(holdout.devEnd)) → \(day(holdout.end)) · \(holdout.testBars.formatted()) barres")
        }
    }
    private func day(_ s: String) -> String { ISO8601.parse(s).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? s }
}

private struct RsUsageCard: View {
    let usage: ResearchUsage
    let budgets: ResearchBudgets
    var body: some View {
        Card {
            RsBlockHeader(title: "Consommation mesurée", provenance: ResearchUsage.provenance)
            Text("Mesuré par l’exécuteur depuis l’extérieur du processus de l’agent ; enregistré par le serveur, qui ne s’en sert pour aucune décision d’argent.").font(.callout).foregroundStyle(.secondary)
            Field(label: "Durée", value: "\(OpsFmt.duration(ms: Double(usage.wallMs))) sur \(budgets.wallSeconds / 60) min autorisées")
            Field(label: "Essais", value: "\(usage.trials) sur \(budgets.maxTrials)")
            Field(label: "Disque", value: "\(OpsFmt.number(usage.diskMb, digits: 1)) Mo sur \(budgets.maxDiskMb)")
            Field(label: "Jetons du modèle", value: "\(usage.modelTokens.formatted()) sur \(budgets.maxModelTokens.formatted())\(usage.modelRequests.map { " · \($0) requêtes" } ?? "")")
            Field(label: "Coût du modèle", value: usage.modelUsd.map { "\(OpsFmt.usd($0)) sur \(OpsFmt.usd(budgets.maxModelUsd)) (déclaré par l’outil de l’agent)" } ?? "Non déclaré par l’outil de l’agent — inconnu, pas zéro")
            Field(label: "Confinement de l’agent", value: usage.sandbox == "sandbox-exec" ? "Confiné (sandbox-exec)" : usage.sandbox == "none" ? "AUCUN : la plateforme de l’exécuteur n’offrait pas de bac à sable" : usage.sandbox, emphasis: usage.sandbox == "none")
            if usage.ledgerTampered { Banner(.danger, "Le registre d’essais de l’agent a été tronqué ou réécrit pendant sa copie : le nombre d’essais ci-dessus n’est pas fiable, et les statistiques qui en dépendent non plus.") }
            Field(label: "Fin du processus", value: "\(usage.agent ?? "agent") · code \(usage.exitCode.map(String.init) ?? "—")\(usage.signal.map { " · signal \($0)" } ?? "")")
        }
    }
}

private struct RsServerReportCard: View {
    let report: ResearchServerReport
    var body: some View {
        let r = report
        Card {
            RsBlockHeader(title: "Backtests rejoués par le serveur", provenance: ResearchServerReport.provenance)
            Text("Le serveur a exécuté lui-même la stratégie sur ses propres données. Ce sont des simulations : ce que la stratégie AURAIT fait sur des données passées, sous le modèle d’exécution du laboratoire — pas un résultat de trading.").font(.callout).foregroundStyle(.secondary)
            if r.isOK { Label("Évaluation du serveur terminée", systemImage: "checkmark.circle").foregroundStyle(Theme.positive) }
            else { Banner(.danger, "L’évaluation du serveur a échoué\(r.reason.map { " : \($0)" } ?? "."). Sans elle, la stratégie ne peut pas être approuvée.") }
            if let h = r.holdout { Field(label: "Période de test", value: "\(h.testStart.prefix(10)) → \(h.testEnd.prefix(10)) · \(h.bars.formatted()) barres") }
            if let m = r.metrics {
                RsMetricsGrid(columns: [("Entraînement", m.train), ("Validation", m.validation), ("Test (hors échantillon)", m.test), ("Référence passive, même test", r.benchmark)])
                Text("Référence passive : achat-conservation (comptant) ou long 1× (perpétuels) sur la même période de test.").font(.caption).foregroundStyle(.secondary)
            }
            if let t = r.trials {
                Field(label: "Essais comptés", value: "\(t.total) (\(t.job) par la recherche, \(t.server) par le serveur)")
                if t.ledgerTampered { Banner(.danger, "Registre d’essais altéré : le nombre d’essais, donc le Sharpe corrigé, ne sont pas fiables.") }
            }
            if let checks = r.checks, !checks.isEmpty { Field(label: "Contrôles du laboratoire", value: checks.keys.sorted().map { "\($0) : \(checks[$0]?.displayText ?? "—")" }.joined(separator: " · ")) }
            if let s = r.sandbox { Field(label: "Confinement côté serveur", value: s == "sandbox-exec" ? "Confiné (sandbox-exec)" : s == "none" ? "AUCUN" : s, emphasis: s == "none") }
            if let sha = r.sha256 { Field(label: "SHA-256 de strategy.py", value: sha, mono: true) }

            if r.deflatedSharpe != nil || r.sharpeCi != nil {
                Divider()
                RsBlockHeader(title: "Estimations statistiques", provenance: ResearchServerReport.estimateProvenance)
                Field(label: "Sharpe corrigé des essais (déflaté)", value: RsFmt.metric(r.deflatedSharpe, digits: 3))
                if let ci = r.sharpeCi, ci.count == 2 { Field(label: "Intervalle de confiance du Sharpe (bootstrap)", value: "[\(RsFmt.metric(ci[0])) ; \(RsFmt.metric(ci[1]))]") }
                Text("Statistiques calculées sur l’ensemble des essais et sur des rééchantillonnages : elles ont une incertitude et ne prédisent rien.").font(.caption).foregroundStyle(.secondary)
            }

            if let cmp = r.comparison, !cmp.isEmpty {
                Divider()
                HStack { Text("Affirmations de l’agent face aux mesures du serveur").font(.headline); Spacer(); ProvenanceTag(p: .ai, text: "Affirmé · agent IA"); ProvenanceTag(p: .simulated, text: "Mesuré · serveur") }
                if r.claimsDiffer == true { Banner(.warning, "Les chiffres annoncés par l’agent diffèrent de ceux que le serveur a recalculés sur les mêmes données. Seuls ceux du serveur comptent.") }
                if let p = r.claimsProblem { Text("Affirmations ignorées : \(p)").font(.callout).foregroundStyle(Theme.warning) }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text("Période"); Text("Mesure"); Text("Affirmé par l’agent"); Text("Mesuré par le serveur"); Text("") }.font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(cmp.enumerated()), id: \.offset) { _, c in
                        GridRow {
                            Text(RsJobText.split(c.split)); Text(RsJobText.metric(c.metric))
                            Text(RsMetricsGrid.value(c.metric, c.claimed)).monospacedDigit().foregroundStyle(.secondary)
                            Text(RsMetricsGrid.value(c.metric, c.measured)).monospacedDigit()
                            if c.differs { Label("Diffère", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning) } else { Text("") }
                        }
                    }
                }
            }
            if let rep = r.replication {
                DisclosureGroup("Réplication par le serveur sur les données que l’agent avait") {
                    RsMetricsGrid(columns: [("Entraînement", rep.train), ("Validation", rep.validation), ("Test interne de l’agent", rep.innerTest)]).padding(.top, 4)
                }
            }
        }
    }
}

/// Split metrics side by side. Each cell is the number as measured, or "—" where the laboratory gave none.
struct RsMetricsGrid: View {
    let columns: [(String, ResearchSplitMetrics?)]
    static func value(_ metric: String, _ v: Double?) -> String {
        guard let v else { return "—" }
        switch metric {
        case "total_return", "max_drawdown": return OpsFmt.fraction(v)
        case "trades": return v.formatted(.number.precision(.fractionLength(0)))
        default: return RsFmt.metric(v)
        }
    }
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
            GridRow { Text(""); ForEach(Array(columns.enumerated()), id: \.offset) { _, c in Text(c.0).font(.caption).foregroundStyle(.secondary) } }
            row("total_return") { $0.totalReturn }
            row("sharpe") { $0.sharpe }
            row("max_drawdown") { $0.maxDrawdown }
            row("trades") { $0.trades }
        }
    }
    private func row(_ metric: String, _ get: @escaping (ResearchSplitMetrics) -> Double?) -> some View {
        GridRow {
            Text(RsJobText.metric(metric))
            ForEach(Array(columns.enumerated()), id: \.offset) { _, c in Text(c.1 == nil ? "non fourni" : Self.value(metric, c.1.flatMap(get))).monospacedDigit().foregroundStyle(c.1 == nil ? .secondary : .primary) }
        }
    }
}

private struct RsSubmissionCard: View {
    let submission: ResearchSubmission
    @State private var file = ""

    var body: some View {
        let names = submission.files.keys.sorted { a, b in rank(a) == rank(b) ? a < b : rank(a) < rank(b) }
        Card {
            RsBlockHeader(title: "Ce que l’agent IA a rendu", provenance: ResearchSubmission.provenance)
            Banner(.warning, "Texte et chiffres écrits par l’agent IA : des affirmations non vérifiées, pas des mesures. Le texte est affiché tel quel, sans images, et aucun lien n’y est suivi.")
            if let c = submission.claims {
                if let s = c.summary, !s.isEmpty {
                    Text("Résumé de l’agent").font(.subheadline.weight(.semibold))
                    Text(verbatim: s).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                RsMetricsGrid(columns: [("Entraînement (affirmé)", c.train), ("Validation (affirmé)", c.validation), ("Test interne de l’agent (affirmé)", c.innerTest)])
                Text("Le « test interne » de l’agent n’est pas la période de test du serveur, qu’il n’a jamais vue.\(c.trials.map { " Essais déclarés par l’agent : \($0)." } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            if let p = submission.claimsProblem { Text("Affirmations ignorées par le serveur : \(p)").font(.callout).foregroundStyle(Theme.warning) }
            Field(label: "SHA-256 de strategy.py", value: submission.sha256, mono: true)
            if let p = submission.path { Field(label: "Installée sous", value: p, mono: true) }
            if !names.isEmpty {
                Divider()
                Picker("Fichier", selection: $file) { ForEach(names, id: \.self) { n in Text("\(n)\(submission.bytes?[n].map { " (\(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)))" } ?? "")").tag(n) } }.pickerStyle(.segmented).labelsHidden()
                let shown = names.contains(file) ? file : names[0]
                if let text = submission.files[shown] {
                    if shown.lowercased().hasSuffix(".md") { RsPlainDocumentView(text) }
                    else {
                        Text("Code source écrit par l’agent — affiché, jamais exécuté par cette app.").font(.caption).foregroundStyle(.secondary)
                        ScrollView(.horizontal) { Text(verbatim: text.count > RsPlainDocument.maxCharacters ? String(text.prefix(RsPlainDocument.maxCharacters)) + "\n… (tronqué pour l’affichage)" : text).font(Theme.monoSmall).textSelection(.enabled).padding(8) }
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
    private func rank(_ name: String) -> Int { name == "README.md" ? 0 : name == "NOTES.md" ? 1 : name == "strategy.py" ? 2 : 3 }
}

private struct RsLabReportCard: View {
    let report: ResearchLabReport
    private struct EquityPoint: Identifiable { let date: Date; let value: Double; var id: Date { date } }
    private struct Section: Identifiable { let title: String; let value: JSONValue; var id: String { title } }

    private var equity: [EquityPoint] {
        (report.equityCurve?.arrayValue ?? []).compactMap { p in
            guard let t = p[0]?.doubleValue ?? p["ts"]?.doubleValue, let v = p[1]?.doubleValue ?? p["equity"]?.doubleValue, t > 0, v.isFinite else { return nil }
            return EquityPoint(date: Date(timeIntervalSince1970: t > 1e11 ? t / 1000 : t), value: v)
        }
    }
    private var sections: [Section] {
        [("Périodes", report.splits), ("Configuration", report.config), ("Mesures", report.metrics), ("Références", report.benchmarks), ("Robustesse", report.robustness),
         ("Contrôles", report.checks), ("Recherche", report.researchJob)].compactMap { t, v in v.flatMap { $0.isNull ? nil : Section(title: t, value: $0) } }
    }

    var body: some View {
        let curve = equity
        Card {
            RsBlockHeader(title: "Rapport complet du laboratoire", provenance: ResearchLabReport.provenance)
            Text("Le rapport de backtest tel que le serveur l’a enregistré, sur le jeu de données gelé. Données affichées telles que servies.").font(.callout).foregroundStyle(.secondary)
            if curve.count > 1 {
                HStack { Text("Valeur SIMULÉE du backtest").font(.subheadline.weight(.semibold)); ProvenanceTag(p: .simulated, text: "Simulation — pas l’historique d’un compte") }
                Chart(curve) { p in LineMark(x: .value("Date", p.date), y: .value("Valeur simulée", p.value)).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.3, dash: [5, 3])) }
                    .chartYScale(domain: .automatic(includesZero: false)).frame(height: 200)
                    .accessibilityLabel("Courbe de valeur simulée du backtest, \(curve.count) points")
            } else if report.equityCurve != nil { Text("Courbe de valeur simulée : format non reconnu par cette version, non tracée.").font(.caption).foregroundStyle(.secondary) }
            ForEach(sections) { s in
                DisclosureGroup(s.title) { RsJSONOutline(s.value).padding(.top, 4).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
}

private struct RsVersionCard: View {
    let version: ResearchJobDetail.Version
    let agent: ResearchJobDetail.Agent?
    var body: some View {
        Card("Version de stratégie laissée en brouillon") {
            Field(label: "Identifiant", value: version.id, mono: true)
            Field(label: "État", value: version.approvedAt.map { "\(version.status) — approuvée le \(Fmt.date($0))" } ?? version.status)
            if let n = version.notes, !n.isEmpty { Field(label: "Notes", value: n) }
            Text("Cette recherche n’active rien. Utiliser cette stratégie demande une approbation explicite avec votre passkey dans « Agents de trading »\(agent.map { " (agent « \($0.name) »)" } ?? "") ; cet écran ne l’offre pas.").font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Live log

struct RsJobLogView: View {
    let data: RsJobsModel
    @State private var follow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                let (text, color): (String, Color) = switch data.logLive {
                case .idle: ("En pause", .secondary)
                case .connecting: ("Connexion au flux…", Theme.warning)
                case .streaming: ("En direct", Theme.positive)
                case .reconnecting: ("Reconnexion…", Theme.warning)
                case .ended: ("Journal complet — la recherche est terminée", .secondary)
                }
                Label(text, systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(color)
                    .help({ if case .reconnecting(let why) = data.logLive { return why }; return "" }())
                Text("\(data.logLines.count) lignes\(data.logTruncated ? " (les plus anciennes ne sont plus affichées)" : "")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Suivre la fin", isOn: $follow).toggleStyle(.checkbox)
                Button("Copier") { copyToPasteboard(data.logLines.map { "\(ISO8601.string($0.ts)) [\($0.stream)] \($0.text)" }.joined(separator: "\n")) }.disabled(data.logLines.isEmpty)
            }.padding(.horizontal, 16).padding(.vertical, 8)
            Text("Les lignes « agent » sont la sortie du processus de l’agent IA : du texte non fiable, affiché tel quel. Seules les lignes « serveur » sont les mots de ce portefeuille.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
            Divider()
            ScrollViewReader { proxy in
                List(data.logLines) { l in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(l.ts.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary)
                        Text(RsJobText.stream(l.stream)).foregroundStyle(l.isServerLine ? Theme.positive : l.stream == "err" ? Theme.negative : l.stream == "sys" ? .blue : .secondary).frame(width: 96, alignment: .leading)
                        Text(verbatim: l.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }.font(Theme.monoSmall).listRowSeparator(.hidden).id(l.id)
                }
                .listStyle(.plain)
                .onChange(of: data.logLines.last?.id) { if follow, let last = data.logLines.last?.id { proxy.scrollTo(last, anchor: .bottom) } }
                .overlay { if data.logLines.isEmpty { Text(data.logLive == .ended ? "Aucune ligne de journal." : "En attente des premières lignes…").foregroundStyle(.secondary) } }
            }
        }
    }
}
