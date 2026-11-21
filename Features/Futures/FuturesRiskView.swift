// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Futures/FuturesRiskView.swift
// Description      : The API-side risk engine: the global kill switch and the
//                    read-only switch, the automatic stops, the limits of each
//                    mode (paper / live) with what is missing, the exposure of
//                    each book (paper, live mainnet, live testnet — never
//                    merged), the engine's decision log and the server locks.
//                    The server's rule is kept as it is: what REMOVES authority
//                    is one click and a confirmation, without passkey (engaging
//                    a switch, tightening a limit, switching an automatic stop
//                    on); what GIVES authority back (releasing a switch,
//                    loosening a limit, switching a stop off) is prepared,
//                    verified by the Core against its challenge, reviewed and
//                    approved with the passkey.
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

@MainActor @Observable final class FutRiskFlow {
    enum Sheet: Identifiable {
        case release(RiskSwitchReleaseApproval)
        case limits(RiskLimitsApproval)
        case auto(AutoKillApproval)
        var id: String {
            switch self { case .release(let a): "rel-\(a.intent.nonce)"; case .limits(let a): "lim-\(a.intent.nonce)"; case .auto(let a): "auto-\(a.intent.nonce)" }
        }
    }
    let model: AppModel
    let store: FuturesStore
    var sheet: Sheet?
    private(set) var busy = false
    private(set) var approving = false
    var error: String?
    var sheetError: String?
    var notice: String?

    init(model: AppModel, store: FuturesStore) { self.model = model; self.store = store }
    private var risk: RiskAPI { store.risk }

    private func run(_ body: () async throws -> Void) async {
        guard model.canOperate, !busy, !approving else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do { try await body() } catch { self.error = model.describe(error); await store.loadRiskState() }
    }

    /// One click and a confirmation, no passkey. The switch is shown as engaged only when the server's answer says so.
    func engage(_ kind: RiskSwitchKind, reason: String) async {
        await run {
            let s: RiskSwitches
            if kind == .killSwitch { s = try await risk.engageKillSwitch(reason: reason) } else { s = try await risk.engageReadOnly(reason: reason) }
            await store.loadRiskState()
            notice = (kind == .killSwitch ? "Coupe-circuit" : "Mode lecture seule") + " engagé, confirmé par le serveur" + (s.state(of: kind).engagedAt.map { " à \(Fmt.dateSeconds($0))" } ?? "") + "."
        }
    }

    func prepareRelease(_ kind: RiskSwitchKind) async {
        guard let displayed = store.riskState.value?.switches.state(of: kind) else { return }
        await run {
            switch try await risk.prepareRelease(kind, displayed: displayed) {
            case .notEngaged: notice = "Ce commutateur n’est pas engagé : rien à lever."; await store.loadRiskState()
            case .approval(let a): sheetError = nil; sheet = .release(a)
            }
        }
    }

    func setAuto(_ auto: AutoKillSettings) async {
        await run {
            switch try await risk.prepareAutoKill(auto) {
            case .passkeyNotNeeded: _ = try await risk.setAutoKill(auto); await store.loadRiskState(); notice = "Arrêts automatiques mis à jour (aucun n’a été désactivé : pas de passkey requise)."
            case .approval(let a): sheetError = nil; sheet = .auto(a)
            }
        }
    }

    func saveLimits(mode: RiskMode, limits: EngineRiskLimits) async {
        await run {
            switch try await risk.prepareLimits(mode: mode, limits: limits) {
            case .passkeyNotNeeded: _ = try await risk.setLimits(mode: mode, limits: limits); await store.loadRiskState(); notice = "Limites \(mode == .paper ? "papier" : "réelles") enregistrées (rien n’est assoupli : pas de passkey requise)."
            case .approval(let a): sheetError = nil; sheet = .limits(a)
            }
        }
    }

