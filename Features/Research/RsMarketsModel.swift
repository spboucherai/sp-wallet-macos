// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Features/Research/RsMarketsModel.swift
// Description: State of the market explorer (the server's markets hub: search, filters, sort, paging) and of one underlying's page (its markets venue by venue, the consolidated candles, the comparison of a hypothetical position's cost across venues). Read-only: nothing here prepares or places anything.
import Foundation
import SPWalletCore

@MainActor @Observable final class RsMarketsModel {
    let model: AppModel
    private let api: MarketsAPI
    private static let pageSize = 100

    var search = "" { didSet { if search != oldValue { scheduleReload(debounced: true) } } }
    var kind = "" { didSet { if kind != oldValue { scheduleReload() } } }
    var venue = "" { didSet { if venue != oldValue { scheduleReload() } } }
    var category = "" { didSet { if category != oldValue { scheduleReload() } } }
    var tradableOnly = false { didSet { if tradableOnly != oldValue { scheduleReload() } } }
    var sort: HubQuery.Sort = .volume { didSet { if sort != oldValue { scheduleReload() } } }
    var descending = true { didSet { if descending != oldValue { scheduleReload() } } }

    private(set) var rows: [HubRow] = []
    private(set) var total = 0
    private(set) var counts: HubList.Counts?
    private(set) var venues: [HubVenue] = []
    private(set) var sourceErrors: [SourceError] = []
    private(set) var locks: [ExecutionLock] = []
    private(set) var serverDate: Date?
    private(set) var cacheAgeMs: Int?
    private(set) var loadedAt: Date?
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var categories: [String] = []
    var error: String?
    private var generation = 0
    private var reloadTask: Task<Void, Never>?

    init(model: AppModel) { self.model = model; api = MarketsAPI(model.client) }

    private var query: HubQuery {
        func opt(_ s: String) -> String? { s.isEmpty ? nil : s }
        return HubQuery(kind: opt(kind), venue: opt(venue), category: opt(category), search: opt(search), tradable: tradableOnly ? true : nil, sort: sort, descending: descending, limit: Self.pageSize, offset: 0)
    }

    private func scheduleReload(debounced: Bool = false) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            if debounced { try? await Task.sleep(for: .milliseconds(350)); if Task.isCancelled { return } }
            await self?.reload()
        }
    }

    func reload() async {
        generation += 1; let g = generation
        loading = true; defer { if g == generation { loading = false } }
        do {
            let list = try await api.list(query)
            guard g == generation else { return }
            rows = list.rows; total = list.total; counts = list.counts; venues = list.venues; sourceErrors = list.errors; locks = list.locks ?? []
            serverDate = Date(timeIntervalSince1970: TimeInterval(list.ts) / 1000); cacheAgeMs = list.cache?.ageMs; loadedAt = Date(); error = nil
            categories = Array(Set(categories).union(list.rows.compactMap(\.category))).sorted()
        } catch { guard g == generation else { return }; self.error = model.describe(error) }
    }

    func loadMore() async {
        guard !loadingMore, !loading, rows.count < total else { return }
        loadingMore = true; defer { loadingMore = false }
        let g = generation
        var q = query; q.offset = rows.count
        do {
            let list = try await api.list(q)
            guard g == generation else { return }
            let known = Set(rows.map(\.id))
            rows.append(contentsOf: list.rows.filter { !known.contains($0.id) })
            total = list.total; error = nil
            for e in list.errors where !sourceErrors.contains(e) { sourceErrors.append(e) }
            categories = Array(Set(categories).union(list.rows.compactMap(\.category))).sorted()
        } catch { self.error = model.describe(error) }
    }
}

/// One underlying's page.
@MainActor @Observable final class RsInstrumentModel {
    let model: AppModel
    let symbol: String
    private let api: MarketsAPI

    // markets of the underlying, venue by venue
    private(set) var detail: HubUnderlyingDetail?
    private(set) var detailAt: Date?
    private(set) var detailError: String?

    // consolidated candles
    var interval = "1h" { didSet { if interval != oldValue { Task { await loadCandles() } } } }
    var barCount = 300 { didSet { if barCount != oldValue { Task { await loadCandles() } } } }
    private(set) var intervals: [String] = []
    private(set) var hasMarketData: Bool?
    private(set) var statusError: String?
    private(set) var candles: MarketCandles?
    private(set) var bars: [RsBar] = []
    private(set) var unreadableBars = 0
    private(set) var candlesAt: Date?
    private(set) var candlesError: String?
    private(set) var loadingCandles = false
    private var candleGeneration = 0

    // cost comparison of a hypothetical position (an estimate)
    var side = "long"
    var notional = "1000"
    var leverage = "2"
    var horizonHours = "24"
    var liquidity = "taker"
    private(set) var comparison: VenueComparison?
    private(set) var comparisonAt: Date?
    private(set) var comparisonError: String?
    private(set) var comparing = false

    init(model: AppModel, symbol: String) { self.model = model; self.symbol = symbol; api = MarketsAPI(model.client) }

    func load() async {
        async let a: Void = loadDetail()
        async let b: Void = loadStatusThenCandles()
        _ = await (a, b)
    }

    func loadDetail() async {
        do { detail = try await api.underlying(symbol); detailAt = Date(); detailError = nil } catch { detailError = model.describe(error) }
    }

    private func loadStatusThenCandles() async {
        do {
            let s = try await api.marketDataStatus()
            intervals = s.intervals; statusError = nil
            hasMarketData = s.symbols.contains { $0.uppercased() == symbol.uppercased() }
            if !s.intervals.contains(interval), let first = s.intervals.first { interval = first; return } // didSet loads
        } catch { statusError = model.describe(error); hasMarketData = nil }
        await loadCandles()
    }

    func loadCandles() async {
        guard hasMarketData != false else { candles = nil; bars = []; return }
        candleGeneration += 1; let g = candleGeneration
        loadingCandles = true; defer { if g == candleGeneration { loadingCandles = false } }
        do {
            let c = try await api.candles(symbol: symbol.uppercased(), interval: interval, limit: barCount)
            guard g == candleGeneration else { return }
            let parsed = c.bars.compactMap(RsBar.init).sorted { $0.date < $1.date }
            candles = c; bars = parsed; unreadableBars = c.bars.count - parsed.count; candlesAt = Date(); candlesError = nil
        } catch { guard g == candleGeneration else { return }; candlesError = model.describe(error) }
    }

    var comparisonProblem: String? {
        func positive(_ s: String) -> Bool { (Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 }
        if !positive(notional) { return "Notionnel en USD invalide." }
        if !positive(leverage) { return "Levier invalide." }
        if !positive(horizonHours) { return "Horizon en heures invalide." }
        return nil
    }

    func compare() async {
        guard comparisonProblem == nil, !comparing else { return }
        comparing = true; defer { comparing = false }
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".") }
        do {
            comparison = try await api.compare(CompareQuery(underlying: symbol, side: side, notional: norm(notional), leverage: norm(leverage), horizonHours: norm(horizonHours), liquidity: liquidity))
            comparisonAt = Date(); comparisonError = nil
        } catch { comparisonError = model.describe(error) }
    }
}
