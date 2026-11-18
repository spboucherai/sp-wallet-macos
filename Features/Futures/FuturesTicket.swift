// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Futures/FuturesTicket.swift
// Description: The order ticket and its mandatory pre-trade risk panel. An order can only be placed (paper) or proposed (live) on a FRESH preview of the backend for exactly the form on screen: notional, leverage, required margin, estimated liquidation price, fees, funding, collateral at stake and the risk engine's verdict. Leverage never defaults to the venue maximum: it is the account's current setting, or 1× when there is none. Paper orders go to the paper engine and are labelled SIMULATION; live orders go through FutLiveOps (proposal → verified venue order → review sheet → passkey).
import SwiftUI
import SPWalletCore

@MainActor @Observable final class FutTicketFlow {
    /// A preview is only good for the form it was computed for, for a short time.
    struct Preview {
        let fingerprint: String
        let at: Date
        let mode: FutMode
        var paper: PaperOrderPreview?
        var live: LiveOrderPreview?
        var verdict: DerivRiskVerdict? { paper?.risk ?? live?.risk }
    }
    static let previewLifetime: TimeInterval = 30

    let model: AppModel
    let store: FuturesStore
    let ops: FutLiveOps

    var side: DerivOrderSide = .buy
    var type: DerivOrderType = .limit
    var size = ""
    var price = ""
    var slippageBps = "50"
    var reduceOnly = false
    var tif: DerivTimeInForce = .gtc
    /// Paper only. Nil keeps the paper account's current setting for the instrument.
    var leverageChange: Int?

    private(set) var preview: Preview?
    private(set) var previewing = false
    private(set) var placing = false
    private(set) var placement: PaperPlacement?
    var error: String?
    @ObservationIgnored private var idempotency: (key: String, fingerprint: String)?

    init(model: AppModel, store: FuturesStore, ops: FutLiveOps) { self.model = model; self.store = store; self.ops = ops }

    // MARK: what the venue supports

    var venue: DerivVenue? { store.instrument.flatMap { store.venueInfo($0.venue) } }
    var orderTypes: [DerivOrderType] {
        let served = venue?.capabilities?.orderTypes ?? []
        let known: [DerivOrderType] = [.limit, .market]
        let ok = known.filter { served.contains($0.rawValue) }
        return ok.isEmpty ? known : ok
    }
    var timesInForce: [DerivTimeInForce] {
        let served = venue?.capabilities?.tif ?? []
        let known: [DerivTimeInForce] = [.gtc, .ioc, .alo]
        let ok = known.filter { served.contains($0.rawValue) }
        return ok.isEmpty ? [.gtc, .ioc] : ok
    }

    // MARK: leverage (paper)

    /// The paper account's present leverage setting for the instrument, as served.
    var paperLeverageSetting: String? {
        guard let id = store.instrumentId, let s = store.paperAccount?.settings else { return nil }
        return s.leverageByInstrument?[id] ?? s.leverage
    }
    /// Where a leverage selector starts: the account's current setting, else 1× — never the maximum.
    var leverageStart: Int { paperLeverageSetting.flatMap { FutNum.d($0) }.map { max(1, Int($0)) } ?? 1 }
    var leverageCeiling: Int {
        let venueMax = store.instrument.flatMap { FutNum.d($0.maxLeverage) }.map { Int($0) } ?? 1
        let policyMax = store.paperAccount.flatMap { FutNum.d($0.policy.maxLeverage) }.map { Int($0) } ?? venueMax
        return max(1, min(venueMax, policyMax))
    }

    // MARK: form

    private var accountKey: String {
        switch store.mode { case .paper: store.paperId?.rawValue ?? ""; default: store.liveAccount?.id.rawValue ?? "" }
    }
    var fingerprint: String {
        "\(store.mode.rawValue)|\(accountKey)|\(store.instrumentId ?? "")|\(side.rawValue)|\(type.rawValue)|\(FutNum.input(size) ?? size)|\(type == .limit ? (FutNum.input(price) ?? price) : "")|\(type == .market ? slippageBps : "")|\(reduceOnly)|\(effectiveTif.rawValue)|\(leverageChange.map(String.init) ?? "")"
    }
    var effectiveTif: DerivTimeInForce { type == .market ? .ioc : tif }
    private var slippage: Int? { Int(slippageBps.trimmingCharacters(in: .whitespaces)).flatMap { (1...500).contains($0) ? $0 : nil } }

