// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/AgentCreateSheet.swift
// Description      : Creating an agent — from a server template, as a spot
//                    agent with a vault, or as a perp agent in simulation.
//                    Creation signs nothing and gives no authority. Every limit
//                    is stated by the owner and bounded: an empty, zero,
//                    non-finite or out-of-range limit is refused here before
//                    the server sees it, and leverage is never pre-set to a
//                    maximum.
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

@MainActor @Observable final class AgentCreateForm {
    enum Kind: String, CaseIterable { case template = "Depuis un modèle", spot = "Comptant (coffre)", perp = "Perpétuels (simulation)" }
    let model: AppModel
    let api: AgentsAPI
    var kind: Kind = .template
    var name = ""
    var mission = ""
    var capital = ""
    private(set) var busy = false
    var error: String?
    private(set) var warnings: [AgentWarning] = []
    private(set) var createdId: String?

    // template
    var templateId = "" { didSet { if oldValue != templateId { applyTemplate() } } }
    var universeText = ""
    var venuesText = ""
    var strategyPath = ""
    var riskText: [String: String] = [:]

    // spot
    private(set) var networks: AgentNetworks?
    private(set) var networksError: String?
    var network = "" { didSet { if oldValue != network { symbols = []; assets = [:]; cash = spotNetwork?.defaultCash ?? spotNetwork?.cash.first?.symbol ?? "" } } }
    var symbols: Set<String> = []
    var assets: [String: String] = [:]
    var cash = ""
    var interval = "1h"
    var maxExposurePct = ""
    var maxLossPct = ""
    var maxOrderUsd = ""
    var maxDailyUsd = ""
    var maxOrdersPerDay = ""
    var mandateDays = ""
    var slippageBps = ""

    // perp
    private(set) var venues: PerpVenues?
    private(set) var venuesError: String?
    var venue = ""
    var instruments: Set<String> = []
    var perpInterval = ""
    var leverage = "1"
    var grossX = ""
    var positionX = ""
    var dailyLossPct = ""
    var totalLossPct = ""
    var perpSlippage = ""
    var minTradePct = ""

    init(model: AppModel) { self.model = model; api = AgentsAPI(model.client) }

    var spotNetwork: AgentNetworks.Network? { networks?.networks.first { $0.id == network } }
    var perpVenue: PerpVenues.Venue? { venues?.venues.first { $0.id == venue } }

    func load(templates: AgentTemplates?) async {
        if templateId.isEmpty, let t = templates?.templates.first { templateId = t.id; applyTemplate(templates) }
        let api = api
        async let n = Result.catching { try await api.networks() }
        async let v = Result.catching { try await api.perpVenues() }
        switch await n {
        case .success(let x): networks = x; if network.isEmpty, let f = x.networks.first(where: \.enabled) { network = f.id }
        case .failure(let e): networksError = model.describe(e)
        }
        switch await v {
        case .success(let x):
            venues = x
            if venue.isEmpty { venue = x.venues.first?.id ?? "" }
            if perpInterval.isEmpty { perpInterval = x.intervals.first ?? "" }
            // the server's suggestions are shown and editable; leverage starts at 1, never at the suggested or maximum value
            let d = x.riskDefaults
            grossX = AgentCreateForm.plain(d.maxGrossExposureX); positionX = AgentCreateForm.plain(d.maxPositionX); dailyLossPct = AgentCreateForm.plain(d.maxDailyLossPct)
            totalLossPct = AgentCreateForm.plain(d.maxTotalLossPct); perpSlippage = String(d.slippageBps); minTradePct = AgentCreateForm.plain(d.minTradePct)
        case .failure(let e): venuesError = model.describe(e)
        }
    }

