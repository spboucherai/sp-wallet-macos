// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Futures/FuturesAccountView.swift
// Description: The account of the current mode — a paper account (SIMULATION) or the live venue account (testnet / mainnet), never both: equity, collateral, free collateral, margin used, positions with their liquidation price as served (the venue's own figure, or the paper engine's estimate, labelled), open orders, order history, fills, funding payments and risk events. A venue that could not be read is shown as unavailable, never as an empty account. Cancels and reduce-only closes are always offered: they are never behind the server locks.
import SwiftUI
import Charts
import SPWalletCore

/// Operations on a PAPER account: everything here is simulated by the server and can never reach a venue or the signer.
@MainActor @Observable final class FutPaperOps {
    let model: AppModel
    let store: FuturesStore
    private(set) var busy = false
    var error: String?
    var notice: String?
    @ObservationIgnored private var closeKey: (key: String, fingerprint: String)?

    init(model: AppModel, store: FuturesStore) { self.model = model; self.store = store }

    private func run(_ body: () async throws -> Void) async {
        guard model.canOperate, !busy else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do { try await body() } catch { self.error = model.describe(error) }
    }

    func create(venue: String, label: String, collateral: String) async {
        await run {
            let d = try await store.deriv.createPaperAccount(PaperAccountCreation(venue: venue, label: label, collateral: collateral))
            await store.loadAccounts()
            store.paperId = d.account.id; store.adopt(d)
            notice = "Compte papier « \(d.account.label) » créé avec \(FutNum.usd(d.account.state.collateral)) de collatéral simulé."
        }
    }
    func reset() async {
        guard let id = store.paperId else { return }
        await run { store.adopt(try await store.deriv.resetPaperAccount(id)); notice = "Compte papier remis à son collatéral initial : ordres, exécutions et historique simulés effacés." }
    }
    func cancel(clientId: String) async {
        guard let id = store.paperId else { return }
        await run {
            let o = try await store.deriv.cancelPaperOrder(id, clientId: clientId)
            notice = "Ordre simulé \(o.instrument) : \(FutOrderStatePill.text(o.status))."
            await store.refreshAccount()
        }
    }
    func close(_ p: DerivPosition, fraction: String, slippageBps: Int) async {
        guard let id = store.paperId else { return }
        await run {
            let fp = "\(id)|\(p.instrument)|\(p.side)|\(p.size)|\(fraction)|\(slippageBps)"
            if closeKey?.fingerprint != fp { closeKey = (APIClient.newIdempotencyKey(), fp) }
            let r = try await store.deriv.closePaperPosition(id, instrument: p.instrument, fraction: fraction, slippageBps: slippageBps, idempotencyKey: closeKey!.key)
            closeKey = nil
            notice = "Clôture simulée \(p.instrument) : \(FutOrderStatePill.text(r.order.status))" + (r.order.avgFillPrice.map { ", exécutée à \(FutNum.exact($0))" } ?? "") + (r.order.rejectReason.map { " — \($0)" } ?? "") + (r.worstPrice.map { " (pire prix accepté \(FutNum.exact($0)))" } ?? "")
            await store.refreshAccount()
        }
    }
}

struct FutAccountView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    let ops: FutLiveOps
    let open: (String) -> Void
    @State private var paper: FutPaperOps?

    var body: some View {
        Group {
            switch store.mode {
            case .paper: if let paper { FutPaperAccountView(model: model, store: store, paper: paper, open: open) } else { ProgressView() }
            case .testnet, .mainnet: FutLiveAccountView(model: model, store: store, ops: ops, open: open)
            }
        }
        .task { if paper == nil { paper = FutPaperOps(model: model, store: store) } }
    }
}

// MARK: - paper

