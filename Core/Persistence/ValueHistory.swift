// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Core/Persistence/ValueHistory.swift
// Description: The portfolio's estimated total as THIS Mac observed it over time (the server keeps no such series). Each point is an estimate (balances × displayed prices) taken when the app was open; gaps are real gaps. Stored in the sandbox container, excluded from backups.
import Foundation
import SPWalletCore

struct ValuePoint: Codable, Sendable, Identifiable { let at: Date; let value: Double; let currency: String; let complete: Bool; var id: Date { at } }

actor ValueHistory {
    static let shared = ValueHistory()
    private var points: [ValuePoint] = []
    private var loaded = false
    private var url: URL { AppEnvironment.supportDirectory.appendingPathComponent("snapshots/value-history.json") }

    private func load() {
        guard !loaded else { return }; loaded = true
        if let d = try? Data(contentsOf: url), let p = try? APICoding.decoder().decode([ValuePoint].self, from: d) { points = p }
    }
    /// One point per 10 minutes at most; two years kept.
    func record(_ p: Portfolio, currency: FiatCurrency) {
        load()
        guard p.prices != nil else { return }
        let t = p.estimatedTotal(in: currency)
        if let last = points.last, last.currency == currency.rawValue, p.asOf.timeIntervalSince(last.at) < 600 { return }
        points.append(ValuePoint(at: p.asOf, value: t.value, currency: currency.rawValue, complete: t.complete))
        let cutoff = Date().addingTimeInterval(-730 * 86400); points.removeAll { $0.at < cutoff }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? APICoding.encoder().encode(points) { try? d.write(to: url, options: [.atomic, .completeFileProtection]) }
    }
    func series(currency: FiatCurrency, since: Date) -> [ValuePoint] { load(); return points.filter { $0.currency == currency.rawValue && $0.at >= since } }
}
