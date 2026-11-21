// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Futures/FuturesStore.swift
// Description      : The read side of the derivatives terminal, shared by its
//                    tabs: venues, instruments, tickers, server locks and
//                    capabilities, jurisdiction notice, paper and live
//                    accounts, and the live quote stream (the Core's websocket,
//                    with its own reconnection and freshness verdicts). Every
//                    source keeps its own error: a failed read is shown as
//                    unavailable, never as an empty or zero account. Nothing
//                    here places, prepares or signs anything.
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

import Foundation
import SPWalletCore

@MainActor @Observable final class FuturesStore {
    let model: AppModel
    let deriv: DerivativesAPI
    let live: DerivativesLiveAPI
    let collateral: DerivativesCollateralAPI
    let gmx: DerivativesGMXAPI
    let risk: RiskAPI
    let markets: MarketsAPI
    let monitor: MonitorAPI
    @ObservationIgnored private let stream: QuoteStream

    // MARK: selection

    var mode: FutMode = .paper { didSet { if mode != oldValue { liveDetail = FutLoaded(); Task { await refreshAccount() } } } }
    var venue = "" { didSet { if venue != oldValue { instruments = FutLoaded(); tickers = [:]; Task { await loadMarket() } } } }
    var instrumentId: String? { didSet { if instrumentId != oldValue { book = nil; trades = []; lastCandle = nil; resubscribe() } } }
    var chartInterval: DerivCandleInterval = .h1 { didSet { if chartInterval != oldValue { lastCandle = nil; resubscribe() } } }
    var paperId: PaperAccountID? { didSet { if paperId != oldValue { paperDetail = FutLoaded(); Task { await refreshAccount() } } } }
    /// The owner's own statement, for this session of the screen, that the jurisdiction notice was read. Never persisted, never assumed.
    var jurisdictionRead = false

    // MARK: what the server said

    private(set) var venues = FutLoaded<[DerivVenue]>()
    private(set) var instruments = FutLoaded<[DerivInstrument]>()
    private(set) var venueErrors: [DerivVenueReadError] = []
    private(set) var tickers: [String: DerivTicker] = [:]
    private(set) var tickersAt: Date?
    private(set) var tickersError: String?
    private(set) var config = FutLoaded<LiveConfig>()
    private(set) var jurisdiction = FutLoaded<JurisdictionAnswer>()
    private(set) var capabilities = FutLoaded<[ServerCapability]>()
    private(set) var riskState = FutLoaded<RiskState>()
    private(set) var paperAccounts = FutLoaded<[PaperAccount]>()
    private(set) var liveAccounts = FutLoaded<[LiveAccount]>()
    private(set) var paperDetail = FutLoaded<PaperAccountDetail>()
    private(set) var liveDetail = FutLoaded<LiveAccountDetail>()

    // MARK: live stream

    private(set) var streamState: QuoteStreamState = .idle
    private(set) var quotes: [String: LiveQuote] = [:]
    private(set) var book: LiveBook?
    private(set) var trades: [StreamTrade] = []
    private(set) var lastCandle: StreamCandleMessage?
    private(set) var streamError: String?
    private(set) var channelRefusals: [String: String] = [:]
    /// The clock the freshness verdicts are evaluated on; advanced by the flush loop so that a silent quote turns stale on screen.
    private(set) var now = Date()

    @ObservationIgnored private var pending: [String: LiveQuote] = [:]
    @ObservationIgnored private var pendingBook: LiveBook?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var subscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var channels: Set<StreamChannel> = []
    @ObservationIgnored private var listIds: [String] = []
    /// How many list rows get a live quote; the rest show the REST snapshot with its age (the server caps a connection's subscriptions).
    static let liveRows = 120

    init(model: AppModel) {
        self.model = model
        let c = model.client
        deriv = DerivativesAPI(c); live = DerivativesLiveAPI(c); collateral = DerivativesCollateralAPI(c); gmx = DerivativesGMXAPI(c)
        risk = RiskAPI(c); markets = MarketsAPI(c); monitor = MonitorAPI(c)
        stream = QuoteStream(client: c)
    }

    var locale: String { model.settings.locale.lowercased().hasPrefix("fr") ? "fr" : "en" }

    // MARK: derived

    var selectedVenue: DerivVenue? { venues.value?.first { $0.id == venue } }
    var instrument: DerivInstrument? { instruments.value?.first { $0.id == instrumentId } }
    func venueInfo(_ id: String) -> DerivVenue? { venues.value?.first { $0.id == id } }

    /// The live venue account of the current mode (one per venue and network); nil in paper mode or when none exists.
    var liveAccount: LiveAccount? {
        guard let net = mode.network else { return nil }
        if let d = liveDetail.value, d.account.network == net { return d.account }
        return liveAccounts.value?.first { $0.network == net }
    }
    var paperAccount: PaperAccount? {
        if let d = paperDetail.value, d.account.id == paperId { return d.account }
        return paperAccounts.value?.first { $0.id == paperId }
    }
    /// The live detail, only when it belongs to the current mode.
    var currentLiveDetail: LiveAccountDetail? { liveDetail.value.flatMap { $0.account.network == mode.network ? $0 : nil } }
    var currentPaperDetail: PaperAccountDetail? { paperDetail.value.flatMap { $0.account.id == paperId ? $0 : nil } }

