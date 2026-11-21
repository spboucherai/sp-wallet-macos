// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Core/Persistence/ValueHistory.swift
// Description      : The portfolio's estimated total as THIS Mac observed it
//                    over time (the server keeps no such series). Each point is
//                    an estimate (balances × displayed prices) taken when the
//                    app was open; gaps are real gaps. Stored in the sandbox
//                    container, excluded from backups.
// Module           : Core
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
