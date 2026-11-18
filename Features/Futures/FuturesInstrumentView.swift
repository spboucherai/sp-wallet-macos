// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Futures/FuturesInstrumentView.swift
// Description: The page of one instrument: live header (mark, index, funding, open interest), candlestick or line chart from the backend's candles (the forming bar follows the quote stream), the order book when the venue serves one (stream first, REST snapshot with its date otherwise; GMX's pool figures instead of a book), recent prints, funding history and the contract's facts — next to the order ticket. Everything here is market data: nothing on this page prepares or sends an order by itself.
import SwiftUI
import Charts
import SPWalletCore

/// One bar for drawing. The Doubles are only pixels: the exact strings stay in the server's answer.
struct FutCandle: Identifiable, Equatable {
    let ts: Date
    let open, high, low, close, volume: Double
    var id: Date { ts }
    init?(_ c: DerivCandle) {
        guard let o = Double(c.open), let h = Double(c.high), let l = Double(c.low), let cl = Double(c.close) else { return nil }
        ts = c.ts; open = o; high = h; low = l; close = cl; volume = Double(c.volume) ?? 0
    }
    init?(_ m: StreamCandleMessage) {
        guard let o = Double(m.open), let h = Double(m.high), let l = Double(m.low), let cl = Double(m.close) else { return nil }
        ts = Date(timeIntervalSince1970: TimeInterval(m.ts) / 1000); open = o; high = h; low = l; close = cl; volume = Double(m.volume) ?? 0
    }
}

struct FutInstrumentView: View {
    let model: AppModel
    @Bindable var store: FuturesStore
    let ops: FutLiveOps
    let ticket: FutTicketFlow
    let go: (FuturesView.Tab) -> Void

    @State private var market = FutLoaded<DerivMarket>()
    @State private var candles = FutLoaded<[FutCandle]>()
    @State private var candleSource: String?
    @State private var funding = FutLoaded<DerivFundingHistory>()
    @State private var lineChart = false