    func capability(_ id: String) -> ServerCapability? { capabilities.value?.first { $0.id == id } }
    func executionLock(_ id: String) -> ExecutionLock? { riskState.value?.locks.first { $0.id == id } }
    var killSwitch: RiskSwitch? { riskState.value?.switches.killSwitch }
    var readOnlySwitch: RiskSwitch? { riskState.value?.switches.readOnly }

    /// The price to display for an instrument: the stream's quote with its freshness, else the REST ticker with its date.
    func price(_ id: String) -> (mark: String?, freshness: StreamFreshness?, snapshotAt: Date?) {
        if let q = quotes[id], let m = q.quote.mark ?? q.quote.mid ?? q.quote.last {
            return (m, q.freshness(connection: streamState, now: now), nil)
        }
        let t = tickers[id]
        return (t?.mark, nil, t?.ts)
    }
    func bookFreshness(_ b: LiveBook) -> StreamFreshness {
        .evaluate(freshAt: b.freshAt, serverStale: b.stale, staleAfterMs: nil, connection: streamState, now: now)
    }

    // MARK: loading

    func loadAll() async {
        async let a: Void = loadVenues()
        async let b: Void = loadLocks()
        async let c: Void = loadAccounts()
        _ = await (a, b, c)
        await loadMarket()
        await refreshAccount()
    }

    func loadVenues() async {
        venues.loading = true
        do {
            let v = try await deriv.venues().venues
            venues.set(v)
            if venue.isEmpty || !v.contains(where: { $0.id == venue }) { venue = v.first(where: { $0.restriction == nil })?.id ?? v.first?.id ?? "" }
        } catch { venues.fail(model.describe(error)) }
    }

    /// Server locks, capabilities, jurisdiction notice and the risk engine's switches: read together, each failing alone.
    func loadLocks() async {
        let live = live, monitor = monitor, risk = risk, loc = locale
        async let cfg = futAttempt { try await live.config(locale: loc) }
        async let jur = futAttempt { try await live.jurisdiction() }
        async let cap = futAttempt { try await monitor.health() }
        async let rs = futAttempt { try await risk.state() }
        switch await cfg { case .success(let v): config.set(v); case .failure(let e): config.fail(model.describe(e)) }
        switch await jur { case .success(let v): jurisdiction.set(v); case .failure(let e): jurisdiction.fail(model.describe(e)) }
        switch await cap {
        case .success(let v): if let c = v.capabilities { capabilities.set(c) } else { capabilities.fail("Le serveur n’a pas publié ses capacités.") }
        case .failure(let e): capabilities.fail(model.describe(e))
        }
        switch await rs { case .success(let v): riskState.set(v); case .failure(let e): riskState.fail(model.describe(e)) }
    }

    func loadRiskState() async {
        do { riskState.set(try await risk.state()) } catch { riskState.fail(model.describe(error)) }
    }

    func loadAccounts() async {
        let deriv = deriv, live = live
        async let p = futAttempt { try await deriv.paperAccounts() }
        async let l = futAttempt { try await live.accounts() }
        switch await p {
        case .success(let v):
            paperAccounts.set(v)
            if paperId == nil || !v.contains(where: { $0.id == paperId }) { paperId = v.first?.id }
        case .failure(let e): paperAccounts.fail(model.describe(e))
        }
        switch await l { case .success(let v): liveAccounts.set(v); case .failure(let e): liveAccounts.fail(model.describe(e)) }
    }

    func loadMarket() async {
        guard !venue.isEmpty else { return }
        let v = venue
        instruments.loading = true
        do {
            let a = try await deriv.instruments(venue: v, locale: locale)
            guard v == venue else { return }
            instruments.set(a.instruments.filter { $0.venue == v }); venueErrors = a.errors ?? []
        } catch { if v == venue { instruments.fail(model.describe(error)) } }
        await refreshTickers()
    }

    func refreshTickers() async {
        guard !venue.isEmpty else { return }
        let v = venue
        do {
            let a = try await deriv.tickers(venue: v)
            guard v == venue else { return }
            tickers = Dictionary(a.tickers.map { ($0.instrument, $0) }, uniquingKeysWith: { _, b in b })
            tickersAt = Date(); tickersError = a.errors?.first { $0.venue == v }?.message
        } catch { if v == venue { tickersError = model.describe(error) } }
    }

