// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Research/RsJobCreateSheet.swift
// Description      : Creation of an automated research job, within the server's
//                    schema: mission, universe, kind, interval, virtual
//                    capital, the tools the AI agent may use, and the budgets
//                    (time, trials, disk, model tokens, model cost) the runner
//                    enforces from outside the agent. The sheet shows exactly
//                    what will be sent, what it can cost and what the result
//                    will be — AI-generated analysis and backtests, never
//                    advice — before an explicit button sends it.
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

@MainActor @Observable final class RsJobCreateForm {
    static let allTools = ["Read", "Write", "Edit", "Glob", "Grep", "Bash"]

    var agentId = ""
    var kind = "spot"
    var mission = ""
    var universe = ""
    var interval = "1h"
    var capital = "1000"
    var wallMinutes = "60"
    var maxTrials = "200"
    var maxDiskMb = "512"
    var maxModelTokens = "5000000"
    var maxModelUsd = "10"
    var tools = Set(allTools)

    private(set) var agents: [Agent] = []
    private(set) var agentsError: String?
    var sending = false
    var error: String?
    var acknowledged = false

    var agent: Agent? { agents.first { $0.id == agentId } }
    var symbols: [String] {
        universe.uppercased().split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" || $0 == "\n" }).map(String.init)
    }
    private func int(_ s: String) -> Int? { Int(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{202F}", with: "").replacingOccurrences(of: " ", with: "")) }
    private func dbl(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    /// The bounds of packages/core/src/research-job.ts (ResearchJobCreate, ResearchBudgets), checked before sending so that a refusal is explained here.
    var problems: [String] {
        var out: [String] = []
        let m = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.count < 10 || m.count > 2000 { out.append("La mission doit compter de 10 à 2 000 caractères (\(m.count) actuellement).") }
        if agent == nil {
            let s = symbols
            if s.isEmpty || s.count > 12 { out.append("L’univers doit compter de 1 à 12 symboles.") }
            if Set(s).count != s.count { out.append("Les symboles doivent être distincts.") }
            if let bad = s.first(where: { $0.wholeMatch(of: /[A-Z0-9]{2,10}/) == nil }) { out.append("Symbole invalide : « \(bad) » (2 à 10 lettres ou chiffres).") }
            if kind == "perp" && s.count > 8 { out.append("Au plus 8 perpétuels.") }
            if kind == "spot" && !["1h", "1d"].contains(interval) { out.append("Une recherche au comptant se fait en 1 h ou 1 j.") }
            if kind == "perp" && !["1h", "4h"].contains(interval) { out.append("Une recherche sur perpétuels se fait en 1 h ou 4 h.") }
        }
        if let a = agent, agentUniverse(a).isEmpty { out.append("L’univers de cet agent ne contient aucun symbole transmissible dans une demande de recherche : choisissez la bibliothèque.") }
        if let c = dbl(capital), (10...10_000_000).contains(c) {} else { out.append("Capital virtuel entre 10 et 10 000 000 USD.") }
        if let w = int(wallMinutes), (1...1440).contains(w) {} else { out.append("Durée maximale entre 1 et 1 440 minutes.") }
        if let t = int(maxTrials), (1...5000).contains(t) {} else { out.append("Essais entre 1 et 5 000.") }
        if let d = int(maxDiskMb), (16...10_240).contains(d) {} else { out.append("Disque entre 16 et 10 240 Mo.") }
        if let k = int(maxModelTokens), (10_000...500_000_000).contains(k) {} else { out.append("Jetons du modèle entre 10 000 et 500 000 000.") }
        if let u = dbl(maxModelUsd), (0.05...1000).contains(u) {} else { out.append("Coût du modèle entre 0,05 et 1 000 USD.") }
        if tools.isEmpty { out.append("Au moins un outil.") }
        return out
    }

    /// The agent's own symbols, as the request must carry them (the schema wants 1 to 12 distinct tickers even though the server then uses the agent's).
    private func agentUniverse(_ a: Agent) -> [String] {
        var seen = Set<String>()
        return Array(a.universe.map { $0.uppercased() }.filter { $0.wholeMatch(of: /[A-Z0-9]{2,10}/) != nil && seen.insert($0).inserted }.prefix(12))
    }

    var request: ResearchJobRequest? {
        guard problems.isEmpty, let c = dbl(capital), let w = int(wallMinutes), let t = int(maxTrials), let d = int(maxDiskMb), let k = int(maxModelTokens), let u = dbl(maxModelUsd) else { return nil }
        let budgets = ResearchJobRequest.Budgets(wallSeconds: w * 60, maxTrials: t, maxDiskMb: d, maxModelTokens: k, maxModelUsd: u)
        let orderedTools = Self.allTools.filter(tools.contains)
        // with an agent, the server replaces kind, universe and interval by the agent's own; its universe is sent as shown
        if let a = agent {
            return ResearchJobRequest(mission: mission.trimmingCharacters(in: .whitespacesAndNewlines), universe: agentUniverse(a), agentId: a.id, capitalUsd: c, budgets: budgets, tools: orderedTools)
        }
        return ResearchJobRequest(mission: mission.trimmingCharacters(in: .whitespacesAndNewlines), universe: symbols, kind: kind, interval: interval, capitalUsd: c, budgets: budgets, tools: orderedTools)
    }

    func loadAgents(_ model: AppModel) async {
        do { agents = try await AgentsAPI(model.client).list(); agentsError = nil } catch { agentsError = model.describe(error) }
    }
}

struct RsJobCreateSheet: View {
    let model: AppModel
    let jobs: RsJobsModel
    let dismiss: () -> Void
    @State private var form = RsJobCreateForm()

    var body: some View {
        @Bindable var form = form
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Nouvelle recherche automatisée").font(.title2.weight(.semibold)); Spacer(); ProvenanceTag(p: .ai, text: "Résultat : analyse IA + backtests") }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Banner(.info, "Un agent de programmation IA, sur une autre machine, développe une stratégie selon votre mission, dans les limites ci-dessous. Ce qu’il rend est une analyse générée par IA et des backtests (simulations sur données passées) : ni un conseil, ni une promesse de résultat. Le serveur rejoue ensuite la stratégie lui-même sur une période que l’agent n’a jamais vue. Rien n’est négocié, et aucune stratégie n’est activée sans votre approbation par passkey, ailleurs.")
                    if let s = jobs.status, !s.runnerConfigured {
                        Banner(.warning, "Aucun exécuteur n’est configuré sur le serveur\(jobs.runnerCapability.map { " (\($0.why))" } ?? "") : la recherche sera créée mais restera en file d’attente.")
                    }
                    Form {
                        Picker("Destination", selection: $form.agentId) {
                            Text("Bibliothèque (brouillon sans agent)").tag("")
                            ForEach(form.agents) { a in Text("Agent « \(a.name) » — \(a.universe.joined(separator: ", ")) · \(a.interval)").tag(a.id) }
                        }
                        if let e = form.agentsError { LabeledContent("") { Text("Liste des agents indisponible (\(e)) : seule la bibliothèque est proposée.").font(.caption).foregroundStyle(Theme.warning) } }
                        if let a = form.agent {
                            LabeledContent("Univers et intervalle") { Text("Ceux de l’agent, imposés par le serveur : \(a.universe.joined(separator: ", ")) · \(a.interval)").foregroundStyle(.secondary) }
                        } else {
                            Picker("Type de marché", selection: $form.kind) { Text("Comptant").tag("spot"); Text("Perpétuels").tag("perp") }.pickerStyle(.segmented)
                            TextField("Univers", text: $form.universe, prompt: Text("BTC, ETH (1 à 12 symboles)"))
                            Picker("Intervalle des barres", selection: $form.interval) { ForEach(form.kind == "perp" ? ["1h", "4h"] : ["1h", "1d"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                                .onChange(of: form.kind) { if !(form.kind == "perp" ? ["1h", "4h"] : ["1h", "1d"]).contains(form.interval) { form.interval = "1h" } }
                        }
                        TextField("Mission (vos mots, transmis tels quels à l’agent)", text: $form.mission, prompt: Text("Ex. : chercher une stratégie de suivi de tendance robuste aux frais, sans effet de levier"), axis: .vertical).lineLimit(4...8)
                        TextField("Capital VIRTUEL de la simulation (USD)", text: $form.capital)
                        LabeledContent("") { Text("Ce capital n’est pas des fonds : c’est le point de départ des backtests.").font(.caption).foregroundStyle(.secondary) }
                    }.formStyle(.grouped).scrollDisabled(true)

                    Card("Budgets — plafonds appliqués par l’exécuteur, de l’extérieur de l’agent") {
                        Text("La recherche consomme des jetons du modèle d’IA facturés à votre compte de modèle, jusqu’aux plafonds ci-dessous. Elle s’arrête (« budget dépassé ») dès qu’un plafond est atteint.").font(.callout).foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            budgetRow("Durée maximale", $form.wallMinutes, "minutes (1 à 1 440)")
                            budgetRow("Essais de backtest", $form.maxTrials, "essais (1 à 5 000)")
                            budgetRow("Disque du dossier de travail", $form.maxDiskMb, "Mo (16 à 10 240)")
                            budgetRow("Jetons du modèle", $form.maxModelTokens, "jetons, entrée + sortie + cache (10 000 à 500 M)")
                            budgetRow("Coût du modèle", $form.maxModelUsd, "USD déclarés par l’outil de l’agent (0,05 à 1 000)")
                        }
                        Divider()
                        Text("Outils autorisés à l’agent (aucun outil web n’existe : l’agent n’a pas accès à Internet par ses outils)").font(.callout)
                        HStack(spacing: 14) {
                            ForEach(RsJobCreateForm.allTools, id: \.self) { t in
                                Toggle(t, isOn: Binding(get: { form.tools.contains(t) }, set: { if $0 { form.tools.insert(t) } else { form.tools.remove(t) } })).toggleStyle(.checkbox)
                            }
                        }
                    }
                    if let s = jobs.status { Text("Recherches ouvertes : \(s.openJobs) sur \(s.maxOpenJobs) au plus.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(form.problems, id: \.self) { Label($0, systemImage: "xmark.circle").font(.callout).foregroundStyle(Theme.negative) }
                    if let r = form.request { review(r) }
                }.padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = form.error { Banner(.danger, e) }
                Toggle("J’ai compris : ceci lance une dépense de jetons d’IA plafonnée aux budgets affichés, et le résultat est une analyse générée par IA, pas un conseil.", isOn: $form.acknowledged).toggleStyle(.checkbox)
                HStack {
                    Button("Annuler") { dismiss() }.disabled(form.sending)
                    Spacer()
                    if form.sending { ProgressView().controlSize(.small) }
                    Button("Lancer la recherche") { Task { await send() } }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(form.request == nil || !form.acknowledged || form.sending || !jobs.canCreate)
                }
                if !jobs.canCreate { Text(model.canOperate ? "Le nombre maximal de recherches ouvertes est atteint, ou l’état du service de recherche est inconnu." : "Indisponible hors ligne ou sans session.").font(.caption).foregroundStyle(Theme.warning) }
            }.padding(16)
        }
        .frame(width: 760, height: 820)
        .task { await form.loadAgents(model) }
    }

    private func budgetRow(_ label: String, _ text: Binding<String>, _ unit: String) -> some View {
        GridRow {
            Text(label)
            TextField("", text: text).frame(width: 110).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func review(_ r: ResearchJobRequest) -> some View {
        Card("Ce qui sera envoyé au serveur") {
            Field(label: "Destination", value: form.agent.map { "Agent « \($0.name) » (le serveur impose son univers et son intervalle)" } ?? "Bibliothèque (brouillon)")
            if form.agent == nil {
                Field(label: "Marché", value: "\(r.kind == "perp" ? "Perpétuels" : "Comptant") · \(r.universe.joined(separator: ", ")) · barres de \(r.interval ?? "—")")
            }
            Field(label: "Mission", value: r.mission)
            Field(label: "Capital virtuel", value: OpsFmt.usd(r.capitalUsd) + " (simulation)")
            if let b = r.budgets {
                Field(label: "Plafonds", value: "\((b.wallSeconds ?? 0) / 60) min · \(b.maxTrials ?? 0) essais · \(b.maxDiskMb ?? 0) Mo · \((b.maxModelTokens ?? 0).formatted()) jetons · \(OpsFmt.usd(b.maxModelUsd)) de modèle", emphasis: true)
            }
            Field(label: "Outils", value: (r.tools ?? []).joined(separator: ", "))
        }
    }

    private func send() async {
        guard let r = form.request, !form.sending else { return }
        form.sending = true; form.error = nil
        let failure = await jobs.create(r)
        form.sending = false
        if let failure { form.error = failure } else { dismiss() }
    }
}
