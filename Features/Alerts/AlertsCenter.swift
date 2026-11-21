// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Alerts/AlertsCenter.swift
// Description      : The state of the alerts centre: the server's alert rows
//                    with their filters and paging, read marks, the live watch
//                    (the Core's SSE stream of unread counters while the screen
//                    is open, a slow poll of the same counters otherwise) and
//                    the macOS notifications of NEW alerts. Every alert shown
//                    or notified is a row the server returned; nothing is
//                    deduced locally.
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

import AppKit
import Foundation
import SPWalletCore

@MainActor @Observable final class AlertsCenter {
    enum Live: Equatable {
        case idle
        /// App in the background, offline or signed out: nothing is fetched.
        case paused
        case connecting
        case streaming(since: Date)
        case reconnecting(at: Date, reason: String)
        /// The screen is closed: only the unread counters are read, once a minute.
        case polling
    }

    private static var current: AlertsCenter?
    /// One centre per app model: the watch and the notification memory survive the screen being closed and reopened.
    static func shared(_ model: AppModel) -> AlertsCenter {
        if let c = current, c.model === model { return c }
        let c = AlertsCenter(model: model); current = c; return c
    }

    let model: AppModel
    private let api: AlertsAPI
    /// Alerts older than this are never notified (the app was not running when they happened).
    private let launchedAt = NSRunningApplication.current.launchDate ?? Date()
    private static let pageSize = 100, snapshotKey = "alerts.page"

    // list
    private(set) var items: [WalletAlert] = []
    private(set) var counters: AlertUnread?
    private(set) var loadedAt: Date?
    private(set) var fromCache = false
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var reachedEnd = false
    private(set) var marking = false
    var error: String?

    // filters: severity, group and unread are the server's; the subject is applied to the rows already loaded
    var severity: AlertSeverity? { didSet { if severity != oldValue { Task { await reload() } } } }
    var group: AlertGroup? { didSet { if group != oldValue { Task { await reload() } } } }
    var unreadOnly = false { didSet { if unreadOnly != oldValue { Task { await reload() } } } }
    var theme: AlertsTheme?

    // live
    private(set) var live: Live = .idle
    private var visible = false
    private var watchTask: Task<Void, Never>?
    private var highestSeen: Int64 = 0
    private var notified: Set<Int64> = []
    private var loadGeneration = 0

    private init(model: AppModel) { self.model = model; api = AlertsAPI(model.client) }

    var shown: [WalletAlert] { guard let t = theme else { return items }; return items.filter { AlertsTheme.of($0).contains(t) } }
    private var query: AlertListQuery { AlertListQuery(limit: Self.pageSize, severity: severity, group: group, unreadOnly: unreadOnly) }
    private var isUnfiltered: Bool { severity == nil && group == nil && !unreadOnly }

    // MARK: - Reading

    func reload() async {
        loadGeneration += 1; let generation = loadGeneration
        loading = true; defer { if generation == loadGeneration { loading = false } }
        do {
            let page = try await api.list(query)
            guard generation == loadGeneration else { return }
            items = page.items; counters = page.counters; reachedEnd = page.items.count < Self.pageSize
            loadedAt = Date(); fromCache = false; error = nil
            if isUnfiltered { await SnapshotStore.shared.save(page, as: Self.snapshotKey); noteNew(page.items) }
        } catch {
            guard generation == loadGeneration else { return }
            self.error = model.describe(error)
            if items.isEmpty, isUnfiltered, let snap: Snapshot<AlertPage> = await SnapshotStore.shared.load(Self.snapshotKey) {
                items = snap.value.items; counters = snap.value.counters; loadedAt = snap.savedAt; fromCache = true; reachedEnd = true
            } else if !items.isEmpty { fromCache = true }
        }
    }

    func loadMore() async {
        guard !loadingMore, !reachedEnd, !fromCache, let last = items.last else { return }
        loadingMore = true; defer { loadingMore = false }
        let generation = loadGeneration
        var q = query; q.before = last.id
        do {
            let page = try await api.list(q)
            guard generation == loadGeneration else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            counters = page.counters; reachedEnd = page.items.count < Self.pageSize; error = nil
        } catch { self.error = model.describe(error) }
    }

    // MARK: - Read marks

    func markRead(_ ids: [Int64]) async {
        let unread = ids.filter { id in items.first { $0.id == id }?.isRead == false }
        guard !unread.isEmpty, model.canOperate, !marking else { return }
        marking = true; defer { marking = false }
        do {
            var start = 0
            while start < unread.count { // the server takes at most 500 ids per call
                let end = min(start + 500, unread.count)
                counters = try await api.markRead(ids: Array(unread[start..<end])); start = end
            }
            await reload() // the read dates shown are the server's
        } catch { self.error = model.describe(error) }
    }

