// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/TradingAgents/AgentMandateViews.swift
// Description      : The mandate and the risks of an agent (what the signer
//                    holds now, the prominent revocation that needs no passkey,
//                    the door to a new passkey-approved mandate, who enforces
//                    each limit) and its configuration with its versions. A
//                    limit can be edited only while the agent is not running,
//                    and never to an empty or unbounded value.
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

struct AgentMandateSection: View {
    let model: AppModel
    let d: AgentDetailStore
    let store: AgentsStore
    let spotFlow: SpotGoLiveFlow
    @State private var confirmRevoke = false

    var body: some View {
        switch d.detail {
        case .spot(let s): spot(s)
        case .perp(let p):
            Card("Mandat de dérivés") {
                if let l = p.live, l.active || l.mandateId != nil {
                    let kind = ModeKind(.live, liveNetwork: l.network)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { ModeTag(kind: kind); Text(l.active ? "Mandat en vigueur" : "Dernier mandat").fontWeight(.semibold) }
                        Field(label: "Mandat", value: l.mandateId ?? "—", mono: true)
                        Field(label: "Compte / réseau", value: "\(l.accountId ?? "—") · \(l.network ?? "—")")
                        if let c = l.capital { Field(label: "Capital de référence", value: "\(Fmt.amount(c)) USDC") }
                        Text("Mandat et compteurs tels que le SIGNATAIRE les rapporte").font(.caption.weight(.semibold))
                        JSONFacts(value: l.signer, depth: 3, empty: "Le signataire n’a rien rapporté pour ce mandat.")
                    }.modeFramed(kind)
                } else { Text("Aucun mandat de dérivés pour cet agent.").foregroundStyle(.secondary) }
                Text("La préparation, l’approbation, la pause et la révocation du mandat d’un agent de perpétuels sont dans l’onglet Perpétuels.").font(.callout).foregroundStyle(.secondary)
            }
            StatementsCard(can: CustodyFacts.perpCan, cannot: CustodyFacts.perpCannot, notBounded: CustodyFacts.perpNotBounded)
        default:
            Card("Mandat") {
                if let m = d.summary?.mandate { Field(label: "Mandat en vigueur", value: "\(m.kind) · \(m.id)", mono: true) } else { Text("Aucun mandat en vigueur pour cet agent.").foregroundStyle(.secondary) }
                if d.isMarketMaking { Text("Le mandat de cotation, sa liste de contrôle et sa révocation sont dans l’onglet Tenue de marché.").font(.callout).foregroundStyle(.secondary) }
            }
        }
        limits
        draft
    }

    // MARK: spot

    @ViewBuilder private func spot(_ s: SpotAgentDetail) -> some View {
        let a = s.agent, live = ModeKind(.live)
        Card("Mandat du coffre", trailing: AnyView(Group { if a.mode == .live { ModeTag(kind: live) } })) {
            if let m = s.mandateStatus {
                Field(label: "État au signataire", value: m.active ? "EN VIGUEUR" : m.revoked ? "Révoqué" : m.expired ? "Expiré" : "Inactif", emphasis: true)
                Field(label: "Expiration", value: "\(Fmt.dateSeconds(m.expiry)) (\(Fmt.relative(m.expiry)))")
                Field(label: "Ordres par jour", value: "\(m.today?.orders.map(String.init) ?? "—") utilisés aujourd’hui sur \(m.maxOrdersPerDay)")
                ForEach(m.maxOrder.keys.sorted(), id: \.self) { asset in
                    let h = a.holdings?.first { $0.asset == asset }, dec = model.network(a.network)?.asset(asset)?.decimals
                    Field(label: "Plafonds \(h?.assetSymbol ?? Fmt.short(asset))", value: "par ordre \(units(m.maxOrder[asset], dec)) · par jour \(units(m.maxDaily[asset], dec)) · vendu aujourd’hui \(units(m.today?.sold?[asset] ?? "0", dec))")
                }
                if let ms = a.mandate { Field(label: "Stratégie épinglée", value: ms.strategySha256, mono: true) }
            } else { Text("Le signataire ne détient aucun mandat pour ce coffre : l’agent ne peut rien signer.").foregroundStyle(.secondary) }

            if s.mandateStatus?.active == true || a.mode == .live {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Révocation").font(.headline)
                        Text("Immédiate et définitive, SANS passkey : le signataire ne signe plus aucun échange pour ce coffre et l’agent est arrêté. Les fonds restent dans le coffre ; un nouveau mandat exigera votre passkey.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(role: .destructive) { confirmRevoke = true } label: { Label("Révoquer le mandat", systemImage: "xmark.shield.fill").fontWeight(.semibold) }
                        .buttonStyle(.borderedProminent).tint(Theme.negative).controlSize(.large).disabled(!model.canOperate || d.busy != nil)
                }
            }
            if let n = d.notice { Banner(.info, n) }
            if let e = d.actionError { Banner(.danger, e) }
        }
        .confirmationDialog("Révoquer le mandat de « \(a.name) » ?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Révoquer le mandat", role: .destructive) { Task { await d.revokeSpotMandate(); await store.refresh() } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Le signataire cesse immédiatement de signer pour ce coffre et l’agent est arrêté. Les positions détenues par le coffre ne sont pas vendues.") }

        if a.mode != .live {
            Card("Passer en réel", trailing: AnyView(ModeTag(kind: live))) {
                let version = s.approvedVersion, capable = d.summary?.live
                VStack(alignment: .leading, spacing: 6) {
                    check(version != nil, "Une version de stratégie approuvée par vous est en service", version.map { "\($0.name) \($0.version)" } ?? "Approuvez une version dans l’onglet Stratégie.")
                    check(capable?.capable == true, "Le serveur permet le mode réel pour cet agent", capable?.capable == true ? nil : capable?.reason ?? capable?.code ?? "Vue d’ensemble non lue.")
                    check(s.vault != nil, "Les soldes du coffre sont lisibles sur la chaîne", s.vault == nil ? "Lecture de chaîne en échec." : "Le serveur exigera aussi une réserve de gaz dans le coffre (onglet Coffre).")
                    check(model.network(a.network) != nil, "Le réseau du coffre est dans le registre de ce portefeuille", nil)
                    check(store.killSwitch?.engaged == false, "L’arrêt d’urgence n’est pas engagé", store.killSwitch == nil ? "État inconnu." : nil)
                }
                Text("Préparer ne signe rien : le serveur construit le mandat à partir de vos limites, cette app le vérifie champ par champ et vérifie que le défi de la passkey est son empreinte. Vous verrez ensuite le mandat complet avant d’approuver.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let e = spotFlow.error { Banner(.danger, e) }
                if spotFlow.step == .done { Banner(.ok, "Mandat approuvé et enregistré au signataire. État de l’agent selon le serveur : \(spotFlow.result.map { AgentText.phase($0.state) } ?? "—").") }
                HStack {
                    Spacer()
                    if spotFlow.step == .preparing { ProgressView().controlSize(.small); Text("Construction et vérification du mandat…").foregroundStyle(.secondary) }
                    ModeButton(title: "Préparer le mandat à approuver…", kind: live, systemImage: "touchid", prominent: true) { Task { await spotFlow.prepare(s) } }
                        .disabled(!model.canOperate || version == nil || capable?.capable != true || spotFlow.step != .idle && spotFlow.step != .done || d.busy != nil)
                }
            }
        }
        StatementsCard(can: CustodyFacts.spotCan, cannot: CustodyFacts.spotCannot, notBounded: CustodyFacts.spotNotBounded)
    }

    private func units(_ s: String?, _ decimals: Int?) -> String {
        guard let s else { return "—" }
        guard let decimals, let u = try? BaseUnits(s) else { return "\(s) (unités de base)" }
        return Fmt.amount(u.formatted(decimals: decimals))
    }

    private func check(_ ok: Bool, _ text: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.positive : .secondary)
            VStack(alignment: .leading, spacing: 1) { Text(text); if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
        }
    }

    // MARK: limits and draft

    @ViewBuilder private var limits: some View {
        Card("Limites de risque de l’agent") {
            if let a = d.agent {
                if let r = a.spotRisk {
                    limit("Plafond par ordre", "\(r.maxOrderUsd.text) USD", "inscrit dans le mandat — appliqué par le signataire")
                    limit("Volume quotidien", "\(r.maxDailyUsd.text) USD", "inscrit dans le mandat — appliqué par le signataire")
                    limit("Ordres par jour", String(r.maxOrdersPerDay), "inscrit dans le mandat — appliqué par le signataire")
                    limit("Validité d’un mandat", "\(r.mandateDays) jour(s)", "inscrit dans le mandat — appliqué par le signataire")
                    limit("Glissement", "\(r.slippageBps) pb (garde du mandat : \(r.mandateSlippageBps) pb)", "garde du mandat appliquée par le signataire")
                    limit("Exposition maximale", "\(AgentCreateForm.plain(r.maxExposurePct)) % du coffre", "moteur de l’API seulement", warn: true)
                    limit("Perte maximale", "\(AgentCreateForm.plain(r.maxLossPct)) % du capital", "moteur de l’API seulement — un écart de prix peut la dépasser", warn: true)
                } else if let r = a.perpRisk {
                    limit("Levier maximal", "×\(r.maxLeverage)", "réglage de levier borné par le signataire sous mandat")
                    limit("Exposition brute", "× \(AgentCreateForm.plain(r.maxGrossExposureX)) du capital", "moteur de risque de l’API", warn: true)
                    limit("Position par instrument", "× \(AgentCreateForm.plain(r.maxPositionX)) du capital", "moteur de risque de l’API", warn: true)
                    limit("Perte quotidienne", "\(AgentCreateForm.plain(r.maxDailyLossPct)) % du capital — fermeture puis arrêt", "moteur de l’API ; sous mandat, plancher de valeur du compte lu par le signataire", warn: true)
                    limit("Perte totale", "\(AgentCreateForm.plain(r.maxTotalLossPct)) % du capital", "moteur de l’API", warn: true)
                    limit("Glissement", "\(r.slippageBps) pb", "moteur de l’API ; écart de prix borné par le mandat")
                    limit("Rééquilibrage minimal", "\(AgentCreateForm.plain(r.minTradePct)) % des fonds propres", "moteur de l’API")
                } else {
                    JSONFacts(value: d.summary?.riskLimits ?? a.risk, depth: 3, empty: "Le serveur n’a publié aucune limite pour cet agent.")
                    Text("Limites telles que le serveur les stocke. En simulation elles sont appliquées par le moteur de l’agent.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func limit(_ label: String, _ value: String, _ who: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 190, alignment: .leading)
            Text(value).fontWeight(.medium).monospacedDigit().frame(width: 260, alignment: .leading)
            Label(who, systemImage: warn ? "exclamationmark.triangle" : "lock.shield").font(.caption).foregroundStyle(warn ? Theme.warning : Theme.positive).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var draft: some View {
        Card("Ce que le serveur ferait approuver pour passer en réel (lecture seule)") {
            if let m = d.mandateDraft {
                Field(label: "Disponible", value: m.available ? "oui" : "non\(m.reason.map { " — \($0)" } ?? "")\(m.code.map { " [\($0)]" } ?? "")")
                if let k = m.kind { Field(label: "Nature du mandat", value: "\(k)\(m.shape.map { " · \($0)" } ?? "")") }
                Field(label: "Approbation", value: m.approval.note)
                if let p = m.pending { Field(label: "Mandat en attente", value: "\(p.mandateId) — \(p.state)", mono: true) }
                if let c = m.checklist { Field(label: "Liste de contrôle", value: c) }
                if let f = m.fields, !f.isNull { Text("Champs").font(.caption.weight(.semibold)); JSONFacts(value: f, depth: 3) }
                if let r = m.readiness, !r.isNull { DisclosureGroup("État de préparation") { JSONFacts(value: r, depth: 3).padding(.top, 6) } }
                Text("Lire ce brouillon ne prépare rien au signataire et n’accorde rien.").font(.caption).foregroundStyle(.secondary)
            } else { Unavailable(what: "Brouillon de mandat", error: d.error("mandateDraft")) }
        }
        .task { await d.loadConfig() }
    }
}

struct StatementsCard: View {
    let can: [String]; let cannot: [String]; let notBounded: [String]
    var body: some View {
        Card("Ce que le signataire isolé borne — et ne borne pas") {
            StatementList(title: "Sous mandat, la clé PEUT", symbol: "checkmark.circle", color: Theme.positive, items: can)
            StatementList(title: "Elle NE PEUT PAS", symbol: "xmark.circle", color: .secondary, items: cannot)
            StatementList(title: "Le signataire NE BORNE PAS", symbol: "exclamationmark.triangle.fill", color: Theme.negative, items: notBounded)
            Text("Source : décision d’architecture sur la garde des clés (ADR 0001) du serveur. Révoquer une autorité permanente ne demande jamais de passkey et est définitif.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: configuration

/// Scalar server values edited as text and rebuilt with their original JSON type. An empty or non-finite limit is refused.
enum JSONEdit {
    static func editable(_ v: JSONValue) -> String? {
        switch v { case .int(let i): String(i); case .double(let x): AgentCreateForm.plain(x); case .string(let s): s; case .bool(let b): b ? "true" : "false"; default: nil }
    }
    static func rebuild(_ text: String, like original: JSONValue) -> JSONValue? {
        switch original {
        case .int, .double:
            guard let v = AgentText.decimal(text), v <= 1e12 else { return nil }
            if case .int = original, v == v.rounded() { return .int(Int64(v)) }
            return v == v.rounded() && abs(v) < 9e15 ? .int(Int64(v)) : .double(v)
        case .bool: return text == "true" ? .bool(true) : text == "false" ? .bool(false) : nil
        case .string: return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .string(text)
        default: return original
        }
    }
}

struct AgentConfigSection: View {
    let model: AppModel
    let d: AgentDetailStore
    @State private var editing = false
    @State private var configText: [String: String] = [:]
    @State private var riskText: [String: String] = [:]
    @State private var perp: [String: String] = [:]
    @State private var liftHalt = false

    private var runtimeConfig: [String: JSONValue] { d.overview?.runtime?.config?.objectValue ?? [:] }
    private var riskLimits: [String: JSONValue] { d.summary?.riskLimits.objectValue ?? [:] }
    private var stopped: Bool { d.summary.map { $0.state != .active && !$0.isWindingDown } ?? false }

    var body: some View {
        let a = d.agent
        Card("Configuration en service") {
            Field(label: "Version", value: "v\(d.summary?.configVersion ?? a?.configVersion ?? 0)", emphasis: true)
            if let rt = d.overview?.runtime {
                Field(label: "Règle / plateformes", value: "\(rt.rule ?? "—") · \(rt.venues.joined(separator: ", "))")
                JSONFacts(value: rt.config, depth: 3, empty: "Aucun paramètre publié.")
                if let c = rt.counters, !c.isNull { DisclosureGroup("Compteurs du moteur") { JSONFacts(value: c, depth: 3).padding(.top, 6) } }
                if let p = rt.lastPass, !p.isNull { DisclosureGroup("Dernière passe du moteur") { JSONFacts(value: p, depth: 3).padding(.top, 6) } }
            } else if case .perp(let p)? = d.detail {
                Field(label: "Exécution", value: "\(p.execution.kind)\(p.execution.network.map { " · \($0)" } ?? "") — \(p.execution.note)")
                if let r = p.rules, !r.isNull { DisclosureGroup("Simplifications et garde-fous déclarés de la simulation") { JSONFacts(value: r, depth: 3).padding(.top, 6) } }
            } else { Text("Les paramètres de cet agent sont ses marchés, son pas de temps et ses limites (onglet Mandat et risques).").foregroundStyle(.secondary) }
        }
        if let a { editor(a) }
        Card("Versions de configuration") {
            if let v = d.configVersions {
                if v.isEmpty { Text("Aucune version enregistrée.").foregroundStyle(.secondary) }
                ForEach(v, id: \.version) { x in
                    DisclosureGroup("v\(x.version) · \(Fmt.date(x.createdAt)) · \(x.actor) — \(x.reason)") {
                        VStack(alignment: .leading, spacing: 4) { Field(label: "SHA-256", value: x.sha256, mono: true); JSONFacts(value: x.config, depth: 3) }.padding(.top, 6)
                    }
                }
            } else { Unavailable(what: "Versions", error: d.error("configVersions")) }
        }
        .task { await d.loadConfig() }
    }

    @ViewBuilder private func editor(_ a: Agent) -> some View {
        switch a.resolvedKind {
        case .stream, .supervisor:
            Card("Modifier la configuration et les limites") {
                if !stopped { Text("L’agent doit être en pause ou arrêté pour être reconfiguré.").foregroundStyle(.secondary) }
                else if !editing { Button("Modifier…") { configText = runtimeConfig.compactMapValues(JSONEdit.editable); riskText = riskLimits.compactMapValues(JSONEdit.editable); editing = true }.disabled(!model.canOperate) }
                else {
                    Form {
                        if !configText.isEmpty { SwiftUI.Section("Paramètres") { ForEach(configText.keys.sorted(), id: \.self) { k in TextField(k, text: Binding(get: { configText[k] ?? "" }, set: { configText[k] = $0 })).font(Theme.monoSmall) } } }
                        if !riskText.isEmpty { SwiftUI.Section("Limites de risque") { ForEach(riskText.keys.sorted(), id: \.self) { k in TextField(k, text: Binding(get: { riskText[k] ?? "" }, set: { riskText[k] = $0 })).font(Theme.monoSmall) } } }
                    }.formStyle(.grouped).scrollDisabled(true)
                    let problem = editProblem
                    if let problem { Text(problem).font(.callout).foregroundStyle(Theme.warning) }
                    Text("Les valeurs imbriquées restent inchangées. Une limite ne peut être ni vidée ni rendue illimitée ; le serveur vérifie ses propres bornes.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Annuler") { editing = false }
                        Spacer()
                        if d.busy != nil { ProgressView().controlSize(.small) }
                        Button("Enregistrer une nouvelle version") { Task { if await save() { editing = false } } }.buttonStyle(.borderedProminent).disabled(problem != nil || !model.canOperate || d.busy != nil)
                    }
                }
                if let e = d.actionError { Banner(.danger, e) }
            }
        case .perp:
            let sim = ModeKind(.paper)
            Card("Limites de la simulation", trailing: AnyView(ModeTag(kind: sim))) {
                if a.mode == .live { Text("En réel, les limites de l’agent sont celles de son mandat : elles ne se modifient pas ici. Arrêtez l’agent et approuvez un nouveau mandat pour les changer.").foregroundStyle(.secondary) }
                else if let r = a.perpRisk {
                    if !editing {
                        Button("Modifier les limites · PAPIER…") {
                            perp = ["lev": String(r.maxLeverage), "gross": AgentCreateForm.plain(r.maxGrossExposureX), "pos": AgentCreateForm.plain(r.maxPositionX), "day": AgentCreateForm.plain(r.maxDailyLossPct),
                                    "total": AgentCreateForm.plain(r.maxTotalLossPct), "slip": String(r.slippageBps), "min": AgentCreateForm.plain(r.minTradePct)]
                            liftHalt = false; editing = true
                        }.disabled(!model.canOperate)
                    } else {
                        Form {
                            perpField("Levier maximal (entier, 1–5)", "lev"); perpField("Exposition brute (× capital, 0,1–5)", "gross"); perpField("Position par instrument (× capital, 0,05–5)", "pos")
                            perpField("Perte quotidienne (%, 0,01–50)", "day"); perpField("Perte totale (%, 0,01–90)", "total"); perpField("Glissement (pb, 5–100)", "slip"); perpField("Rééquilibrage minimal (%)", "min")
                            Toggle("Lever le disjoncteur du compte simulé", isOn: $liftHalt)
                        }.formStyle(.grouped).scrollDisabled(true)
                        let risk = perpRisk
                        if risk == nil { Text("Chaque limite est obligatoire et doit rester dans ses bornes ; la perte quotidienne ne dépasse pas la perte totale.").font(.callout).foregroundStyle(Theme.warning) }
                        HStack {
                            Button("Annuler") { editing = false }
                            Spacer()
                            ModeButton(title: "Enregistrer les limites", kind: sim, prominent: true) { Task { if let risk, await d.setPerpRisk(risk, liftHalt: liftHalt) { editing = false } } }.disabled(risk == nil || !model.canOperate || d.busy != nil)
                        }
                    }
                } else { Text("Limites illisibles.").foregroundStyle(.secondary) }
                if let e = d.actionError { Banner(.danger, e) }
            }
        default:
            Card("Modifier les limites") { Text("Les limites d’un agent au comptant sont fixées à sa création : elles déterminent le mandat. Pour d’autres limites, créez un nouvel agent.").foregroundStyle(.secondary) }
        }
    }

    private func perpField(_ label: String, _ key: String) -> some View { TextField(label, text: Binding(get: { perp[key] ?? "" }, set: { perp[key] = $0 })) }

    private var perpRisk: PerpAgentRisk? {
        func v(_ k: String, _ r: ClosedRange<Double>, integer: Bool = false) -> Double? {
            guard let x = AgentText.decimal(perp[k] ?? ""), r.contains(x), !integer || x == x.rounded() else { return nil }
            return x
        }
        guard let lev = v("lev", 1...5, integer: true), let gross = v("gross", 0.1...5), let pos = v("pos", 0.05...5), let day = v("day", 0.01...50), let total = v("total", 0.01...90),
              let slip = v("slip", 5...100, integer: true), let min = v("min", 0...100), day <= total else { return nil }
        return PerpAgentRisk(maxLeverage: Int(lev), maxGrossExposureX: gross, maxPositionX: pos, maxDailyLossPct: day, maxTotalLossPct: total, slippageBps: Int(slip), minTradePct: min)
    }

    private var editProblem: String? {
        for (k, t) in configText { if let o = runtimeConfig[k], JSONEdit.rebuild(t, like: o) == nil { return "Paramètre « \(k) » : valeur invalide." } }
        for (k, t) in riskText { if let o = riskLimits[k], JSONEdit.rebuild(t, like: o) == nil { return "Limite « \(k) » : valeur requise, finie et non négative. Une limite ne peut pas être vidée." } }
        return nil
    }

    private func save() async -> Bool {
        var config = runtimeConfig, risk = riskLimits
        for (k, t) in configText { if let o = runtimeConfig[k], let v = JSONEdit.rebuild(t, like: o) { config[k] = v } }
        for (k, t) in riskText { if let o = riskLimits[k], let v = JSONEdit.rebuild(t, like: o) { risk[k] = v } }
        return await d.updateConfig(config: config == runtimeConfig ? nil : config, risk: risk == riskLimits ? nil : risk)
    }
}