    var formProblem: String? {
        guard let inst = store.instrument else { return "Choisissez un instrument." }
        if inst.status == "halted" { return "Instrument suspendu par la plateforme." }
        if accountKey.isEmpty { return store.mode == .paper ? "Créez ou choisissez un compte papier (onglet Compte)." : "Aucun compte de plateforme dans ce mode (onglet Plateforme et collatéral)." }
        if store.mode == .paper, let a = store.paperAccount, a.venue != inst.venue { return "Ce compte papier simule \(a.venue) ; l’instrument est sur \(inst.venue)." }
        if store.mode != .paper, let a = store.liveAccount, a.venue != inst.venue { return "Le compte réel est sur \(a.venue) ; l’instrument est sur \(inst.venue)." }
        guard FutNum.input(size) != nil else { return size.isEmpty ? "Entrez une taille en \(inst.base)." : "Taille invalide." }
        if type == .limit, FutNum.input(price) == nil { return price.isEmpty ? "Entrez un prix limite." : "Prix invalide." }
        if type == .market, slippage == nil { return "Borne de glissement : un entier de 1 à 500 points de base." }
        return nil
    }

    private func paperRequest() -> PaperOrderRequest? {
        guard let id = store.instrumentId, let s = FutNum.input(size) else { return nil }
        return PaperOrderRequest(instrument: id, side: side, type: type, size: s, price: type == .limit ? FutNum.input(price) : nil, triggerPrice: nil, reduceOnly: reduceOnly, tif: effectiveTif,
                                 leverage: leverageChange.map(String.init), slippageBps: type == .market ? slippage : nil)
    }
    private func liveRequest() -> LiveOrderRequest? {
        guard let id = store.instrumentId, let s = FutNum.input(size) else { return nil }
        return LiveOrderRequest(instrument: id, side: side, type: type, size: s, price: type == .limit ? FutNum.input(price) : nil, triggerPrice: nil, reduceOnly: reduceOnly, tif: effectiveTif, slippageBps: type == .market ? slippage : nil)
    }

    // MARK: preview

    func isFresh(_ p: Preview?, at now: Date) -> Bool {
        guard let p else { return false }
        return p.fingerprint == fingerprint && p.mode == store.mode && now.timeIntervalSince(p.at) < Self.previewLifetime
    }
    func canPlace(at now: Date) -> Bool { isFresh(preview, at: now) && preview?.verdict?.ok == true && model.canOperate && !placing && !ops.isBusy }

    /// Asks the backend what this exact order would do. Nothing is stored, nothing is sent to a venue.
    func runPreview() async {
        guard formProblem == nil, model.canOperate, !previewing else { return }
        previewing = true; error = nil; placement = nil
        defer { previewing = false }
        let fp = fingerprint, mode = store.mode
        do {
            switch mode {
            case .paper:
                guard let id = store.paperId, let req = paperRequest() else { return }
                let p = try await store.deriv.previewPaperOrder(id, order: req)
                preview = Preview(fingerprint: fp, at: Date(), mode: mode, paper: p, live: nil)
            case .testnet, .mainnet:
                guard let a = store.liveAccount, let req = liveRequest() else { return }
                let p = try await store.live.previewOrder(a.id, order: req)
                preview = Preview(fingerprint: fp, at: Date(), mode: mode, paper: nil, live: p)
            }
        } catch { preview = nil; self.error = model.describe(error) }
    }

    // MARK: placing

    func place() async {
        guard canPlace(at: Date()) else { return }
        switch store.mode {
        case .paper: await placePaper()
        case .testnet, .mainnet:
            guard let req = liveRequest(), store.liveActionsAllowed, store.liveAccount?.tradable == true else { return }
            placing = true; defer { placing = false }
            await ops.propose(req)
            preview = nil
        }
    }