    func approve() async {
        guard let sheet, model.canOperate, !approving else { return }
        approving = true; sheetError = nil
        defer { approving = false }
        do {
            switch sheet {
            case .release(let a): _ = try await risk.release(a, with: model.authenticator); notice = (a.kind == .killSwitch ? "Coupe-circuit" : "Mode lecture seule") + " levé par le serveur."
            case .limits(let a): _ = try await risk.approveLimits(a, with: model.authenticator); notice = "Limites assouplies enregistrées par le serveur."
            case .auto(let a): _ = try await risk.approveAutoKill(a, with: model.authenticator); notice = "Arrêts automatiques modifiés par le serveur."
            }
            self.sheet = nil
            await store.loadRiskState()
        } catch PasskeyError.cancelled {
        } catch {
            // the answer may have been lost after the server acted: the state is read again rather than a second signature asked
            sheetError = model.describe(error)
            await store.loadRiskState()
        }
    }

    func dismiss() { if !approving { sheet = nil; sheetError = nil } }
}

struct FutRiskView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    @State private var flow: FutRiskFlow?

    var body: some View {
        Group {
            if let flow { content(flow) } else { ProgressView() }
        }
        .sheet(item: Binding(get: { flow?.sheet }, set: { if $0 == nil { flow?.dismiss() } })) { s in
            if let flow { FutRiskSheet(model: model, flow: flow, sheet: s) }
        }
        .task { if flow == nil { flow = FutRiskFlow(model: model, store: store) }; await store.loadRiskState() }
    }

    @ViewBuilder private func content(_ flow: FutRiskFlow) -> some View {
        if let e = store.riskState.error { Banner(.danger, "État du moteur de risque indisponible : \(e)" + (store.riskState.at.map { " — ce qui suit date du \(Fmt.dateSeconds($0))" } ?? "")) }
        if let e = flow.error { Banner(.danger, e) }
        if let n = flow.notice { Banner(.info, n) }
        if let s = store.riskState.value {
            FutSwitchesCard(model: model, flow: flow, state: s)
            FutLocksCard(store: store)
            Card("Arrêt d’urgence du signataire") {
                let h = model.portfolio?.value.halted
                Label(h == true ? "ACTIF : plus rien ne peut être signé" : h == false ? "Inactif" : "État inconnu (signataire injoignable)", systemImage: h == true ? "xmark.shield.fill" : h == false ? "checkmark.shield" : "questionmark.circle")
                    .foregroundStyle(h == true ? Theme.negative : h == false ? Theme.positive : Theme.warning)
                Text("Distinct du coupe-circuit ci-dessus : il s’engage dans l’écran Sécurité et ne se lève que sur la machine du signataire.").font(.caption).foregroundStyle(.secondary)
            }
            FutAutoKillCard(model: model, flow: flow, auto: s.auto)
            HStack(alignment: .top, spacing: 16) {
                FutExposureCard(title: "Exposition — papier", mode: .paper, e: s.exposure.paper)
                FutExposureCard(title: "Exposition — testnet", mode: .testnet, e: s.exposure.liveTestnet)
                FutExposureCard(title: "Exposition — réel", mode: .mainnet, e: s.exposure.live)
            }
            Text("Les trois livres ne sont jamais additionnés.").font(.caption).foregroundStyle(.secondary)
            FutLimitsCard(model: model, flow: flow, view: s.limits.live, color: FutMode.mainnet.color, title: "Limites — ordres réels (mainnet et testnet)")
            FutLimitsCard(model: model, flow: flow, view: s.limits.paper, color: FutMode.paper.color, title: "Limites — ordres papier (simulation)")
            FutDecisionsCard(decisions: s.decisions)
        } else if store.riskState.error == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}

// MARK: switches

private struct FutSwitchesCard: View {
    let model: AppModel
    let flow: FutRiskFlow
    let state: RiskState
    @State private var reason = ""
    @State private var confirm: RiskSwitchKind?