private struct FutPaperAccountView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    @Bindable var paper: FutPaperOps
    let open: (String) -> Void
    @State private var creating = false
    @State private var newVenue = ""
    @State private var newLabel = ""
    @State private var newCollateral = ""
    @State private var confirmReset = false

    private var paperVenues: [DerivVenue] { (store.venues.value ?? []).filter { $0.paper == true } }

    var body: some View {
        Card("Comptes papier", trailing: AnyView(ProvenanceTag(p: .simulated, text: "SIMULATION — aucun fonds réel"))) {
            if let e = store.paperAccounts.error { Banner(.danger, "Comptes papier indisponibles : \(e)") }
            HStack {
                if let list = store.paperAccounts.value, !list.isEmpty {
                    Picker("Compte", selection: Binding(get: { store.paperId }, set: { store.paperId = $0 })) {
                        ForEach(list) { a in Text("\(a.label) — \(a.venue)").tag(Optional(a.id)) }
                    }.frame(maxWidth: 360)
                } else if store.paperAccounts.value != nil { Text("Aucun compte papier.").foregroundStyle(.secondary) }
                Spacer()
                if paper.busy { ProgressView().controlSize(.small) }
                Button("Nouveau compte papier…") { creating.toggle(); if newVenue.isEmpty { newVenue = paperVenues.first?.id ?? "" } }
                Button("Réinitialiser…", role: .destructive) { confirmReset = true }.disabled(store.paperId == nil || !model.canOperate || paper.busy)
                    .confirmationDialog("Réinitialiser ce compte papier ?", isPresented: $confirmReset) {
                        Button("Effacer l’historique simulé et revenir au collatéral initial", role: .destructive) { Task { await paper.reset() } }
                    } message: { Text("Ordres, exécutions, financement et courbe de valeur simulés de ce compte seront effacés. Aucun fonds réel n’est concerné.") }
            }
            if creating {
                Form {
                    Picker("Plateforme simulée", selection: $newVenue) { ForEach(paperVenues) { Text($0.name).tag($0.id) } }
                    TextField("Nom du compte", text: $newLabel)
                    TextField("Collatéral simulé (10 à 1 000 000 000)", text: $newCollateral, prompt: Text("montant en dollars simulés"))
                }.formStyle(.grouped).scrollDisabled(true)
                if paperVenues.isEmpty { Text("Le serveur n’offre de compte papier sur aucune plateforme pour l’instant.").font(.callout).foregroundStyle(.secondary) }
                HStack {
                    Spacer()
                    Button("Créer le compte SIMULÉ") {
                        guard let c = FutNum.input(newCollateral) else { return }
                        Task { await paper.create(venue: newVenue, label: newLabel.trimmingCharacters(in: .whitespaces), collateral: c); if paper.error == nil { creating = false; newLabel = ""; newCollateral = "" } }
                    }.buttonStyle(.borderedProminent).tint(FutMode.paper.color)
                        .disabled(newVenue.isEmpty || newLabel.trimmingCharacters(in: .whitespaces).isEmpty || FutNum.input(newCollateral) == nil || !model.canOperate || paper.busy)
                }
            }
            if let e = paper.error { Banner(.danger, e) }
            if let n = paper.notice { Banner(.info, n) }
        }
        if let e = store.paperDetail.error { Banner(.warning, "Dernière lecture du compte en échec : \(e)" + (store.paperDetail.at.map { " — données du \(Fmt.dateSeconds($0))" } ?? "")) }
        if let d = store.currentPaperDetail {
            let a = d.account
            FutStateCard(title: "État du compte « \(a.label) »", mode: .paper, state: a.state, unavailable: nil) {
                FutStat("Collatéral initial", FutNum.usd(a.initialCollateral))
                FutStat("PnL réalisé (simulé)", FutNum.usd(a.totals?.realizedPnl), color: Theme.change(FutNum.d(a.totals?.realizedPnl)))
                FutStat("Frais payés (simulés)", FutNum.usd(a.totals?.feesPaid))
                FutStat("Financement net (simulé)", FutNum.usd(a.totals?.fundingNet), color: Theme.change(FutNum.d(a.totals?.fundingNet)))
                FutStat("Liquidations simulées", a.totals?.liquidations.map(String.init) ?? "—")
            }
            if let how = a.settings?.liquidationPrice { Text("Prix de liquidation des positions papier : \(how)").font(.caption).foregroundStyle(.secondary) }
            FutEquityCard(points: d.equity, mode: .paper)
            FutPositionsCard(model: model, store: store, mode: .paper, positions: a.positions, busy: paper.busy, open: open) { p, f, s in Task { await paper.close(p, fraction: f, slippageBps: s) } }
            FutOrdersCard(title: "Ordres ouverts", mode: .paper, rows: a.openOrders.map(FutOrderRow.init), empty: "Aucun ordre simulé au carnet.", busy: paper.busy || !model.canOperate) { id in Task { await paper.cancel(clientId: id) } }
            FutOrdersCard(title: "Historique des ordres", mode: .paper, rows: d.orders.map(FutOrderRow.init), empty: "Aucun ordre simulé.", busy: true, cancel: nil)
            FutFillsCard(mode: .paper, fills: d.fills)
            FutFundingCard(mode: .paper, payments: d.funding)
            FutRiskEventsCard(events: d.riskEvents)
        } else if store.paperId != nil, store.paperDetail.error == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 100)
        }
    }
}