    func markAllRead() async {
        guard model.canOperate, !marking else { return }
        marking = true; defer { marking = false }
        do { counters = try await api.markAllRead(); await reload() } catch { self.error = model.describe(error) }
    }

    // MARK: - Live watch

    /// Called when the alerts screen appears / disappears. The stream only runs while it is on screen.
    func setVisible(_ v: Bool) {
        visible = v
        if v { start() }
    }

    /// Starts the watch if it is not running. Safe to call from the app shell at sign-in so that notifications do not wait for the screen to be opened once.
    func start() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            var backoff = OpsBackoff()
            while !Task.isCancelled {
                guard let self else { return }
                guard AppActivity.isActive, self.model.canOperate else {
                    self.live = .paused
                    try? await Task.sleep(for: .seconds(3)); continue
                }
                if self.visible {
                    let outcome = await self.runStream()
                    if Task.isCancelled { return }
                    guard self.visible, AppActivity.isActive, self.model.canOperate else { continue }
                    if outcome.delivered { backoff.reset() }
                    let wait = outcome.delivered && outcome.reason == nil ? Duration.seconds(1) : backoff.next() // a stream the server ended on schedule is reopened at once
                    self.live = .reconnecting(at: Date().addingTimeInterval(Double(wait.components.seconds)), reason: outcome.reason ?? "Flux terminé par le serveur (durée maximale de dix minutes).")
                    try? await Task.sleep(for: wait)
                } else {
                    self.live = .polling
                    if let u = try? await self.api.unread() { await self.received(u) }
                    for _ in 0..<30 { // one minute, leaving early when the screen opens
                        if Task.isCancelled || self.visible { break }
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }
        }
    }

    func stop() { watchTask?.cancel(); watchTask = nil; live = .idle }

    private struct StreamOutcome { var delivered = false; var reason: String? }

    /// One connection of the SSE stream; returns when it ends, fails, or the screen / the app stops deserving it.
    private func runStream() async -> StreamOutcome {
        guard let request = await api.streamRequest() else { return StreamOutcome(reason: "Session absente.") }
        live = .connecting
        // the stream is dropped as soon as the screen closes, the app goes to the background, or the session is lost
        let keep: @MainActor @Sendable () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.visible && AppActivity.isActive && self.model.canOperate
        }
        var out = StreamOutcome()
        do {
            for try await event in OpsEventStream.events(request, while: keep) {
                if !out.delivered { out.delivered = true; live = .streaming(since: Date()) }
                if case .unread(let u)? = AlertStreamEvent(event) { await received(u) }
            }
        } catch { out.reason = model.describe(error) }
        return out
    }

    /// New counters from the stream or the poll: refresh what is on screen and look for alerts to notify.
    private func received(_ u: AlertUnread) async {
        let changed = counters != u
        counters = u
        if u.lastId > highestSeen { await fetchNew() }
        if changed, visible { await reload() }
    }

    /// The newest rows, unfiltered, only to find the ones that appeared since the last look.
    private func fetchNew() async {
        guard let page = try? await api.list(AlertListQuery(limit: 50)) else { return }
        noteNew(page.items)
    }

    // MARK: - Notifications

    /// Raises one macOS notification per alert that is new, unread, created after the app's launch and at or above the owner's
    /// threshold. The text is the alert's own sentence from the catalogue (the backend's template) — never a paraphrase.
    private func noteNew(_ rows: [WalletAlert]) {
        let fresh = rows.filter { $0.id > highestSeen }
        highestSeen = max(highestSeen, rows.map(\.id).max() ?? 0)
        let level = AlertsNotifyLevel.stored
        let candidates = fresh.filter { !$0.isRead && $0.ts >= launchedAt && !notified.contains($0.id) && level.allows($0.severity) }.sorted { $0.id < $1.id }
        guard !candidates.isEmpty, Notifier.enabled else { candidates.forEach { notified.insert($0.id) }; return }
        // a burst is summarised rather than stacking dozens of banners; criticals always get their own
        let individually = candidates.filter { $0.severity >= .critical } + candidates.filter { $0.severity < .critical }.suffix(3)
        let shownIds = Set(individually.map(\.id))
        for a in candidates where shownIds.contains(a.id) {
            let t = AlertsText.sentence(a, detail: AlertsNotifyLevel.showDetails)
            let prefix = a.severity >= .critical ? "Critique — " : ""
            Notifier.post(title: prefix + t.title, body: t.body.isEmpty ? AlertsText.group(a.group) : t.body, id: "alert-\(a.id)")
        }
        let rest = candidates.count - shownIds.count
        if rest > 0 { Notifier.post(title: "\(rest) autres alertes", body: "Ouvrez le centre d’alertes de SP Wallet pour les lire.", id: "alert-burst-\(highestSeen)") }
        candidates.forEach { notified.insert($0.id) }
    }
}