    private func placePaper() async {
        guard let id = store.paperId, let req = paperRequest() else { return }
        placing = true; error = nil
        defer { placing = false }
        let fp = fingerprint
        if idempotency?.fingerprint != fp { idempotency = (APIClient.newIdempotencyKey(), fp) }
        do {
            let r = try await store.deriv.placePaperOrder(id, order: req, idempotencyKey: idempotency!.key)
            placement = r; preview = nil; idempotency = nil
            await store.refreshAccount()
        } catch let e as APIError where e.isOffline {
            // the answer was lost: the same key answers the same order, so a retry cannot place a second one
            self.error = "Réponse perdue. Réessayez : la même clé d’idempotence renverra le même ordre simulé, jamais un second."
        } catch { idempotency = nil; preview = nil; self.error = model.describe(error) }
    }

    func clearResult() { placement = nil; error = nil }
}

extension FuturesStore {
    /// Real operations are only offered once the server's jurisdiction notice was displayed and the owner ticked it.
    var liveActionsAllowed: Bool { jurisdictionRead && jurisdiction.value != nil }

    /// Why NEW risk cannot be taken on the live account of the current mode, each in the server's words where it gave some. Empty = nothing blocks.
    var liveBlockers: [String] {
        guard mode != .paper else { return [] }
        guard let a = liveAccount else {
            return [liveAccounts.error.map { "Comptes de plateforme illisibles : \($0)" } ?? "Aucun compte \(mode == .mainnet ? "réel" : "testnet") n’existe encore sur Hyperliquid."]
        }
        var out: [String] = []
        if a.isMainnet, !a.mainnetEnabled { out.append(config.value?.mainnet?.reason ?? "Le serveur garde le mainnet fermé (deriv_live_mainnet).") }
        if a.mode == .readOnly { out.append("Ce compte est en lecture seule : la clé de négociation n’a pas été autorisée par votre passkey.") }
        if let auth = a.authorization, auth.expired { out.append("L’autorisation de négociation est expirée depuis le \(Fmt.date(auth.expiresAt)).") }
        if let h = a.halted { out.append("Nouveaux ordres arrêtés sur ce compte : \(h)") }
        if !a.tradable, out.isEmpty { out.append("Le serveur indique que ce compte ne peut pas prendre de nouveau risque pour l’instant.") }
        return out
    }
}

// MARK: - view