// MARK: - live

private struct FutLiveAccountView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    @Bindable var ops: FutLiveOps
    let open: (String) -> Void
    @State private var confirmCancelAll = false

    var body: some View {
        let mode = store.mode
        if let e = store.liveAccounts.error { Banner(.danger, "Comptes de plateforme indisponibles : \(e)") }
        if let a = store.liveAccount {
            Card("Compte \(a.label)", trailing: AnyView(FutModeBadge(mode: mode))) {
                Field(label: "Adresse du compte", value: a.account, mono: true)
                Field(label: "Plateforme / réseau", value: "\(a.venue) · \(a.network)")
                Field(label: "Mode du compte", value: a.mode.rawValue + (a.tradable ? " — nouveau risque permis" : " — nouveau risque refusé"))
                ForEach(store.liveBlockers, id: \.self) { Banner(.warning, $0) }
                if let dv = a.divergence { Banner(.danger, "Divergence entre le portefeuille et la plateforme : \(dv)") }
                HStack {
                    if ops.isBusy { ProgressView().controlSize(.small); Text(ops.busyText ?? "").font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Rapprocher avec la plateforme") { Task { await ops.reconcile() } }.disabled(!model.canOperate || ops.isBusy)
                    Button("Actualiser") { Task { await store.refreshAccount() } }
                }
                if let e = ops.error { Banner(.danger, e) }
                if let n = ops.notice { Banner(.info, n) }
            }
            if let e = store.liveDetail.error { Banner(.danger, "Lecture du compte en échec : \(e)" + (store.liveDetail.at.map { " — ce qui suit date du \(Fmt.dateSeconds($0))" } ?? "")) }
            if let d = store.currentLiveDetail {
                let vs = d.venueState
                if let e = vs.error { Banner(.danger, "La plateforme n’a pas pu être lue : \(e). Les soldes et positions sont INDISPONIBLES — ce n’est pas un compte vide.") }
                FutStateCard(title: "État du compte sur la plateforme", mode: mode, state: vs.state, unavailable: vs.error ?? (vs.state == nil ? "état non fourni" : nil)) { EmptyView() }
                if let o = ops.trackedOrder { FutTrackedOrderCard(ops: ops, order: o, mode: mode) }
                FutEquityCard(points: d.equity, mode: mode)
                if vs.error == nil {
                    FutPositionsCard(model: model, store: store, mode: mode, positions: vs.positions, busy: ops.isBusy, open: open) { p, f, s in Task { await ops.proposeClose(p, fraction: f, slippageBps: s) } }
                    FutOrdersCard(title: "Ordres au carnet de la plateforme", mode: mode, rows: vs.openOrders.map(FutOrderRow.init), empty: "Aucun ordre au carnet selon la plateforme.", busy: true, cancel: nil)
                }
                let pending = d.orders.filter { !$0.final }
                Card("Ordres en cours suivis par le portefeuille", trailing: AnyView(Button("Tout annuler sur la plateforme…", role: .destructive) { confirmCancelAll = true }.disabled(!model.canOperate || ops.isBusy)
                    .confirmationDialog("Annuler tous les ordres au carnet de ce compte ?", isPresented: $confirmCancelAll) {
                        Button("Annuler tous les ordres (\(mode.badge))", role: .destructive) { Task { await ops.cancelAll() } }
                    } message: { Text("La plateforme est interrogée pour chaque ordre. Aucune position n’est clôturée. Aucune passkey n’est requise pour arrêter.") })) {
                    FutOrdersTable(rows: pending.map(FutOrderRow.init), empty: "Aucun ordre en cours.", busy: !model.canOperate || ops.isBusy) { id in Task { await ops.cancel(orderClientId: id) } }
                }
                FutOrdersCard(title: "Historique des ordres", mode: mode, rows: d.orders.map(FutOrderRow.init), empty: "Aucun ordre.", busy: true, cancel: nil)
                FutFillsCard(mode: mode, fills: d.fills)
                FutFundingCard(mode: mode, payments: d.funding)
                FutRiskEventsCard(events: d.riskEvents)
            } else if store.liveDetail.error == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            }
        } else if store.liveAccounts.value != nil {
            EmptyState(symbol: "person.crop.rectangle.badge.plus", title: "Aucun compte \(mode == .mainnet ? "réel" : "testnet")", detail: "Le compte de plateforme se crée dans l’onglet « Plateforme et collatéral ». Il est créé en lecture seule.")
        }
    }
}