    var body: some View {
        Card("Commutateurs globaux") {
            row(.killSwitch, state.switches.killSwitch, title: "Coupe-circuit (kill switch)", on: "ENGAGÉ : aucun nouvel ordre n’ajoute de risque, sur toutes les plateformes et dans tous les modes. Annulations et ordres strictement réducteurs passent.", off: "Non engagé.")
            Divider()
            row(.readOnly, state.switches.readOnly, title: "Mode lecture seule", on: "ENGAGÉ : seules les annulations passent.", off: "Non engagé.")
            Divider()
            HStack {
                TextField("Raison (facultative, jointe à l’engagement)", text: $reason).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                if flow.busy { ProgressView().controlSize(.small) }
            }
            Text("Engager est immédiat et ne demande pas de passkey. Lever un commutateur redonne de l’autorité : votre passkey signe la levée de l’engagement exact affiché ici.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func row(_ kind: RiskSwitchKind, _ s: RiskSwitch, title: String, on: String, off: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: s.on ? "power.circle.fill" : "power.circle").font(.title2).foregroundStyle(s.on ? Theme.negative : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(s.on ? on : off).font(.callout).foregroundStyle(s.on ? Theme.negative : .secondary).fixedSize(horizontal: false, vertical: true)
                if s.on { Text("Depuis \(Fmt.dateSeconds(s.engagedAt)) · par \(s.by?.label ?? "inconnu")" + (s.reason.map { $0.isEmpty ? "" : " · raison : \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Spacer()
            if s.on {
                Button("Lever (passkey)…") { Task { await flow.prepareRelease(kind) } }.disabled(!model.canOperate || flow.busy)
            } else {
                Button(kind == .killSwitch ? "Engager le coupe-circuit…" : "Engager la lecture seule…", role: .destructive) { confirm = kind }.disabled(!model.canOperate || flow.busy)
                    .confirmationDialog(kind == .killSwitch ? "Engager le coupe-circuit global ?" : "Engager le mode lecture seule ?", isPresented: Binding(get: { confirm == kind }, set: { if !$0 { confirm = nil } })) {
                        Button("Engager maintenant", role: .destructive) { Task { await flow.engage(kind, reason: reason) } }
                    } message: { Text(kind == .killSwitch ? "Effet immédiat pour tous les modes et toutes les plateformes. Les positions ne sont pas clôturées. Le lever demandera votre passkey." : "Effet immédiat : seules les annulations passeront. Le lever demandera votre passkey.") }
            }
        }
    }
}

private struct FutAutoKillCard: View {
    let model: AppModel
    let flow: FutRiskFlow
    let auto: AutoKillSettings
    var body: some View {
        Card("Arrêts automatiques") {
            toggle("Perte totale maximale atteinte", \.totalLoss)
            toggle("Baisse maximale depuis le sommet (drawdown) atteinte", \.drawdown)
            toggle("Perte quotidienne maximale atteinte", \.dailyLoss)
            Text("Quand la limite correspondante est franchie, le serveur engage lui-même le coupe-circuit. Activer un arrêt est libre ; en désactiver un exige votre passkey.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func toggle(_ label: String, _ key: WritableKeyPath<AutoKillSettings, Bool>) -> some View {
        Toggle(label, isOn: Binding(get: { auto[keyPath: key] }, set: { v in var next = auto; next[keyPath: key] = v; Task { await flow.setAuto(next) } }))
            .disabled(!model.canOperate || flow.busy)
    }
}

// MARK: exposure

private struct FutExposureCard: View {
    let title: String
    let mode: FutMode
    let e: RiskExposure
    var body: some View {
        Card(title, trailing: AnyView(FutModeBadge(mode: mode))) {
            if let err = e.error { Banner(.warning, "Livre illisible : \(err)") }
            FutStatGrid(minimum: 120) {
                FutStat("Valeur", e.isReadable ? FutNum.usd(e.equity) : nil)
                FutStat("Exposition brute", e.isReadable ? FutNum.usd(e.grossExposure) : nil)
                FutStat("Levier du livre", e.isReadable ? (e.leverage.map { "\(FutNum.exact($0, maxFraction: 2))×" } ?? "—") : nil)
                FutStat("Sommet de valeur", e.isReadable ? FutNum.usd(e.peakEquity) : nil)
            }
            ForEach(e.byAsset ?? [], id: \.asset) { a in
                HStack { Text(a.asset).fontWeight(.medium); Spacer(); Text("long \(FutNum.usd(a.long)) · short \(FutNum.usd(a.short)) · net \(FutNum.usd(a.net))").font(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }
            ForEach(e.positions ?? [], id: \.instrument) { p in
                HStack { FutSideText(side: p.side); Text(p.instrument).font(.callout); Spacer(); Text("\(FutNum.usd(p.notional))" + (p.liquidationDistanceBps.map { " · liq. à \(FutNum.exact($0, maxFraction: 0)) pb" } ?? "")).font(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }
            if let errs = e.errors, !errs.isEmpty { Text("Chiffres PARTIELS — sources illisibles : \(errs.joined(separator: " ; "))").font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true) }
            if let t = FutNum.ms(e.ts) { Text("Calculé \(Fmt.relative(t))").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: limits

private struct FutLimitsCard: View {
    let model: AppModel
    let flow: FutRiskFlow
    let view: RiskLimitsView
    let color: Color
    let title: String
    @State private var editing = false
    @State private var draft: [String: String] = [:]

    static let decimals: [(String, String, WritableKeyPath<EngineRiskLimits, String?>)] = [
        ("maxOrderNotional", "Notionnel max par ordre ($)", \.maxOrderNotional), ("maxDailyNotional", "Notionnel max par jour ($)", \.maxDailyNotional),
        ("maxOrderLeverage", "Levier max d’un ordre", \.maxOrderLeverage), ("maxAccountLeverage", "Levier max du compte", \.maxAccountLeverage),
        ("maxGrossExposure", "Exposition brute max ($)", \.maxGrossExposure), ("maxNetExposure", "Exposition nette max ($)", \.maxNetExposure),
        ("maxDailyLoss", "Perte quotidienne max ($)", \.maxDailyLoss), ("maxTotalLoss", "Perte totale max ($)", \.maxTotalLoss), ("maxDrawdownBps", "Drawdown max (pb)", \.maxDrawdownBps),
        ("maxVenueCollateralShareBps", "Part max du collatéral par plateforme (pb)", \.maxVenueCollateralShareBps), ("minLiquidationDistanceBps", "Distance min. à la liquidation (pb)", \.minLiquidationDistanceBps),
        ("maxSlippageBps", "Glissement max (pb)", \.maxSlippageBps), ("maxSourceDeviationBps", "Écart max entre sources de prix (pb)", \.maxSourceDeviationBps),
    ]
    static let integers: [(String, String, WritableKeyPath<EngineRiskLimits, Int?>)] = [
        ("maxOrdersPerMinute", "Ordres par minute", \.maxOrdersPerMinute), ("maxOrdersPerHour", "Ordres par heure", \.maxOrdersPerHour), ("maxOrdersPerDay", "Ordres par jour", \.maxOrdersPerDay),
        ("maxBookAgeMs", "Âge max du carnet (ms)", \.maxBookAgeMs), ("minPriceSources", "Sources de prix minimales", \.minPriceSources),
    ]

    static func lines(_ l: EngineRiskLimits) -> [(String, String)] {
        let o = (try? JSONValue.from(l))?.objectValue ?? [:]
        return EngineRiskLimits.fieldNames.compactMap { k in o[k].flatMap { $0.isNull ? nil : (k, $0.displayText) } }
    }

    /// The edited set: the stored one with the scalar fields replaced; keyed limits and lists are kept untouched.
    private var edited: EngineRiskLimits? {
        var l = view.stored
        for (k, _, path) in Self.decimals {
            let t = (draft[k] ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            if t.isEmpty { l[keyPath: path] = nil } else { guard let d = VenueDecimal(t), !d.isNegative else { return nil }; l[keyPath: path] = d.description }
        }
        for (k, _, path) in Self.integers {
            let t = (draft[k] ?? "").trimmingCharacters(in: .whitespaces)
            if t.isEmpty { l[keyPath: path] = nil } else { guard let n = Int(t), n >= 0 else { return nil }; l[keyPath: path] = n }
        }
        return l
    }

    var body: some View {
        Card(title, trailing: AnyView(Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true))) {
            if view.ownerOrdersRefused == true || !view.missing.isEmpty {
                Banner(.warning, "Limites de capital absentes pour vos propres ordres : \(view.missing.joined(separator: ", ")). Tant qu’elles manquent, vos ordres qui ajoutent du risque dans ce mode sont refusés.")
            }
            if let m = view.missingForAutomation, !m.isEmpty { Text("Absentes pour les clés d’API et les agents : \(m.joined(separator: ", "))" + (view.automationOrdersRefused == true ? " — leurs ordres sont refusés." : "")).font(.callout).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true) }
            HStack(alignment: .top, spacing: 20) {
                set("En vigueur pour vos ordres", view.effectiveOwner ?? view.effective)
                set("En vigueur pour clés d’API et agents", view.effective)
                set("Enregistrées par vous", view.stored)
            }
            if let seed = view.seed { Text("Limites reprises de vos autorisations antérieures (\(seed.sources.map { "\($0.field) ← \($0.from)" }.joined(separator: ", ")))" + (seed.notSeeded.isEmpty ? "" : " ; non reprises : \(seed.notSeeded.joined(separator: ", "))")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if !view.storedUnknownFields.isEmpty {
                Banner(.warning, "Le serveur a enregistré des limites que cette version de l’app ne connaît pas (\(view.storedUnknownFields.joined(separator: ", "))). L’édition est désactivée ici : enregistrer un nouvel ensemble les supprimerait.")
            } else if editing {
                Divider()
                Text("Champ vide = pas de limite enregistrée. Resserrer est immédiat ; tout assouplissement (valeur plus large ou limite retirée) vous sera montré puis demandera votre passkey. Les limites par actif, par plateforme et les listes ne sont pas modifiées ici et sont conservées.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], alignment: .leading, spacing: 8) {
                    ForEach(Self.decimals, id: \.0) { f in field(f.0, f.1) }
                    ForEach(Self.integers, id: \.0) { f in field(f.0, f.1) }
                }
                HStack {
                    if edited == nil { Text("Une valeur n’est pas un nombre valide.").font(.callout).foregroundStyle(Theme.negative) }
                    Spacer()
                    Button("Abandonner") { editing = false }
                    Button("Enregistrer les limites…") { if let l = edited { Task { await flow.saveLimits(mode: view.mode, limits: l); if flow.error == nil { editing = false } } } }
                        .buttonStyle(.borderedProminent).disabled(edited == nil || edited == view.stored || !model.canOperate || flow.busy)
                }
            } else {
                HStack { Spacer(); Button("Modifier les limites enregistrées…") { load(); editing = true }.disabled(!model.canOperate) }
            }
        }
    }

    private func load() {
        var d: [String: String] = [:]
        for (k, _, path) in Self.decimals { d[k] = view.stored[keyPath: path] ?? "" }
        for (k, _, path) in Self.integers { d[k] = view.stored[keyPath: path].map(String.init) ?? "" }
        draft = d
    }
    private func field(_ key: String, _ label: String) -> some View {
        HStack { Text(label).font(.callout).frame(maxWidth: .infinity, alignment: .leading); TextField("aucune", text: Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0 })).textFieldStyle(.roundedBorder).frame(width: 110) }
    }
    private func set(_ title: String, _ l: EngineRiskLimits) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout.weight(.medium))
            let rows = Self.lines(l)
            if rows.isEmpty { Text("aucune limite").font(.callout).foregroundStyle(.secondary) }
            ForEach(rows, id: \.0) { r in
                HStack(alignment: .firstTextBaseline) { Text(r.0).font(.caption).foregroundStyle(.secondary); Spacer(minLength: 6); Text(r.1).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(3).multilineTextAlignment(.trailing) }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: decisions

private struct FutDecisionsCard: View {
    let decisions: [RiskDecision]
    var body: some View {
        Card("Journal du moteur de risque") {
            if decisions.isEmpty { Text("Aucune décision enregistrée.").foregroundStyle(.secondary) } else {
                Table(decisions) {
                    TableColumn("Date") { d in Text(Fmt.dateSeconds(d.date)).font(.callout) }.width(min: 130, ideal: 150)
                    TableColumn("Décision") { d in Text(d.decision + (d.preview ? " (aperçu)" : "")).fontWeight(.medium).foregroundStyle(d.denied ? Theme.negative : Theme.positive) }.width(min: 90, ideal: 110)
                    TableColumn("Objet") { d in Text("\(d.kind) · \(d.mode) · \(d.venue)" + (d.instrument.map { " · \($0)" } ?? "") + (d.reducing ? " · réducteur" : "")).font(.callout) }.width(min: 200, ideal: 280)
                    TableColumn("Auteur") { d in Text(d.principal.label).font(.caption).foregroundStyle(.secondary) }.width(min: 90, ideal: 130)
                    TableColumn("Contrôles en échec") { d in
                        let t = d.failing.map { f in "\(f.id) : \(f.detail)" + (f.observed.map { " — observé \($0)" } ?? "") + (f.limit.map { ", limite \($0)" } ?? "") }.joined(separator: " ; ")
                        Text(t.isEmpty ? "—" : t).font(.caption).lineLimit(2).help(t)
                    }.width(min: 200, ideal: 360)
                }.frame(height: CGFloat(min(decisions.count, 12)) * 30 + 36)
                Text("Chaque évaluation est consignée, aperçus compris ; un aperçu ne place rien.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: review sheet

private struct FutRiskSheet: View {
    let model: AppModel
    @Bindable var flow: FutRiskFlow
    let sheet: FutRiskFlow.Sheet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FutSheetHeader(title: title)
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 14) { content }.padding(20) }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let e = flow.sheetError { Banner(.danger, e) }
                HStack {
                    Button("Fermer sans approuver") { flow.dismiss() }.disabled(flow.approving)
                    Spacer()
                    if flow.approving { ProgressView().controlSize(.small) }
                    Button { Task { await flow.approve() } } label: { Label("Approuver avec la passkey", systemImage: "touchid") }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(flow.approving || !model.canOperate)
                }
            }.padding(16)
        }
        .frame(width: 700, height: 680).interactiveDismissDisabled()
    }

    private var title: String {
        switch sheet {
        case .release(let a): a.kind == .killSwitch ? "Lever le coupe-circuit" : "Lever le mode lecture seule"
        case .limits(let a): "Assouplir les limites \(a.mode == .paper ? "papier" : "réelles")"
        case .auto: "Désactiver un arrêt automatique"
        }
    }

    @ViewBuilder private var content: some View {
        switch sheet {
        case .release(let a):
            let i = a.intent
            Banner(.warning, a.kind == .killSwitch ? "Lever le coupe-circuit permet de nouveau à tous les ordres d’ajouter du risque, dans tous les modes." : "Lever le mode lecture seule permet de nouveau les ordres.")
            ReviewLines(lines: [
                .init(label: "Type d’opération", value: "Levée d’un commutateur global", style: .strong),
                .init(label: "Commutateur", value: i.kind.rawValue, style: .strong),
                .init(label: "Engagé le", value: FutNum.ms(i.engagedAt).map { Fmt.dateSeconds($0) } ?? "—"),
                .init(label: "Engagé par", value: i.engagedBy ?? "—"),
                .init(label: "Raison de l’engagement", value: i.reason.map { $0.isEmpty ? "(vide)" : $0 } ?? "—"),
                .init(label: "Nonce", value: i.nonce),
            ])
            BindingProof(digest: a.approval.digest, expiry: i.expiry)
        case .limits(let a):
            Banner(.warning, "Ces champs deviennent PLUS LARGES : \(a.loosened.joined(separator: ", ")).")
            ReviewLines(lines: [.init(label: "Type d’opération", value: "Nouvel ensemble de limites — mode \(a.mode.rawValue)", style: .strong)]
                        + FutLimitsCard.lines(a.limits).map { ReviewLine(label: $0.0, value: $0.1, style: a.loosened.contains($0.0) ? .warning : .normal) }
                        + [.init(label: "Nonce", value: a.intent.nonce)])
            Text("L’ensemble ci-dessus REMPLACE celui qui est enregistré : une limite qui n’y figure pas n’existe plus.").font(.callout).foregroundStyle(.secondary)
            BindingProof(digest: a.approval.digest, expiry: a.intent.expiry)
        case .auto(let a):
            Banner(.warning, "Arrêts désactivés par ce changement : \(a.loosened.joined(separator: ", ")).")
            ReviewLines(lines: [
                .init(label: "Type d’opération", value: "Réglage des arrêts automatiques", style: .strong),
                .init(label: "Perte totale", value: a.auto.totalLoss ? "actif" : "DÉSACTIVÉ", style: a.auto.totalLoss ? .normal : .warning),
                .init(label: "Drawdown", value: a.auto.drawdown ? "actif" : "DÉSACTIVÉ", style: a.auto.drawdown ? .normal : .warning),
                .init(label: "Perte quotidienne", value: a.auto.dailyLoss ? "actif" : "DÉSACTIVÉ", style: a.auto.dailyLoss ? .normal : .warning),
                .init(label: "Nonce", value: a.intent.nonce),
            ])
            BindingProof(digest: a.approval.digest, expiry: a.intent.expiry)
        }
    }
}