struct FutTicketView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    let ops: FutLiveOps
    @Bindable var flow: FutTicketFlow
    let go: (FuturesView.Tab) -> Void
    @State private var leverageForm = false
    @State private var liveLeverage = 1
    @State private var liveMarginMode: DerivMarginMode = .cross

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let v = flow.venue, let r = v.restriction {
                Card("Ordre") { Banner(.warning, "Données de marché seulement sur \(v.name) : aucun compte, aucun ordre, aucun compte papier. \(r)") }
            } else if let v = flow.venue, !accountPossible(on: v) {
                // the server offers no account of this mode on this venue: no order control at all, only the reason
                Card("Ordre", trailing: AnyView(FutModeBadge(mode: mode))) {
                    Banner(.info, mode == .paper
                           ? "Le serveur n’offre pas de compte papier sur \(v.name) : aucun ordre simulé n’est possible ici."
                           : store.config.value == nil
                             ? "Configuration des comptes réels illisible\(store.config.error.map { " (\($0))" } ?? "") : aucun contrôle d’ordre réel n’est proposé."
                             : "Le serveur n’ouvre pas de compte \(mode == .mainnet ? "réel" : "testnet") sur \(v.name) : données de marché seulement ici." + (v.id == "gmx" ? " L’état de GMX, ses verrous et la réduction de positions sont dans l’onglet GMX v2." : ""))
                    if v.id == "gmx" { Button("Ouvrir GMX v2") { go(.gmx) } }
                }
            } else {
                formCard
                if let p = flow.preview { FutRiskPanel(store: store, flow: flow, preview: p) }
                resultCard
            }
        }
    }

    /// Whether the server can hold an account of the current mode on this venue — its own lists, never a hard-coded one.
    private func accountPossible(on v: DerivVenue) -> Bool {
        guard let net = mode.network else { return v.paper == true }
        return store.config.value?.venues.contains { $0.venue == v.id && $0.networks.contains(net) } ?? false
    }

    private var mode: FutMode { store.mode }
    private var blockers: [String] { store.liveBlockers }

    private var formCard: some View {
        Card("Ordre", trailing: AnyView(FutModeBadge(mode: mode))) {
            accountLine
            if mode != .paper, !blockers.isEmpty {
                // the server refuses new risk here: no order form at all, only the reasons
                ForEach(blockers, id: \.self) { Banner(.warning, $0) }
                Text("Les contrôles d’ordre sont absents tant que le serveur ne permet pas de nouveau risque sur ce compte. Les annulations et les clôtures réductrices restent disponibles dans l’onglet Compte.").font(.caption).foregroundStyle(.secondary)
                Button("Ouvrir Plateforme et collatéral") { go(.venue) }
            } else {
                Picker("Sens", selection: $flow.side) { Text("Acheter / long").tag(DerivOrderSide.buy); Text("Vendre / short").tag(DerivOrderSide.sell) }.pickerStyle(.segmented).labelsHidden()
                Picker("Type", selection: $flow.type) { ForEach(flow.orderTypes, id: \.self) { Text($0 == .limit ? "Limite" : "Au marché").tag($0) } }.pickerStyle(.segmented).labelsHidden()
                HStack { TextField("Taille", text: $flow.size, prompt: Text("0.0")).textFieldStyle(.roundedBorder); Text(store.instrument?.base ?? "").foregroundStyle(.secondary).frame(width: 60, alignment: .leading) }
                if let s = FutNum.d(FutNum.input(flow.size)), let m = FutNum.d(store.instrumentId.flatMap { store.price($0).mark }) {
                    Text("Notionnel au prix affiché : \(FutNum.approx(s * m)) $ (indicatif — l’aperçu du serveur fait foi)").font(.caption).foregroundStyle(.secondary)
                }
                if flow.type == .limit {
                    HStack { TextField("Prix limite", text: $flow.price, prompt: Text(store.instrumentId.flatMap { store.price($0).mark } ?? "0.0")).textFieldStyle(.roundedBorder); Text(store.instrument?.quote ?? "").foregroundStyle(.secondary).frame(width: 60, alignment: .leading) }
                    Picker("Durée de validité", selection: $flow.tif) {
                        ForEach(flow.timesInForce, id: \.self) { Text($0 == .gtc ? "Jusqu’à annulation (GTC)" : $0 == .ioc ? "Immédiat ou annulé (IOC)" : "Maker seulement (ALO)").tag($0) }
                    }
                } else {
                    HStack { TextField("Glissement maximal", text: $flow.slippageBps).textFieldStyle(.roundedBorder).frame(width: 90); Text("points de base par rapport au carnet (1 à 500)").font(.callout).foregroundStyle(.secondary) }
                    Text("Un ordre au marché est envoyé comme un ordre limite immédiat (IOC) au pire prix que cette borne autorise.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Réduction seule (ne peut qu’alléger une position)", isOn: $flow.reduceOnly).toggleStyle(.checkbox)
                Divider()
                leverageSection
                Divider()
                actions
            }
        }
    }

    @ViewBuilder private var accountLine: some View {
        switch mode {
        case .paper:
            if let a = store.paperAccount { Text("Compte papier « \(a.label) » — collatéral libre simulé : \(FutNum.usd(a.state.freeCollateral))").font(.callout).foregroundStyle(.secondary) }
            else { Text(store.paperAccounts.error.map { "Comptes papier illisibles : \($0)" } ?? "Aucun compte papier.").font(.callout).foregroundStyle(.secondary); Button("Créer un compte papier") { go(.account) } }
        case .testnet, .mainnet:
            if let a = store.liveAccount {
                let free = store.currentLiveDetail?.venueState.state?.freeCollateral
                Text("Compte \(a.label) (\(a.network)) \(Fmt.short(a.account)) — collatéral libre : \(free.map { FutNum.usd($0) } ?? "indisponible")").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var leverageSection: some View {
        if mode == .paper {
            let current = flow.paperLeverageSetting
            HStack {
                Text("Levier").foregroundStyle(.secondary)
                Spacer()
                Text(flow.leverageChange.map { "\($0)× (nouveau réglage)" } ?? (current.map { "\(FutNum.exact($0))× (réglage actuel du compte)" } ?? "réglage du compte"))
            }
            Toggle("Modifier le levier de cet instrument avec cet ordre", isOn: Binding(get: { flow.leverageChange != nil }, set: { flow.leverageChange = $0 ? min(flow.leverageStart, flow.leverageCeiling) : nil })).toggleStyle(.checkbox)
            if let l = flow.leverageChange {
                Stepper(value: Binding(get: { l }, set: { flow.leverageChange = min(max(1, $0), flow.leverageCeiling) }), in: 1...flow.leverageCeiling) { Text("\(l)×  (maximum permis ici : \(flow.leverageCeiling)×)") }
                if l > flow.leverageStart { Text("Un levier plus élevé rapproche le prix de liquidation : une variation plus faible suffit à perdre la marge.").font(.caption).foregroundStyle(Theme.warning) }
            }
        } else {
            let pos = store.currentLiveDetail?.venueState.positions.first { $0.instrument == store.instrumentId }
            let current = pos.map { "\($0.leverage)× (\($0.marginMode))" } ?? flow.preview?.live?.estimate.flatMap { e in e.leverage.map { "\($0)×" + (e.marginMode.map { " (\($0))" } ?? "") } }
            HStack { Text("Levier (réglage de la plateforme)").foregroundStyle(.secondary); Spacer(); Text(current ?? "lu avec l’aperçu") }
            DisclosureGroup("Changer le levier de cet instrument…", isExpanded: $leverageForm) {
                VStack(alignment: .leading, spacing: 8) {
                    let ceiling = max(1, min(store.instrument.flatMap { FutNum.d($0.maxLeverage) }.map { Int($0) } ?? 1, store.liveAccount?.authorization?.policy.maxLeverage ?? 1))
                    Stepper(value: $liveLeverage, in: 1...ceiling) { Text("\(liveLeverage)×  (maximum de votre autorisation : \(ceiling)×)") }
                    Picker("Marge", selection: $liveMarginMode) { Text("Croisée").tag(DerivMarginMode.cross); Text("Isolée").tag(DerivMarginMode.isolated) }.pickerStyle(.segmented)
                    Text("Le levier est un réglage du compte sur la plateforme : il s’applique aussi à la position déjà ouverte sur cet instrument. Le changement est approuvé par votre passkey.").font(.caption).foregroundStyle(.secondary)
                    Button("Préparer le changement de levier…") { if let id = store.instrumentId { Task { await ops.proposeLeverage(instrument: id, leverage: liveLeverage, marginMode: liveMarginMode) } } }
                        .disabled(!model.canOperate || ops.isBusy || !store.liveActionsAllowed || store.instrumentId == nil)
                }.padding(.top, 6)
            }
            .onChange(of: leverageForm) { _, open in
                // the selector starts from the venue's present setting when it is known, from 1× otherwise — never from the maximum
                if open { liveLeverage = pos.flatMap { FutNum.d($0.leverage) }.map { max(1, Int($0)) } ?? 1; if let m = pos.flatMap({ DerivMarginMode(rawValue: $0.marginMode) }) { liveMarginMode = m } }
            }
        }
    }

    private var actions: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let fresh = flow.isFresh(flow.preview, at: ctx.date)
            VStack(alignment: .leading, spacing: 8) {
                if let p = flow.formProblem, !flow.size.isEmpty || !flow.price.isEmpty || store.instrument == nil { Text(p).font(.callout).foregroundStyle(.secondary) }
                if let e = flow.error { Banner(.danger, e) }
                if let e = ops.error, mode != .paper { Banner(.danger, e) }
                if mode != .paper, !store.liveActionsAllowed { Text("Lisez et cochez l’avis de juridiction (onglet Plateforme et collatéral) avant toute opération réelle.").font(.caption).foregroundStyle(Theme.warning) }
                HStack {
                    Button { Task { await flow.runPreview() } } label: { Label(flow.preview == nil ? "Calculer l’aperçu des risques" : "Recalculer l’aperçu", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                        .disabled(flow.formProblem != nil || !model.canOperate || flow.previewing)
                    if flow.previewing || flow.placing || (ops.isBusy && mode != .paper) { ProgressView().controlSize(.small) }
                    Spacer()
                }
                Button { Task { await flow.place() } } label: {
                    Text(mode == .paper ? "Placer l’ordre SIMULÉ" : mode == .testnet ? "Préparer l’ordre TESTNET…" : "Préparer l’ordre RÉEL…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(mode.color).controlSize(.large)
                .disabled(!flow.canPlace(at: ctx.date) || (mode != .paper && !store.liveActionsAllowed))
                Text(placeHint(fresh: fresh, at: ctx.date)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func placeHint(fresh: Bool, at now: Date) -> String {
        if flow.preview == nil { return "Le bouton reste désactivé tant qu’aucun aperçu des risques n’a été calculé par le serveur pour cet ordre exact." }
        if !fresh { return "L’aperçu ne correspond plus au formulaire ou date de plus de \(Int(FutTicketFlow.previewLifetime)) s : recalculez-le." }
        if flow.preview?.verdict?.ok != true { return "Le moteur de risque refuse cet ordre : il ne peut pas être placé." }
        let left = Int(FutTicketFlow.previewLifetime - now.timeIntervalSince(flow.preview?.at ?? now))
        return mode == .paper ? "Aperçu valide encore \(left) s. L’ordre sera exécuté par le moteur papier : aucun fonds réel."
            : "Aperçu valide encore \(left) s. « Préparer » n’envoie rien : l’ordre exact vous est montré, puis approuvé par votre passkey."
    }

    @ViewBuilder private var resultCard: some View {
        if mode == .paper, let r = flow.placement {
            Card("Résultat de l’ordre", trailing: AnyView(ProvenanceTag(p: .simulated, text: "SIMULATION"))) {
                HStack { FutSideText(side: r.order.side); Text("\(FutNum.exact(r.order.size)) \(r.order.instrument)"); Spacer(); FutOrderStatePill(raw: r.order.status) }
                Field(label: "Exécuté", value: "\(FutNum.exact(r.order.filled)) à \(r.order.avgFillPrice.map { FutNum.exact($0) } ?? "—")")
                if let why = r.order.rejectReason { Banner(.danger, "Rejeté par le moteur papier : \(why)") }
                if let f = r.fills, !f.isEmpty { Field(label: "Exécutions simulées", value: f.map { "\(FutNum.exact($0.size)) à \(FutNum.exact($0.price)) (frais \(FutNum.exact($0.fee)) \($0.feeAsset))" }.joined(separator: "\n")) }
                if r.idempotent == true { Text("Réponse d’un ordre déjà enregistré avec la même clé : rien n’a été placé une seconde fois.").font(.caption).foregroundStyle(.secondary) }
                HStack { Spacer(); Button("Fermer") { flow.clearResult() } }
            }
        } else if mode != .paper, let o = ops.trackedOrder {
            FutTrackedOrderCard(ops: ops, order: o, mode: mode)
        }
        if mode != .paper, let n = ops.notice { Banner(.info, n) }
    }
}

/// The last proposed live order, exactly as the server reports it. « Envoyé » is not « exécuté ».
struct FutTrackedOrderCard: View {
    let ops: FutLiveOps
    let order: LiveOrder
    let mode: FutMode
    var body: some View {
        Card("Suivi de l’ordre", trailing: AnyView(FutModeBadge(mode: mode))) {
            HStack { FutSideText(side: order.side); Text("\(FutNum.exact(order.size)) \(order.instrument)").fontWeight(.medium); Spacer(); if !order.final { ProgressView().controlSize(.small) }; FutOrderStatePill(raw: order.state.rawValue) }
            if order.state.isInFlight { Text("La plateforme n’a encore rien confirmé pour cet ordre. Il n’est ni exécuté ni refusé ; il ne sera jamais renvoyé automatiquement.").font(.callout).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true) }
            Field(label: "Prix (limite ou pire prix)", value: FutNum.exact(order.price))
            Field(label: "Exécuté", value: "\(FutNum.exact(order.filled))" + (order.avgFillPrice.map { " à \(FutNum.exact($0))" } ?? ""))
            if let v = ops.trackedOrderVenue { Field(label: "Réponse de la plateforme", value: v.outcome + (v.error.map { " — \($0)" } ?? "")) }
            if let id = order.venueOrderId { Field(label: "Identifiant plateforme", value: id, mono: true) }
            if let r = order.reason { Banner(order.state.rawValue == "rejected" ? .danger : .warning, r) }
            Field(label: "Source de l’état", value: order.source == "venue" ? "registres de la plateforme" : "portefeuille seul (non confirmé par la plateforme)")
            HStack {
                if !order.final { Button("Annuler cet ordre") { Task { await ops.cancel(orderClientId: order.clientId) } }.disabled(ops.isBusy) }
                Spacer()
                Button("Masquer") { ops.clearTrackedOrder() }
            }
        }
    }
}

/// The pre-trade risk panel: every figure is the backend's preview; estimates are labelled as estimates.
struct FutRiskPanel: View {
    let store: FuturesStore
    let flow: FutTicketFlow
    let preview: FutTicketFlow.Preview

    var body: some View {
        Card("Risques avant l’ordre", trailing: AnyView(HStack(spacing: 6) { ProvenanceTag(p: .estimate, text: "Aperçu du serveur"); FutModeBadge(mode: preview.mode) })) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if !flow.isFresh(preview, at: ctx.date) { Banner(.warning, "Cet aperçu n’est plus à jour (formulaire modifié ou plus de \(Int(FutTicketFlow.previewLifetime)) s). Recalculez-le avant de placer l’ordre.") }
            }
            if let v = preview.verdict, v.ok { Banner(.ok, "Le moteur de risque du serveur accepterait cet ordre maintenant.") }
            else { Banner(.danger, "Refusé par le moteur de risque : \(preview.verdict?.reason ?? "sans détail")" + (preview.verdict?.code.map { " [\($0)]" } ?? "")) }
            if let p = preview.paper { paper(p) } else if let l = preview.live { live(l) }
            Divider()
            Text(lossWording).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Aucune de ces estimations n’est une promesse : le prix d’exécution, les frais et le financement réels peuvent différer.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fundingLine: String {
        guard let id = store.instrumentId, let rate = store.quotes[id]?.quote.funding ?? store.tickers[id]?.funding, let inst = store.instrument else { return "taux non publié" }
        let notional = FutNum.d(preview.paper?.estimate?.notional ?? preview.live?.estimate?.notional)
        let per = notional.flatMap { n in FutNum.d(rate).map { n * $0 } }
        let pays = (FutNum.d(rate) ?? 0) >= 0 ? (flow.side == .buy ? "vous payez" : "vous recevez") : (flow.side == .buy ? "vous recevez" : "vous payez")
        return "\(FutNum.pct(fraction: rate, digits: 4)) par \(FutMarketsView.interval(inst.fundingIntervalSec)) au taux actuel" + (per.map { " → \(FutNum.approx(abs($0), digits: 4)) $ par intervalle (\(pays)) ; le taux change à chaque intervalle" } ?? "")
    }

    @ViewBuilder private func paper(_ p: PaperOrderPreview) -> some View {
        if let e = p.estimate {
            Field(label: "Exposition notionnelle", value: FutNum.usd(e.notional), emphasis: true)
            Field(label: "Levier", value: e.leverage.map { "\(FutNum.exact($0))×" } ?? "réglage du compte")
            Field(label: "Marge requise", value: FutNum.usd(e.initialMargin), emphasis: true)
            Field(label: "Prix de liquidation estimé", value: e.liquidationPrice.map { ($0.value.map { FutNum.exact($0) } ?? "non calculable") + " — estimation (\($0.method))" } ?? "non fourni par le serveur")
            Field(label: "Frais estimés", value: FutNum.usd(e.fee))
            Field(label: "Financement", value: fundingLine)
            Field(label: "Prix moyen simulé", value: (e.avgFillPrice.map { FutNum.exact($0) } ?? "—") + (e.slippageBps.map { " (glissement \(FutNum.exact($0, maxFraction: 2)) pb)" } ?? ""))
            Field(label: "Exécution simulée", value: "exécuté \(FutNum.exact(e.filledSize)) · au carnet \(FutNum.exact(e.restingSize))" + (e.status.map { " · \(FutOrderStatePill.text($0))" } ?? ""))
            Field(label: "Collatéral libre après", value: FutNum.usd(e.freeCollateralAfter))
            if let r = e.rejectReason { Banner(.warning, "Le moteur papier rejetterait l’ordre : \(r)") }
        } else {
            Label("Estimation indisponible : le serveur n’a renvoyé que le verdict.", systemImage: "xmark.octagon").foregroundStyle(Theme.negative)
        }
    }

    @ViewBuilder private func live(_ l: LiveOrderPreview) -> some View {
        if let e = l.estimate {
            Field(label: "Exposition notionnelle", value: FutNum.usd(e.notional), emphasis: true)
            Field(label: "Levier (plateforme)", value: (e.leverage.map { "\(FutNum.exact($0))×" } ?? "non lu") + (e.marginMode.map { " · marge \($0)" } ?? ""))
            Field(label: "Marge requise", value: FutNum.usd(e.initialMargin), emphasis: true)
            Field(label: "Prix de liquidation", value: e.liquidationNote ?? "Le serveur ne fournit aucune estimation avant l’ordre : la plateforme publie le prix de liquidation une fois la position ouverte.")
            Field(label: "Frais estimés", value: FutNum.usd(e.fee) + (e.feeNote.map { " — \($0)" } ?? ""))
            Field(label: "Financement", value: fundingLine)
            Field(label: "Prix retenu / mark", value: "\(FutNum.exact(e.price)) / \(FutNum.exact(e.mark))")
            Field(label: "Collatéral libre après", value: FutNum.usd(e.freeCollateralAfter))
        } else {
            Label("Estimation indisponible : le serveur n’a renvoyé que le verdict.", systemImage: "xmark.octagon").foregroundStyle(Theme.negative)
        }
        if let s = l.venueState?.state { Field(label: "Collatéral du compte en jeu", value: "\(FutNum.usd(s.collateral)) (valeur du compte \(FutNum.usd(s.equity)), lue sur la plateforme)") }
        else { Field(label: "Collatéral du compte en jeu", value: "indisponible : l’état du compte n’a pas pu être lu") }
    }

    private var lossWording: String {
        let margin = preview.paper?.estimate?.initialMargin ?? preview.live?.estimate?.initialMargin
        let sim = preview.mode == .paper ? " (fonds simulés)" : ""
        if flow.reduceOnly { return "Ordre en réduction seule : il ne peut qu’alléger une position existante. La perte déjà latente sur la partie clôturée devient définitive." }
        return "Perte possible\(sim) : en cas de liquidation, la marge de la position (\(FutNum.usd(margin))) est perdue ; en marge croisée, c’est tout le collatéral libre du compte qui sert de garantie et peut être perdu. Un mouvement brutal peut dépasser le prix de liquidation estimé. Le financement s’ajoute tant que la position reste ouverte."
    }
}