// MARK: - shared cards

struct FutStateCard<Extra: View>: View {
    let title: String
    let mode: FutMode
    let state: DerivAccountState?
    /// Non-nil: the state could not be read — every figure shows as unavailable.
    let unavailable: String?
    @ViewBuilder var extra: Extra

    var body: some View {
        Card(title, trailing: AnyView(FutModeBadge(mode: mode))) {
            let s = unavailable == nil ? state : nil
            FutStatGrid {
                FutStat("Valeur du compte (equity)", s.map { FutNum.usd($0.equity) })
                FutStat("Collatéral", s.map { FutNum.usd($0.collateral) })
                FutStat("Collatéral libre", s.map { FutNum.usd($0.freeCollateral) })
                FutStat("Marge utilisée", s.map { FutNum.usd($0.marginUsed) })
                FutStat("Marge de maintien", s.map { $0.maintenanceMargin.map { FutNum.usd($0) } ?? "non publiée" })
                FutStat("Retirable", s.map { $0.withdrawable.map { FutNum.usd($0) } ?? "non publié" })
                extra
            }
            if let s { Text("Lu \(Fmt.relative(s.ts)) — source : \(s.source == "paper" ? "moteur papier (simulation)" : s.source == "venue" ? "la plateforme" : s.source)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct FutEquityCard: View {
    let points: [DerivEquityPoint]
    let mode: FutMode
    var body: some View {
        let pts = points.compactMap { p in Double(p.equity).map { (p.ts, $0) } }.sorted { $0.0 < $1.0 }
        if pts.count > 1 {
            Card("Valeur du compte dans le temps", trailing: AnyView(FutModeBadge(mode: mode))) {
                Chart(pts, id: \.0) { p in LineMark(x: .value("Date", p.0), y: .value("Valeur", p.1)).foregroundStyle(mode.color) }
                    .chartYScale(domain: .automatic(includesZero: false)).chartYAxis { AxisMarks(position: .trailing) }.frame(height: 150)
                    .accessibilityLabel("Courbe de la valeur du compte")
                Text("Points enregistrés par le serveur ; les dépôts et retraits y figurent comme des variations.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FutPositionsCard: View {
    let model: AppModel
    let store: FuturesStore
    let mode: FutMode
    let positions: [DerivPosition]
    let busy: Bool
    let open: (String) -> Void
    let close: (DerivPosition, String, Int) -> Void
    @State private var selected: String?
    @State private var fraction = "1"
    @State private var slippage = "50"
    @State private var confirm = false

    private func key(_ p: DerivPosition) -> String { "\(p.instrument)|\(p.side)" }

    var body: some View {
        Card("Positions", trailing: AnyView(FutModeBadge(mode: mode))) {
            if positions.isEmpty { Text("Aucune position ouverte.").foregroundStyle(.secondary) }
            ForEach(positions, id: \.self) { p in
                let live = store.price(p.instrument)
                let mark = FutNum.d(live.freshness?.isLive == true ? live.mark : p.markPrice) ?? FutNum.d(p.markPrice)
                let size = FutNum.d(p.size), liq = FutNum.d(p.liquidationPrice)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        FutSideText(side: p.side)
                        Button(p.instrument) { open(p.instrument) }.buttonStyle(.link).fontWeight(.medium)
                        Text("\(FutNum.exact(p.leverage))× · marge \(p.marginMode == "cross" ? "croisée" : p.marginMode == "isolated" ? "isolée" : p.marginMode)").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text("PnL latent \(FutNum.usd(p.unrealizedPnl))").fontWeight(.semibold).foregroundStyle(Theme.change(FutNum.d(p.unrealizedPnl))).monospacedDigit()
                    }
                    FutStatGrid(minimum: 130) {
                        FutStat("Taille", FutNum.exact(p.size))
                        FutStat("Prix d’entrée", FutNum.exact(p.entryPrice))
                        FutStat("Prix (mark)", FutNum.exact(p.markPrice))
                        FutStat("Notionnel", size.flatMap { s in mark.map { FutNum.approx(s * $0) + " $" } } ?? "—", note: "taille × prix")
                        FutStat("Marge", FutNum.usd(p.margin))
                        FutStat("Prix de liquidation", p.liquidationPrice.map { FutNum.exact($0) } ?? "non fourni",
                                color: p.liquidationPrice == nil ? .secondary : Theme.warning,
                                note: p.liquidationPrice == nil ? "la source n’en publie pas pour cette position" : p.liquidationPriceIsVenueReported ? "chiffre de la plateforme" : "estimation du moteur papier")
                        FutStat("Distance à la liquidation", liq.flatMap { l in mark.flatMap { m in m > 0 ? "≈ " + (abs(m - l) / m * 100).formatted(.number.precision(.fractionLength(2))) + " %" : nil } } ?? "—", note: "par rapport au prix affiché")
                        FutStat("Financement cumulé", p.fundingPaid.map { FutNum.usd($0) } ?? "non publié", note: "payé (positif) ou reçu")
                        FutStat("PnL réalisé", p.realizedPnl.map { FutNum.usd($0) } ?? "non publié")
                    }
                    HStack {
                        Picker("Part à clôturer", selection: Binding(get: { selected == key(p) ? fraction : "1" }, set: { selected = key(p); fraction = $0 })) {
                            Text("25 %").tag("0.25"); Text("50 %").tag("0.5"); Text("75 %").tag("0.75"); Text("100 %").tag("1")
                        }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
                        TextField("pb", text: $slippage).textFieldStyle(.roundedBorder).frame(width: 60).help("Glissement maximal en points de base par rapport au carnet (1 à 500)")
                        Text("pb max").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(mode == .paper ? "Clôturer (SIMULÉ)…" : "Préparer la clôture (\(mode.badge))…") { selected = key(p); confirm = true }
                            .disabled(busy || !model.canOperate || Int(slippage).map { (1...500).contains($0) } != true)
                    }
                    Text("Clôture en réduction seule, au marché, bornée par ce glissement. Toujours disponible, même quand les nouveaux ordres sont fermés." + (mode == .paper ? "" : " L’ordre exact vous est montré avant votre passkey.")).font(.caption).foregroundStyle(.secondary)
                }
                .padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .confirmationDialog("Clôturer \(p.instrument) ?", isPresented: Binding(get: { confirm && selected == key(p) }, set: { if !$0 { confirm = false } })) {
                    let f = selected == key(p) ? fraction : "1"
                    Button(mode == .paper ? "Clôturer \(Self.percent(f)) (simulation)" : "Préparer la clôture de \(Self.percent(f))") { if let s = Int(slippage) { close(p, f, s) } }
                } message: { Text(mode == .paper ? "Ordre simulé en réduction seule : aucun fonds réel." : "Rien n’est envoyé maintenant : le serveur prépare l’ordre réducteur, que vous vérifierez puis approuverez avec votre passkey.") }
            }
        }
    }
    static func percent(_ f: String) -> String { (Double(f).map { Int(($0 * 100).rounded()) } ?? 100).description + " %" }
}

/// One order for a table, whichever engine it comes from; states are kept verbatim.
struct FutOrderRow: Identifiable {
    let id: String
    let instrument, side, type, size, tif, state, filled: String
    let price, avg, reason, source: String?
    let reduceOnly: Bool
    let final: Bool
    let at: Date?

    init(_ o: DerivOrder) {
        id = o.clientId + (o.venueOrderId ?? ""); instrument = o.instrument; side = o.side; type = o.type; size = o.size; tif = o.tif; state = o.status; filled = o.filled
        price = o.price; avg = o.avgFillPrice; reason = o.rejectReason; source = nil; reduceOnly = o.reduceOnly
        final = ["filled", "cancelled", "rejected"].contains(o.status); at = o.updatedAt ?? o.createdAt
        clientId = o.clientId
    }
    init(_ o: LiveOrder) {
        id = o.clientId; instrument = o.instrument; side = o.side; type = o.type; size = o.size; tif = o.tif; state = o.state.rawValue; filled = o.filled
        price = o.price; avg = o.avgFillPrice; reason = o.reason; source = o.source; reduceOnly = o.reduceOnly; final = o.final; at = o.updatedAt ?? o.createdAt
        clientId = o.clientId
    }
    let clientId: String
}

struct FutOrdersCard: View {
    let title: String
    let mode: FutMode
    let rows: [FutOrderRow]
    let empty: String
    let busy: Bool
    let cancel: ((String) -> Void)?
    var body: some View {
        Card(title, trailing: AnyView(FutModeBadge(mode: mode))) { FutOrdersTable(rows: rows, empty: empty, busy: busy, cancel: cancel) }
    }
}

struct FutOrdersTable: View {
    let rows: [FutOrderRow]
    let empty: String
    let busy: Bool
    let cancel: ((String) -> Void)?
    var body: some View {
        if rows.isEmpty { Text(empty).foregroundStyle(.secondary) } else {
            Table(rows) {
                TableColumn("Date") { r in Text(Fmt.date(r.at)).font(.callout) }.width(min: 110, ideal: 130)
                TableColumn("Instrument") { r in HStack(spacing: 6) { FutSideText(side: r.side); Text(r.instrument); if r.reduceOnly { Text("réd.").font(.caption2).foregroundStyle(.secondary) } } }.width(min: 150, ideal: 190)
                TableColumn("Type") { r in Text("\(r.type) · \(r.tif)").font(.callout) }.width(min: 80, ideal: 100)
                TableColumn("Taille") { r in Text(FutNum.exact(r.size)).monospacedDigit() }.width(min: 70, ideal: 90)
                TableColumn("Prix") { r in Text(FutNum.exact(r.price)).monospacedDigit() }.width(min: 80, ideal: 100)
                TableColumn("Exécuté") { r in Text(FutNum.exact(r.filled) + (r.avg.map { " à \(FutNum.exact($0))" } ?? "")).monospacedDigit() }.width(min: 110, ideal: 150)
                TableColumn("État") { r in FutOrderStatePill(raw: r.state).help(r.reason ?? "") }.width(min: 150, ideal: 220)
                TableColumn("") { r in
                    if let cancel, !r.final { Button("Annuler") { cancel(r.clientId) }.disabled(busy) }
                    else if let why = r.reason { Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(why) }
                }.width(min: 80, ideal: 160)
            }
            .frame(height: CGFloat(min(rows.count, 10)) * 30 + 36)
        }
    }
}

struct FutFillsCard: View {
    let mode: FutMode
    let fills: [DerivFill]
    var body: some View {
        Card("Exécutions", trailing: AnyView(FutModeBadge(mode: mode))) {
            if fills.isEmpty { Text("Aucune exécution.").foregroundStyle(.secondary) } else {
                Table(fills) {
                    TableColumn("Date") { f in Text(Fmt.date(f.ts)).font(.callout) }.width(min: 110, ideal: 130)
                    TableColumn("Instrument") { f in HStack(spacing: 6) { FutSideText(side: f.side); Text(f.instrument); if f.liquidation { Text("LIQUIDATION").font(.caption2.weight(.bold)).foregroundStyle(Theme.negative) } } }.width(min: 150, ideal: 200)
                    TableColumn("Taille") { f in Text(FutNum.exact(f.size)).monospacedDigit() }.width(min: 70, ideal: 90)
                    TableColumn("Prix") { f in Text(FutNum.exact(f.price)).monospacedDigit() }.width(min: 80, ideal: 100)
                    TableColumn("Frais") { f in Text("\(FutNum.exact(f.fee)) \(f.feeAsset)").monospacedDigit() }.width(min: 90, ideal: 120)
                    TableColumn("PnL clôturé") { f in Text(f.closedPnl.map { FutNum.usd($0) } ?? "—").monospacedDigit().foregroundStyle(Theme.change(FutNum.d(f.closedPnl))) }.width(min: 90, ideal: 120)
                    TableColumn("Source") { f in Text(f.source ?? (mode == .paper ? "paper" : "—")).font(.caption).foregroundStyle(.secondary) }.width(min: 60, ideal: 80)
                }.frame(height: CGFloat(min(fills.count, 10)) * 28 + 36)
            }
        }
    }
}

struct FutFundingCard: View {
    let mode: FutMode
    let payments: [DerivFundingPayment]
    var body: some View {
        Card("Paiements de financement du compte", trailing: AnyView(FutModeBadge(mode: mode))) {
            if payments.isEmpty { Text("Aucun paiement de financement enregistré.").foregroundStyle(.secondary) } else {
                ForEach(Array(payments.prefix(40).enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(Fmt.date(p.ts)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                        Text(p.instrument).frame(maxWidth: .infinity, alignment: .leading)
                        Text("taux \(FutNum.pct(fraction: p.rate, digits: 4)) · taille \(FutNum.exact(p.size))").font(.callout).foregroundStyle(.secondary)
                        Text(FutNum.usd(p.amount)).monospacedDigit().foregroundStyle(Theme.change(FutNum.d(p.amount))).frame(width: 130, alignment: .trailing)
                    }.font(.callout)
                }
                Text("Montant négatif : payé ; positif : reçu." + (payments.count > 40 ? " 40 plus récents sur \(payments.count)." : "")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FutRiskEventsCard: View {
    let events: [DerivRiskEvent]
    var body: some View {
        if !events.isEmpty {
            Card("Événements de risque du compte") {
                ForEach(events.prefix(25)) { e in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.date(e.ts)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                        Text(e.kind + (e.code.map { " · \($0)" } ?? "")).font(Theme.monoSmall).frame(width: 220, alignment: .leading)
                        Text(e.message).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }.font(.callout)
                }
            }
        }
    }
}