    var body: some View {
        if let id = store.instrumentId {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    header(id)
                    chartCard
                    HStack(alignment: .top, spacing: 16) { bookCard(id); tradesCard }
                    fundingCard
                    factsCard
                }.frame(maxWidth: .infinity, alignment: .leading)
                FutTicketView(model: model, store: store, ops: ops, flow: ticket, go: go).frame(width: 400)
            }
            .futPolling(every: 45, id: id) { await loadMarket(id) }
            .task(id: id) { await loadFunding(id) }
            .futPolling(every: 120, id: "\(id)|\(store.chartInterval.rawValue)") { await loadCandles(id) }
            .onChange(of: store.lastCandle) { _, m in merge(m) }
        } else {
            EmptyState(symbol: "chart.xyaxis.line", title: "Aucun instrument sélectionné", detail: "Choisissez un instrument dans l’onglet Marchés.")
            Button("Voir les marchés") { go(.markets) }
        }
    }

    // MARK: loading

    private func loadMarket(_ id: String) async {
        do { let m = try await store.deriv.market(instrument: id); if id == store.instrumentId { market.set(m) } }
        catch { if id == store.instrumentId { market.fail(model.describe(error)) } }
    }
    private func loadCandles(_ id: String) async {
        let interval = store.chartInterval
        candles.loading = true
        do {
            let a = try await store.deriv.candles(instrument: id, interval: interval, limit: 240)
            guard id == store.instrumentId, interval == store.chartInterval else { return }
            candles.set(a.candles.compactMap(FutCandle.init).sorted { $0.ts < $1.ts }); candleSource = a.source
        } catch { if id == store.instrumentId { candles.fail(model.describe(error)) } }
    }
    private func loadFunding(_ id: String) async {
        funding = FutLoaded()
        do { let f = try await store.deriv.fundingHistory(instrument: id, hours: 168); if id == store.instrumentId { funding.set(f) } }
        catch { if id == store.instrumentId { funding.fail(model.describe(error)) } }
    }
    /// The forming bar of the stream replaces or follows the last bar read from the backend.
    private func merge(_ m: StreamCandleMessage?) {
        guard let m, m.id == store.instrumentId, m.interval == store.chartInterval.rawValue, let c = FutCandle(m), var list = candles.value, let last = list.last else { return }
        if c.ts == last.ts { list[list.count - 1] = c } else if c.ts > last.ts { list.append(c); if list.count > 400 { list.removeFirst(list.count - 400) } } else { return }
        candles.value = list
    }

    // MARK: header

    private var ticker: DerivTicker? { market.value?.ticker.instrument == store.instrumentId ? market.value?.ticker : store.instrumentId.flatMap { store.tickers[$0] } }
    private var liveQuote: StreamQuoteMessage? { store.instrumentId.flatMap { store.quotes[$0]?.quote } }

    @ViewBuilder private func header(_ id: String) -> some View {
        let p = store.price(id), inst = store.instrument ?? market.value?.instrument, q = liveQuote, t = ticker
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                AssetBadge(symbol: inst?.base ?? id)
                Text(inst?.symbol ?? id).font(.title2.weight(.semibold))
                Text(store.venueInfo(inst?.venue ?? "")?.name ?? (inst?.venue ?? "")).foregroundStyle(.secondary)
                if let s = inst?.status, s != "active" { Text(s == "reduce_only" ? "Réduction seule" : s == "halted" ? "Suspendu" : s).font(.caption.weight(.medium)).foregroundStyle(Theme.warning) }
                Spacer()
                FutFreshnessDot(freshness: p.freshness, snapshotAt: p.snapshotAt)
                Text(p.freshness.map { Self.freshText($0) } ?? (p.snapshotAt.map { "Instantané \(Fmt.relative($0))" } ?? "Aucune donnée")).font(.caption).foregroundStyle(.secondary)
            }
            if let e = market.error { Banner(.warning, "Lecture du marché en échec : \(e)" + (market.at.map { " — données du \(Fmt.dateSeconds($0))" } ?? "")) }
            FutStatGrid(minimum: 135) {
                FutStat("Prix (mark)", p.mark.map { FutNum.exact($0) })
                FutStat("Indice / oracle", FutNum.exact(q?.index ?? t?.index))
                FutStat("Milieu du carnet", FutNum.exact(q?.mid ?? t?.mid))
                FutStat("Variation 24 h", FutNum.pct(fraction: q?.change24h ?? t?.change24h), color: Theme.change(FutNum.d(q?.change24h ?? t?.change24h)))
                FutStat("Volume 24 h", FutNum.compactUSD(q?.volume24h ?? t?.volume24h))
                FutStat("Intérêt ouvert", FutNum.compact(q?.openInterest ?? t?.openInterest) + " " + (inst?.base ?? ""))
                FutStat("Financement", (q?.funding ?? t?.funding) == nil ? "—" : FutNum.pct(fraction: q?.funding ?? t?.funding, digits: 4), note: inst.map { "par intervalle de \(FutMarketsView.interval($0.fundingIntervalSec))" })
                FutStat("Prochain financement", t?.nextFundingTs.map { Fmt.relative($0) } ?? "—")
            }
        }
    }
    static func freshText(_ f: StreamFreshness) -> String {
        switch f.state {
        case .live: "En direct"
        case .delayed: "Retardé" + (f.ageMs.map { " de \($0 / 1000) s" } ?? "")
        case .stale: "PÉRIMÉ" + (f.ageMs.map { " (\($0 / 1000) s)" } ?? "")
        case .reconnecting: "Flux en reconnexion — prix non maintenu"
        case .none: "Aucune donnée en direct"
        }
    }

    // MARK: chart

    private var chartCard: some View {
        Card("Graphique", trailing: AnyView(HStack(spacing: 10) {
            Picker("Intervalle", selection: $store.chartInterval) { ForEach(DerivCandleInterval.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 280)
            Picker("Style", selection: $lineChart) { Image(systemName: "chart.bar.fill").tag(false).accessibilityLabel("Chandeliers"); Image(systemName: "chart.xyaxis.line").tag(true).accessibilityLabel("Ligne") }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
        })) {
            if let list = candles.value, !list.isEmpty {
                let lo = list.map(\.low).min() ?? 0, hi = list.map(\.high).max() ?? 1, pad = max((hi - lo) * 0.04, hi * 0.0005)
                let width = max(1.5, min(9, 620 / CGFloat(list.count)))
                Chart(list) { c in
                    if lineChart {
                        LineMark(x: .value("Heure", c.ts), y: .value("Clôture", c.close)).foregroundStyle(Theme.accent).interpolationMethod(.linear)
                    } else {
                        let up = c.close >= c.open
                        RuleMark(x: .value("Heure", c.ts), yStart: .value("Bas", c.low), yEnd: .value("Haut", c.high)).foregroundStyle(up ? Theme.positive : Theme.negative).lineStyle(StrokeStyle(lineWidth: 1))
                        RectangleMark(x: .value("Heure", c.ts), yStart: .value("Ouverture", c.open), yEnd: .value("Clôture", c.close == c.open ? c.close + pad * 0.02 : c.close), width: .fixed(width)).foregroundStyle(up ? Theme.positive : Theme.negative)
                    }
                }
                .chartYScale(domain: (lo - pad)...(hi + pad))
                .chartYAxis { AxisMarks(position: .trailing) }
                .frame(height: 320)
                .accessibilityLabel("Graphique des prix, intervalle \(store.chartInterval.rawValue)")
                if let last = list.last {
                    Text("Dernière barre \(Fmt.date(last.ts)) — O \(last.open.formatted()) · H \(last.high.formatted()) · B \(last.low.formatted()) · C \(last.close.formatted())" + (candleSource.map { " · source : \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let e = candles.error { Text("Dernière actualisation en échec : \(e)").font(.caption).foregroundStyle(Theme.warning) }
            } else if let e = candles.error {
                Banner(.warning, "Chandeliers indisponibles : \(e)")
            } else if candles.loading || candles.value == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                EmptyState(symbol: "chart.bar.xaxis", title: "Aucune barre pour cet intervalle")
            }
        }
    }

    // MARK: book and trades

    private struct Level: Identifiable { let id: String; let price: String; let size: String; let sizeValue: Double }

    @ViewBuilder private func bookCard(_ id: String) -> some View {
        let liveBook = store.book.flatMap { $0.id == id ? $0 : nil }
        let rest = market.value?.book
        Card("Carnet d’ordres", trailing: AnyView(Group {
            if let b = liveBook { let f = store.bookFreshness(b); HStack(spacing: 6) { FutFreshnessDot(freshness: f); Text(Self.freshText(f)).font(.caption).foregroundStyle(.secondary) } }
            else if let r = rest { ProvenanceTag(p: .stale, text: "Instantané \(Fmt.relative(r.ts))") }
        })) {
            if let b = liveBook {
                book(asks: b.asks.map { ($0.price, $0.size) }, bids: b.bids.map { ($0.price, $0.size) })
            } else if let r = rest {
                book(asks: r.asks.map { ($0.price, $0.size) }, bids: r.bids.map { ($0.price, $0.size) })
                if let why = store.refusal(of: .book(id, depth: 20)) { Text("Carnet en direct refusé par le flux : \(why)").font(.caption).foregroundStyle(.secondary) }
            } else if let l = market.value?.liquidity {
                Text("Cette plateforme n’a pas de carnet : la liquidité vient d’un pool.").font(.callout).foregroundStyle(.secondary)
                FutStatGrid(minimum: 150) {
                    FutStat("Liquidité disponible (long)", FutNum.compactUSD(l.availableLiquidityLongUsd))
                    FutStat("Liquidité disponible (short)", FutNum.compactUSD(l.availableLiquidityShortUsd))
                    FutStat("Intérêt ouvert long", FutNum.compactUSD(l.openInterestLongUsd))
                    FutStat("Intérêt ouvert short", FutNum.compactUSD(l.openInterestShortUsd))
                    FutStat("Taux net long / h", FutNum.pct(fraction: l.netRateLongPerHour, digits: 4), note: "positif : le côté reçoit")
                    FutStat("Taux net short / h", FutNum.pct(fraction: l.netRateShortPerHour, digits: 4), note: "positif : le côté reçoit")
                    FutStat("Oracle min / max", "\(FutNum.exact(l.oracleMin)) / \(FutNum.exact(l.oracleMax))")
                }
            } else if let why = market.value?.errors?["book"] ?? market.value?.errors?["liquidity"] {
                Banner(.warning, "Carnet indisponible : \(why)")
            } else if store.venueInfo(String(id.prefix { $0 != ":" }))?.orderBook == false {
                Text("Le serveur ne sert pas de carnet pour cette plateforme.").foregroundStyle(.secondary)
            } else if market.value == nil, market.error == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Label("Carnet indisponible", systemImage: "xmark.octagon").foregroundStyle(Theme.negative)
            }
        }
    }

    @ViewBuilder private func book(asks: [(String, String)], bids: [(String, String)]) -> some View {
        let depth = 12
        let a = asks.prefix(depth).map { Level(id: "a" + $0.0, price: $0.0, size: $0.1, sizeValue: Double($0.1) ?? 0) }
        let b = bids.prefix(depth).map { Level(id: "b" + $0.0, price: $0.0, size: $0.1, sizeValue: Double($0.1) ?? 0) }
        let maxSize = max((a + b).map(\.sizeValue).max() ?? 0, .leastNonzeroMagnitude)
        VStack(spacing: 1) {
            HStack { Text("Prix").frame(maxWidth: .infinity, alignment: .leading); Text("Taille").frame(maxWidth: .infinity, alignment: .trailing) }.font(.caption).foregroundStyle(.secondary)
            ForEach(a.reversed()) { l in levelRow(l, color: Theme.negative, maxSize: maxSize) }
            if let ba = a.first, let bb = b.first, let x = Double(ba.price), let y = Double(bb.price), y > 0 {
                Text("Écart ≈ \(((x - y) / ((x + y) / 2) * 10_000).formatted(.number.precision(.fractionLength(1)))) pb").font(.caption).foregroundStyle(.secondary).padding(.vertical, 3)
            }
            ForEach(b) { l in levelRow(l, color: Theme.positive, maxSize: maxSize) }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Carnet d’ordres, \(a.count) ventes et \(b.count) achats")
    }
    private func levelRow(_ l: Level, color: Color, maxSize: Double) -> some View {
        HStack {
            Text(FutNum.exact(l.price)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
            Text(FutNum.exact(l.size)).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(Theme.monoSmall).padding(.horizontal, 4).padding(.vertical, 1)
        .background(alignment: .trailing) { GeometryReader { g in Rectangle().fill(color.opacity(0.12)).frame(width: g.size.width * CGFloat(min(1, l.sizeValue / maxSize))).frame(maxWidth: .infinity, alignment: .trailing) } }
    }

    private var tradesCard: some View {
        Card("Dernières transactions") {
            if !store.trades.isEmpty {
                ForEach(store.trades.prefix(18)) { t in
                    HStack {
                        Text(FutNum.exact(t.price)).foregroundStyle(t.side == "buy" ? Theme.positive : Theme.negative).frame(maxWidth: .infinity, alignment: .leading)
                        Text(FutNum.exact(t.size)).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(Date(timeIntervalSince1970: TimeInterval(t.ts) / 1000).formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
                    }.font(Theme.monoSmall)
                }
            } else if let list = market.value?.trades, !list.isEmpty {
                ForEach(list.prefix(18), id: \.id) { t in
                    HStack {
                        Text(FutNum.exact(t.price)).foregroundStyle(t.side == "buy" ? Theme.positive : Theme.negative).frame(maxWidth: .infinity, alignment: .leading)
                        Text(FutNum.exact(t.size)).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(t.ts.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
                    }.font(Theme.monoSmall)
                }
                Text("Instantané du \(Fmt.dateSeconds(market.at))").font(.caption).foregroundStyle(.secondary)
            } else if let why = market.value?.errors?["trades"] {
                Text("Indisponible : \(why)").foregroundStyle(.secondary)
            } else {
                Text("Aucune transaction reçue.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: funding and facts

    private var fundingCard: some View {
        Card("Financement — 7 derniers jours") {
            if let f = funding.value, !f.history.isEmpty {
                let pts = f.history.compactMap { r in Double(r.rate).map { (r.ts, $0 * 100) } }
                Chart(pts, id: \.0) { p in
                    BarMark(x: .value("Heure", p.0), y: .value("Taux (%)", p.1)).foregroundStyle(p.1 >= 0 ? Theme.negative.opacity(0.75) : Theme.positive.opacity(0.75))
                }.frame(height: 130).chartYAxis { AxisMarks(position: .trailing) }
                    .accessibilityLabel("Historique des taux de financement appliqués")
                let mean = pts.isEmpty ? nil : pts.map(\.1).reduce(0, +) / Double(pts.count)
                Text("Taux appliqués par la plateforme, par intervalle de \(FutMarketsView.interval(f.intervalSec)) (positif : les positions longues paient les courtes). Moyenne de la période : \(mean.map { ($0 >= 0 ? "+" : "−") + abs($0).formatted(.number.precision(.fractionLength(4))) + " %" } ?? "—") — \(pts.count) observations" + (f.source.map { " · source : \($0)" } ?? "") + ". Un taux passé ne dit rien du taux futur.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let e = funding.error {
                Banner(.warning, "Historique de financement indisponible : \(e)")
            } else if funding.value != nil {
                Text("La plateforme n’a publié aucun taux sur la période.").foregroundStyle(.secondary)
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 60) }
        }
    }

    @ViewBuilder private var factsCard: some View {
        if let i = store.instrument ?? market.value?.instrument {
            Card("Caractéristiques du contrat") {
                Field(label: "Identifiant", value: i.id, mono: true)
                Field(label: "Type", value: "\(i.kind) · \(i.base)/\(i.quote)" + (i.category.map { " · \($0)" } ?? ""))
                Field(label: "Collatéral / règlement", value: "\(i.collateral) / \(i.settlement)")
                Field(label: "Pas de prix", value: FutNum.exact(i.tickSize))
                Field(label: "Pas de taille", value: "\(FutNum.exact(i.lotSize)) \(i.base)")
                Field(label: "Taille minimale", value: i.minOrderSize.map { "\(FutNum.exact($0)) \(i.base)" } ?? "non publiée")
                Field(label: "Notionnel minimal", value: i.minNotional.map { FutNum.usd($0) } ?? "non publié")
                Field(label: "Levier maximal (plateforme)", value: "\(FutNum.exact(i.maxLeverage))× — une limite, jamais une valeur par défaut")
                Field(label: "Modes de marge", value: i.marginModes.joined(separator: ", "))
                Field(label: "Intervalle de financement", value: FutMarketsView.interval(i.fundingIntervalSec))
                Field(label: "Prix de référence (mark)", value: i.markPriceMethod)
                Field(label: "État", value: i.status)
                if let notes = store.venueInfo(i.venue)?.capabilities?.notes, !notes.isEmpty { Field(label: "Notes de la plateforme", value: notes.joined(separator: "\n")) }
            }
        }
    }
}