    /// Reads the account of the current mode. The previous value stays on screen with the error when a refresh fails.
    func refreshAccount() async {
        switch mode {
        case .paper:
            guard let id = paperId else { return }
            paperDetail.loading = true
            do { let d = try await deriv.paperAccount(id); if id == paperId { paperDetail.set(d); resubscribe() } }
            catch { if id == paperId { paperDetail.fail(model.describe(error)) } }
        case .testnet, .mainnet:
            guard let net = mode.network, let a = liveAccounts.value?.first(where: { $0.network == net }) else { return }
            liveDetail.loading = true
            do { let d = try await live.account(a.id); if mode.network == net { liveDetail.set(d); resubscribe() } }
            catch { if mode.network == net { liveDetail.fail(model.describe(error)) } }
        }
    }

    /// An operation answered the account again: show that answer without another round trip.
    func adopt(_ d: LiveAccountDetail) { if d.account.network == mode.network { liveDetail.set(d) } }
    func adopt(_ d: PaperAccountDetail) { if d.account.id == paperId { paperDetail.set(d) } }

    // MARK: stream

    func startStream() {
        guard streamTask == nil else { return }
        let s = stream
        streamTask = Task { [weak self] in
            let events = await s.events()
            guard !Task.isCancelled else { return }
            await s.start()
            for await e in events { guard let self else { return }; self.handle(e) }
        }
        flushTask = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                n += 1
                self.flush(advanceClock: n % 4 == 0)
            }
        }
        resubscribe()
    }

    /// Leaving the screen: the socket is closed; whatever was held stops reading « live » at once.
    func stopStream() {
        streamTask?.cancel(); streamTask = nil
        flushTask?.cancel(); flushTask = nil
        let s = stream
        Task { await s.stop() }
        streamState = .idle; now = Date()
    }

    /// The rows the markets list shows first (its own sort and filter): they get a live quote.
    func setLiveRows(_ ids: [String]) {
        let cut = Array(ids.prefix(Self.liveRows))
        guard cut != listIds else { return }
        listIds = cut
        resubscribe()
    }

    private func resubscribe() {
        var want = Set(listIds.map { StreamChannel.quote($0) })
        for p in currentPaperDetail?.account.positions ?? [] { want.insert(.quote(p.instrument)) }
        for p in currentLiveDetail?.venueState.positions ?? [] { want.insert(.quote(p.instrument)) }
        if let id = instrumentId {
            want.insert(.quote(id)); want.insert(.trades(id)); want.insert(.candle(id, interval: chartInterval.rawValue))
            if venueInfo(String(id.prefix { $0 != ":" }))?.orderBook != false { want.insert(.book(id, depth: 20)) }
        }
        want = want.filter(\.isValid)
        guard want != channels else { return }
        let add = Array(want.subtracting(channels)), remove = Array(channels.subtracting(want))
        channels = want
        let s = stream, previous = subscriptionTask
        subscriptionTask = Task { [weak self] in
            await previous?.value
            await s.unsubscribe(remove)
            do { try await s.subscribe(add); self?.streamError = nil }
            catch QuoteStreamError.tooManySubscriptions(let limit) { self?.streamError = "Le flux en direct est limité à \(limit) abonnements : certaines lignes affichent l’instantané." }
            catch { self?.streamError = "Abonnement refusé par le flux : \(error)" }
        }
    }

    private func handle(_ e: QuoteStreamEvent) {
        switch e {
        case .state(let s): streamState = s; now = Date()
        case .quote(let q): pending[q.id] = q
        case .book(let b): if b.id == instrumentId { pendingBook = b }
        case .bookResync(let key): if let id = instrumentId, key == StreamChannel.book(id, depth: 20).key { pendingBook = nil; book = nil }
        case .trades(let id, let t, _): if id == instrumentId { trades = Array((t.reversed() + trades).prefix(40)) }
        case .candle(let m, _): if m.id == instrumentId, m.interval == chartInterval.rawValue { lastCandle = m }
        case .error(let m):
            if let ch = m.channel { channelRefusals[ch.key] = "\(m.message) [\(m.code)]" } else { streamError = "\(m.message) [\(m.code)]" }
        case .stale: now = Date()
        default: break
        }
    }

    private func flush(advanceClock: Bool) {
        if !pending.isEmpty { quotes.merge(pending) { _, b in b }; pending = [:] }
        if let b = pendingBook { book = b; pendingBook = nil }
        if advanceClock { now = Date() }
    }

    func refusal(of channel: StreamChannel) -> String? { channelRefusals[channel.key] }

    var streamText: String {
        switch streamState {
        case .idle: "Flux en direct arrêté"
        case .connecting: "Connexion au flux en direct…"
        case .live: "Flux en direct connecté"
        case .reconnecting(let attempt, let delay): "Flux interrompu — nouvelle tentative \(attempt) dans \(max(1, delay / 1000)) s ; les prix affichés ne sont plus en direct"
        case .ended(.signedOut), .ended(.unauthorized): "Flux fermé : session terminée"
        case .ended(.refused(let status)): "Flux refusé par le serveur (\(status))"
        }
    }
}

/// One of several concurrent reads that must each fail alone.
func futAttempt<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await body()) } catch { return .failure(error) }
}