    nonisolated static func plain(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    private var templatesRef: AgentTemplates?
    func template(_ all: AgentTemplates?) -> AgentTemplate? { all?.templates.first { $0.id == templateId } }
    func applyTemplate(_ all: AgentTemplates? = nil) {
        if let all { templatesRef = all }
        guard let t = template(templatesRef) else { return }
        universeText = t.defaults.universe.joined(separator: ", "); venuesText = t.defaults.venues.joined(separator: ", ")
        strategyPath = t.installed.first?.path ?? ""
        capital = t.defaults.capitalUsdc
        riskText = t.defaults.risk.compactMapValues { v in
            switch v { case .int(let i): String(i); case .double(let d): AgentCreateForm.plain(d); case .string(let s): s; case .bool(let b): b ? "true" : "false"; default: nil }
        }
    }

    // MARK: validation — nothing unbounded leaves this form

    private func bounded(_ text: String, _ label: String, _ range: ClosedRange<Double>, integer: Bool = false) -> String? {
        guard let v = AgentText.decimal(text) else { return "\(label) : valeur requise (nombre fini)." }
        if integer, v != v.rounded() { return "\(label) : nombre entier requis." }
        guard range.contains(v) else { return "\(label) : entre \(AgentCreateForm.plain(range.lowerBound)) et \(AgentCreateForm.plain(range.upperBound))." }
        return nil
    }
    private var commonProblem: String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "Donnez un nom à l’agent." }
        if n.count > 60 { return "Nom : 60 caractères au plus." }
        guard let c = AgentText.decimal(capital), c > 0 else { return "Capital : montant positif requis." }
        if c > 10_000_000 { return "Capital : montant hors bornes." }
        return nil
    }

    func problem(templates: AgentTemplates?) -> String? {
        if let p = commonProblem { return p }
        switch kind {
        case .template:
            guard let t = template(templates) else { return "Choisissez un modèle." }
            for k in t.defaults.risk.keys.sorted() {
                guard let text = riskText[k] else { continue }
                switch t.defaults.risk[k]! {
                case .int, .double:
                    guard let v = AgentText.decimal(text) else { return "Limite « \(k) » : valeur requise (nombre fini, non négatif). Une limite ne peut pas être laissée vide." }
                    if v > 1e9 { return "Limite « \(k) » : valeur hors bornes." }
                case .bool: if text != "true" && text != "false" { return "Limite « \(k) » : true ou false." }
                default: if text.trimmingCharacters(in: .whitespaces).isEmpty { return "Limite « \(k) » : valeur requise." }
                }
            }
            if !t.installed.isEmpty, strategyPath.isEmpty { return "Choisissez la version de stratégie installée." }
            return nil
        case .spot:
            guard let n = spotNetwork, n.enabled else { return "Choisissez un réseau disponible." }
            if symbols.isEmpty { return "Choisissez au moins un marché." }
            if let max = networks?.maxSymbols, symbols.count > max { return "Au plus \(max) marchés." }
            if !n.cash.contains(where: { $0.symbol == cash }) { return "Choisissez la monnaie de règlement." }
            if let p = bounded(maxExposurePct, "Exposition maximale (%)", 1...100) ?? bounded(maxLossPct, "Perte maximale (%)", 1...100) ?? bounded(maxOrderUsd, "Plafond par ordre (USD)", 1...100_000)
                ?? bounded(maxDailyUsd, "Volume quotidien (USD)", 1...1_000_000) ?? bounded(maxOrdersPerDay, "Ordres par jour", 1...200, integer: true)
                ?? bounded(mandateDays, "Validité du mandat (jours)", 1...90, integer: true) ?? bounded(slippageBps, "Glissement (pb)", 5...300, integer: true) { return p }
            if (try? USDLimit(AgentText.decimalText(maxOrderUsd))) == nil || (try? USDLimit(AgentText.decimalText(maxDailyUsd))) == nil { return "Plafonds en USD : au plus 6 décimales." }
            if AgentText.decimal(maxOrderUsd)! > AgentText.decimal(maxDailyUsd)! { return "Le plafond par ordre ne peut pas dépasser le volume quotidien." }
            return nil
        case .perp:
            guard let v = venues, perpVenue != nil else { return "Plateforme indisponible." }
            if instruments.isEmpty { return "Choisissez au moins un instrument." }
            if instruments.count > v.maxInstruments { return "Au plus \(v.maxInstruments) instruments." }
            if !v.intervals.contains(perpInterval) { return "Choisissez le pas de temps." }
            if let min = AgentText.decimal(v.minCapital), let c = AgentText.decimal(capital), c < min { return "Capital simulé : au moins \(v.minCapital)." }
            if let p = bounded(leverage, "Levier maximal", 1...5, integer: true) ?? bounded(grossX, "Exposition brute (× capital)", 0.1...5) ?? bounded(positionX, "Position par instrument (× capital)", 0.05...5)
                ?? bounded(dailyLossPct, "Perte quotidienne (%)", 0.01...50) ?? bounded(totalLossPct, "Perte totale (%)", 0.01...90) ?? bounded(perpSlippage, "Glissement (pb)", 5...100, integer: true)
                ?? bounded(minTradePct, "Rééquilibrage minimal (%)", 0...100) { return p }
            if AgentText.decimal(dailyLossPct)! > AgentText.decimal(totalLossPct)! { return "La perte quotidienne ne peut pas dépasser la perte totale." }
            return nil
        }
    }

    private func list(_ s: String) -> [String] { s.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    func create(templates: AgentTemplates?) async {
        guard problem(templates: templates) == nil, model.canOperate, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), m = mission.trimmingCharacters(in: .whitespacesAndNewlines), cap = AgentText.decimalText(capital)
        do {
            switch kind {
            case .template:
                guard let t = template(templates) else { return }
                var risk: [String: JSONValue] = [:]
                for (k, proposed) in t.defaults.risk {
                    guard let text = riskText[k] else { risk[k] = proposed; continue }
                    switch proposed {
                    case .int, .double: let v = AgentText.decimal(text)!; risk[k] = v == v.rounded() && abs(v) < 9e15 ? .int(Int64(v)) : .double(v)
                    case .bool: risk[k] = .bool(text == "true")
                    default: risk[k] = .string(text)
                    }
                }
                let u = list(universeText), v = list(venuesText)
                let r = try await api.create(TemplateAgentCreateRequest(template: t.id, name: n, mission: m, strategyPath: strategyPath.isEmpty ? nil : strategyPath, universe: u.isEmpty ? nil : u, venues: v.isEmpty ? nil : v, capitalUsdc: cap, risk: risk, config: t.defaults.config))
                warnings = r.warnings ?? []; createdId = r.agent.id
            case .spot:
                let risk = SpotAgentRisk(maxExposurePct: AgentText.decimal(maxExposurePct)!, maxLossPct: AgentText.decimal(maxLossPct)!, maxOrderUsd: try USDLimit(AgentText.decimalText(maxOrderUsd)), maxDailyUsd: try USDLimit(AgentText.decimalText(maxDailyUsd)),
                                         maxOrdersPerDay: Int(AgentText.decimal(maxOrdersPerDay)!), mandateDays: Int(AgentText.decimal(mandateDays)!), slippageBps: Int(AgentText.decimal(slippageBps)!))
                let chosen = symbols.sorted()
                let a = try await api.create(SpotAgentCreateRequest(name: n, mission: m, network: network, universe: chosen, assets: assets.filter { chosen.contains($0.key) }, cash: cash, interval: interval, capitalUsdc: cap, risk: risk))
                warnings = a.warnings ?? []; createdId = a.id
            case .perp:
                let risk = PerpAgentRisk(maxLeverage: Int(AgentText.decimal(leverage)!), maxGrossExposureX: AgentText.decimal(grossX)!, maxPositionX: AgentText.decimal(positionX)!, maxDailyLossPct: AgentText.decimal(dailyLossPct)!,
                                         maxTotalLossPct: AgentText.decimal(totalLossPct)!, slippageBps: Int(AgentText.decimal(perpSlippage)!), minTradePct: AgentText.decimal(minTradePct)!)
                let a = try await api.create(PerpAgentCreateRequest(name: n, mission: m, instruments: instruments.sorted(), interval: perpInterval, capitalUsdc: cap, risk: risk))
                warnings = a.warnings ?? []; createdId = a.id
            }
        } catch { self.error = model.describe(error) }
    }
}

