// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Research/RsIndicators.swift
// Description      : The observed bars of the server's consolidated series, and
//                    the basic indicators the app DERIVES from them locally
//                    (moving averages, RSI, realized volatility, drawdown).
//                    Pure functions: bars in, numbers out. Everything computed
//                    here is a derived figure and is labelled as such on screen
//                    with its window length; none of it is market data served
//                    by the wallet.
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

/// One closed bar as served. Every field comes from the single source the bar names.
struct RsBar: Identifiable, Sendable, Equatable {
    let date: Date
    let open: Double, high: Double, low: Double, close: Double
    let volume: Double?
    let source: String?
    var id: Date { date }
    var isUp: Bool { close >= open }

    /// nil when a field is missing or not a finite number: such a bar is not drawn rather than guessed.
    init?(_ v: JSONValue) {
        func num(_ k: String) -> Double? {
            guard let x = v[k] else { return nil }
            let d = x.doubleValue ?? x.stringValue.flatMap(Double.init)
            return d.flatMap { $0.isFinite ? $0 : nil }
        }
        guard let ts = num("ts"), let o = num("open"), let h = num("high"), let l = num("low"), let c = num("close"), ts > 0 else { return nil }
        date = Date(timeIntervalSince1970: ts > 1e11 ? ts / 1000 : ts)
        open = o; high = h; low = l; close = c; volume = num("volume"); source = v["source"]?.stringValue
    }
}

struct RsPoint: Identifiable, Sendable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

enum RsIndicators {
    /// Simple moving average of the closes over `window` bars; the first point is at bar `window`.
    static func sma(_ bars: [RsBar], window: Int) -> [RsPoint] {
        guard window > 0, bars.count >= window else { return [] }
        var out: [RsPoint] = []; out.reserveCapacity(bars.count - window + 1)
        var sum = bars[0..<window].reduce(0) { $0 + $1.close }
        out.append(RsPoint(date: bars[window - 1].date, value: sum / Double(window)))
        for i in window..<bars.count {
            sum += bars[i].close - bars[i - window].close
            out.append(RsPoint(date: bars[i].date, value: sum / Double(window)))
        }
        return out
    }

    /// Exponential moving average (smoothing 2 / (window + 1)), seeded with the simple average of the first `window` closes.
    static func ema(_ bars: [RsBar], window: Int) -> [RsPoint] {
        guard window > 0, bars.count >= window else { return [] }
        let k = 2.0 / Double(window + 1)
        var value = bars[0..<window].reduce(0) { $0 + $1.close } / Double(window)
        var out = [RsPoint(date: bars[window - 1].date, value: value)]
        for i in window..<bars.count { value = bars[i].close * k + value * (1 - k); out.append(RsPoint(date: bars[i].date, value: value)) }
        return out
    }

    /// Relative strength index with Wilder's smoothing over `window` bars (0…100).
    static func rsi(_ bars: [RsBar], window: Int) -> [RsPoint] {
        guard window > 0, bars.count > window else { return [] }
        var gain = 0.0, loss = 0.0
        for i in 1...window { let d = bars[i].close - bars[i - 1].close; if d >= 0 { gain += d } else { loss -= d } }
        gain /= Double(window); loss /= Double(window)
        func value() -> Double { loss == 0 ? (gain == 0 ? 50 : 100) : 100 - 100 / (1 + gain / loss) }
        var out = [RsPoint(date: bars[window].date, value: value())]
        if bars.count > window + 1 {
            for i in (window + 1)..<bars.count {
                let d = bars[i].close - bars[i - 1].close
                gain = (gain * Double(window - 1) + max(d, 0)) / Double(window)
                loss = (loss * Double(window - 1) + max(-d, 0)) / Double(window)
                out.append(RsPoint(date: bars[i].date, value: value()))
            }
        }
        return out
    }

    /// Sample standard deviation of the last `window` close-to-close log returns, annualized with `periodsPerYear`. nil when there are not enough bars.
    static func realizedVolatility(_ bars: [RsBar], window: Int, periodsPerYear: Double) -> Double? {
        guard window > 1, bars.count > window else { return nil }
        let tail = bars.suffix(window + 1).map(\.close)
        guard tail.allSatisfy({ $0 > 0 }) else { return nil }
        var returns: [Double] = []
        for i in 1..<tail.count { returns.append(Foundation.log(tail[i] / tail[i - 1])) } // `log` alone is the app's Logger
        let mean: Double = returns.reduce(0, +) / Double(returns.count)
        var squares = 0.0
        for r in returns { squares += (r - mean) * (r - mean) }
        let variance: Double = squares / Double(returns.count - 1)
        return (variance * periodsPerYear).squareRoot()
    }

    /// Decline of each close from the highest close seen so far in the displayed window (0 or negative fraction).
    static func drawdown(_ bars: [RsBar]) -> [RsPoint] {
        var peak = -Double.infinity
        return bars.compactMap { b in
            peak = max(peak, b.close)
            return peak > 0 ? RsPoint(date: b.date, value: b.close / peak - 1) : nil
        }
    }

    /// Bars per year for a market that trades around the clock, every day (the server's consolidated crypto series).
    static func periodsPerYear(interval: String) -> Double? {
        switch interval { case "5m": 105_120; case "1h": 8_760; case "4h": 2_190; case "1d": 365; default: nil }
    }
    static func intervalSeconds(_ interval: String) -> TimeInterval? {
        switch interval { case "5m": 300; case "1h": 3_600; case "4h": 14_400; case "1d": 86_400; default: nil }
    }
}

enum RsFmt {
    /// A decimal string of the server parsed for DISPLAY of market data only (never an amount to sign).
    static func double(_ s: String?) -> Double? { s.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil } }
    static func price(_ v: Double?) -> String {
        guard let v else { return "—" }
        let digits = abs(v) >= 1000 ? 2 : abs(v) >= 1 ? 4 : 8
        return v.formatted(.number.precision(.fractionLength(2...digits)))
    }
    static func price(_ s: String?) -> String { s == nil ? "—" : (double(s).map { price($0) } ?? s!) }
    static func compactUsd(_ s: String?) -> String {
        guard let v = double(s) else { return "—" }
        return v.formatted(.currency(code: "USD").notation(.compactName).precision(.fractionLength(0...2)))
    }
    /// A fraction served as a decimal string (0.0123) → signed percentage.
    static func fraction(_ s: String?, digits: Int = 2) -> String { OpsFmt.fraction(double(s), digits: digits) }
    static func bps(_ s: String?) -> String { double(s).map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) pb" } ?? "—" }
    static func age(ms: Int?) -> String { OpsFmt.duration(ms: ms.map(Double.init)) }
    static func date(ms: JSONValue?) -> Date? {
        guard let v = ms else { return nil }
        if let d = v.doubleValue, d > 0 { return Date(timeIntervalSince1970: d > 1e11 ? d / 1000 : d) }
        return v.stringValue.flatMap(ISO8601.parse)
    }
    static func metric(_ v: Double?, digits: Int = 2) -> String { v.map { $0.formatted(.number.precision(.fractionLength(digits))) } ?? "—" }
}