struct AgentCreateSheet: View {
    let model: AppModel
    let store: AgentsStore
    let onDone: (String?) -> Void
    @State private var form: AgentCreateForm?

    var body: some View {
        SheetScaffold(title: "Nouvel agent") {
            if let form {
                if let id = form.createdId { created(form, id) } else { content(form) }
            } else { ProgressView() }
        } footer: {
            if let form {
                if let e = form.error { Banner(.danger, e) }
                HStack {
                    if form.createdId == nil, let p = form.problem(templates: store.templates) { Text(p).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    if form.busy { ProgressView().controlSize(.small) }
                    if let id = form.createdId { Button("Ouvrir l’agent") { onDone(id) }.buttonStyle(.borderedProminent).controlSize(.large) }
                    else {
                        Button("Annuler") { onDone(nil) }.disabled(form.busy)
                        Button(form.kind == .perp ? "Créer l’agent · SIMULATION" : "Créer l’agent · sans autorité") { Task { await form.create(templates: store.templates) } }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(form.problem(templates: store.templates) != nil || !model.canOperate || form.busy)
                    }
                }
            }
        }
        .task {
            if form == nil { let f = AgentCreateForm(model: model); form = f; if store.templates == nil { await store.loadTemplates() }; await f.load(templates: store.templates) }
        }
    }

    @ViewBuilder private func created(_ form: AgentCreateForm, _ id: String) -> some View {
        Banner(.ok, "Agent créé. Rien n’a été signé et il ne détient aucune autorité : il ne peut négocier en réel qu’après un mandat approuvé avec votre passkey.")
        ForEach(form.warnings, id: \.self) { w in Banner(.warning, "\(w.message) [\(w.code)]") }
    }

    @ViewBuilder private func content(_ form: AgentCreateForm) -> some View {
        @Bindable var form = form
        Picker("Type", selection: $form.kind) { ForEach(AgentCreateForm.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
        Banner(.info, "La création ne signe rien, ne déplace aucun fonds et ne promet aucun rendement. Chaque limite doit être indiquée : aucune valeur illimitée n’est acceptée.")
        Form {
            TextField("Nom", text: $form.name)
            TextField("Mission (note libre)", text: $form.mission, axis: .vertical).lineLimit(1...3)
        }.formStyle(.grouped).scrollDisabled(true)
        switch form.kind {
        case .template: templateForm(form)
        case .spot: spotForm(form)
        case .perp: perpForm(form)
        }
    }

    // MARK: template

    @ViewBuilder private func templateForm(_ form: AgentCreateForm) -> some View {
        @Bindable var form = form
        if let all = store.templates {
            Form {
                Picker("Modèle", selection: $form.templateId) { ForEach(all.templates) { t in Text("\(t.name.fr) — \(AgentText.family(t.family))").tag(t.id) } }
            }.formStyle(.grouped).scrollDisabled(true)
            if let t = form.template(all) {
                Text(t.summary.fr).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) { Text("Modes permis par le serveur :").font(.callout).foregroundStyle(.secondary); ForEach(t.modes, id: \.self) { ModeTag(kind: ModeKind($0), compact: true) } }
                if !t.modes.contains(.live) { Banner(.warning, "Ce modèle ne peut pas passer en réel\(t.liveReason.map { " : \($0)" } ?? ".")") }
                if !t.strategyInstalled, t.rule == nil { Banner(.warning, "La stratégie de ce modèle n’est pas installée sur le serveur : l’agent sera créé sans version exécutable.") }
                ForEach(Array((t.labVerdicts ?? []).enumerated()), id: \.offset) { _, v in LabVerdictView(verdict: v) }
                Form {
                    if !t.installed.isEmpty {
                        Picker("Version de stratégie", selection: $form.strategyPath) { ForEach(t.installed, id: \.path) { i in Text("\(i.name) \(i.version)\(i.liveCapable ? "" : " — papier seulement")").tag(i.path) } }
                        if let i = t.installed.first(where: { $0.path == form.strategyPath }), !i.liveCapable, let r = i.liveReason { LabeledContent("") { Text(r).font(.caption).foregroundStyle(Theme.warning) } }
                    }
                    TextField("Marchés (séparés par des virgules)", text: $form.universeText)
                    TextField("Plateformes", text: $form.venuesText)
                    TextField("Capital (USDC — simulé tant que l’agent n’est pas réel)", text: $form.capital)
                    SwiftUI.Section("Limites de risque (proposées par le modèle, à confirmer une à une)") {
                        ForEach(t.defaults.risk.keys.sorted(), id: \.self) { k in
                            if form.riskText[k] != nil { TextField(k, text: Binding(get: { form.riskText[k] ?? "" }, set: { form.riskText[k] = $0 })).font(Theme.monoSmall) }
                            else { LabeledContent(k) { Text(JSONFlat.text(t.defaults.risk[k]!)).font(Theme.monoSmall) } }
                        }
                    }
                }.formStyle(.grouped).scrollDisabled(true)
                if !t.defaults.config.isEmpty { DisclosureGroup("Configuration initiale du modèle (modifiable ensuite, agent en pause)") { JSONFacts(value: .object(t.defaults.config)).padding(.top, 6) } }
            }
        } else if let e = store.templatesError { Banner(.danger, "Modèles indisponibles : \(e)") } else { ProgressView() }
    }

    // MARK: spot

    @ViewBuilder private func spotForm(_ form: AgentCreateForm) -> some View {
        @Bindable var form = form
        if let nets = form.networks {
            Form {
                Picker("Réseau du coffre", selection: $form.network) { ForEach(nets.networks) { n in Text(n.name + (n.enabled ? "" : " — indisponible")).tag(n.id) } }
                if let n = form.spotNetwork {
                    Picker("Monnaie de règlement", selection: $form.cash) { ForEach(n.cash, id: \.symbol) { Text("\($0.symbol) — \($0.name)").tag($0.symbol) } }
                    Picker("Pas de temps", selection: $form.interval) { Text("1 heure").tag("1h"); Text("1 jour").tag("1d") }
                    LabeledContent("Réserve de gaz requise pour le réel") { Text(n.gas.map { "\($0.reserve) \(n.native) (≈ \($0.perOrder) par ordre)" } ?? "Inconnue pour l’instant").foregroundStyle(n.gas == nil ? Theme.warning : .primary) }
                }
                TextField("Capital prévu (USDC)", text: $form.capital, prompt: Text("ex. 500"))
            }.formStyle(.grouped).scrollDisabled(true)
            if let n = form.spotNetwork {
                if n.feeWarning { Banner(.warning, "Sur ce réseau, les frais de transaction pèsent lourd face à de petits ordres.") }
                Text("Marchés (\(form.symbols.count) sur \(nets.maxSymbols) au plus ; un mandat réel couvre au plus \(nets.maxLiveSymbols - 1) marchés)").font(.callout.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(n.symbols, id: \.symbol) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(isOn: Binding(get: { form.symbols.contains(s.symbol) }, set: { on in
                                if on { form.symbols.insert(s.symbol); if form.assets[s.symbol] == nil { form.assets[s.symbol] = s.defaultAsset ?? s.representations.first?.asset } } else { form.symbols.remove(s.symbol) }
                            })) { Text(s.symbol + (s.live ? "" : " — papier seulement")).foregroundStyle(s.live ? Color.primary : Theme.warning) }.toggleStyle(.checkbox)
                            if form.symbols.contains(s.symbol), s.representations.count > 1 {
                                Picker("Actif détenu", selection: Binding(get: { form.assets[s.symbol] ?? "" }, set: { form.assets[s.symbol] = $0 })) {
                                    ForEach(s.representations, id: \.asset) { r in Text("\(r.assetSymbol) (\(r.kind)\(r.issuer.map { ", \($0)" } ?? ""))").tag(r.asset) }
                                }.labelsHidden().controlSize(.small)
                            }
                        }
                    }
                }
                if form.symbols.contains(where: { sym in n.symbols.first { $0.symbol == sym }?.live == false }) { Banner(.warning, "Un marché choisi ne peut pas être évalué par le signataire : l’agent ne pourra pas recevoir de mandat réel avec ce marché.") }
            }
            Form {
                SwiftUI.Section("Limites — toutes obligatoires") {
                    TextField("Exposition maximale hors monnaie de règlement (%, 1–100)", text: $form.maxExposurePct)
                    TextField("Perte maximale avant arrêt par le moteur (%, 1–100)", text: $form.maxLossPct)
                    TextField("Plafond par ordre (USD, 1–100 000)", text: $form.maxOrderUsd)
                    TextField("Volume quotidien maximal (USD, 1–1 000 000)", text: $form.maxDailyUsd)
                    TextField("Ordres par jour (1–200)", text: $form.maxOrdersPerDay)
                    TextField("Validité d’un futur mandat (jours, 1–90)", text: $form.mandateDays)
                    TextField("Glissement toléré (points de base, 5–300)", text: $form.slippageBps)
                }
            }.formStyle(.grouped).scrollDisabled(true)
            Text("La perte maximale et la part d’exposition sont appliquées par le moteur de l’agent, pas par le signataire : un écart de prix peut les dépasser. Les plafonds par ordre, le volume quotidien, le nombre d’ordres et la validité seront, eux, inscrits dans le mandat que le signataire applique.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if let e = form.networksError { Banner(.danger, "Catalogue des réseaux indisponible : \(e)") } else { ProgressView() }
    }

    // MARK: perp

    @ViewBuilder private func perpForm(_ form: AgentCreateForm) -> some View {
        @Bindable var form = form
        if let pv = form.venues {
            ModeHeaderBand(kind: ModeKind(.paper))
            Text("Un agent de perpétuels est créé en simulation sur un compte papier : pas de coffre, pas de mandat, rien n’est demandé au signataire.").font(.callout).foregroundStyle(.secondary)
            if let l = pv.live, !l.available { Banner(.info, "Passage en réel indisponible sur ce serveur\(l.reason.map { " : \($0)" } ?? ".")") }
            Form {
                if pv.venues.count > 1 { Picker("Plateforme", selection: $form.venue) { ForEach(pv.venues) { Text($0.name).tag($0.id) } } }
                else { LabeledContent("Plateforme") { Text(form.perpVenue?.name ?? "—") } }
                Picker("Pas de temps", selection: $form.perpInterval) { ForEach(pv.intervals, id: \.self) { Text($0).tag($0) } }
                TextField("Capital SIMULÉ (USDC, au moins \(pv.minCapital))", text: $form.capital)
            }.formStyle(.grouped).scrollDisabled(true)
            if let v = form.perpVenue {
                Text("Instruments (\(form.instruments.count) sur \(pv.maxInstruments) au plus)").font(.callout.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(v.instruments) { i in
                        Toggle(isOn: Binding(get: { form.instruments.contains(i.symbol) }, set: { if $0 { form.instruments.insert(i.symbol) } else { form.instruments.remove(i.symbol) } })) {
                            Text(i.symbol + (i.eligible ? (i.maxLeverage.map { " · levier plateforme ≤ \($0)" } ?? "") : " — \(i.why ?? "non admissible")")).foregroundStyle(i.eligible ? Color.primary : Color.secondary)
                        }.toggleStyle(.checkbox).disabled(!i.eligible)
                    }
                }
            }
            Form {
                SwiftUI.Section("Limites — toutes obligatoires (valeurs suggérées par le serveur, sauf le levier qui part de 1)") {
                    TextField("Levier maximal (entier, 1–5)", text: $form.leverage)
                    TextField("Exposition brute (× capital, 0,1–5)", text: $form.grossX)
                    TextField("Position par instrument (× capital, 0,05–5)", text: $form.positionX)
                    TextField("Perte quotidienne maximale (% du capital, 0,01–50)", text: $form.dailyLossPct)
                    TextField("Perte totale maximale (% du capital, 0,01–90)", text: $form.totalLossPct)
                    TextField("Glissement toléré (points de base, 5–100)", text: $form.perpSlippage)
                    TextField("Rééquilibrage minimal (% des fonds propres)", text: $form.minTradePct)
                }
            }.formStyle(.grouped).scrollDisabled(true)
            Text("Un levier plus élevé rapproche le prix de liquidation et augmente les pertes possibles. En simulation, la liquidation et le financement sont modélisés, jamais garantis identiques au réel.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else if let e = form.venuesError { Banner(.danger, "Plateformes indisponibles : \(e)") } else { ProgressView() }
    }
}
