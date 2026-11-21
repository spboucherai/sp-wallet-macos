// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Core/Models/Formatting.swift
// Description      : Display helpers. Crypto amounts are the server's exact
//                    decimal strings (grouped for reading, never rounded
//                    through floating point); fiat values are estimates and
//                    always rendered with the ≈ sign.
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

enum Fmt {
    /// Groups the integer part of an exact decimal string ("1234567.89" → "1 234 567,89" in fr). No digit is added or removed.
    static func amount(_ exact: String?, maxFraction: Int? = nil) -> String {
        guard let exact, !exact.isEmpty else { return "—" }
        let neg = exact.hasPrefix("-"); let body = neg ? String(exact.dropFirst()) : exact
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var intPart = String(parts[0]); var frac = parts.count > 1 ? String(parts[1]) : ""
        var truncated = false
        if let m = maxFraction, frac.count > m { frac = String(frac.prefix(m)); truncated = true }
        var grouped = ""; for (i, ch) in intPart.reversed().enumerated() { if i > 0, i % 3 == 0 { grouped.append("\u{202F}") }; grouped.append(ch) }
        intPart = String(grouped.reversed())
        let sep = Locale.current.decimalSeparator ?? ","
        return (neg ? "−" : "") + intPart + (frac.isEmpty ? "" : sep + frac) + (truncated ? "…" : "")
    }

    static func fiat(_ v: Double?, _ c: FiatCurrency, estimate: Bool = true) -> String {
        guard let v else { return "—" }
        let s = v.formatted(.currency(code: c.rawValue).precision(.fractionLength(abs(v) < 1 && v != 0 ? 4 : 2)))
        return estimate ? "≈ " + s : s
    }
    static func price(_ v: Double?, _ c: FiatCurrency) -> String {
        guard let v else { return "—" }
        let digits = v >= 100 ? 2 : v >= 1 ? 4 : 6
        return v.formatted(.currency(code: c.rawValue).precision(.fractionLength(2...digits)))
    }
    static func percent(_ v: Double?) -> String {
        guard let v else { return "—" }
        return (v >= 0 ? "+" : "−") + abs(v).formatted(.number.precision(.fractionLength(2))) + " %"
    }
    static func compact(_ v: Double?, _ c: FiatCurrency) -> String {
        guard let v else { return "—" }
        return v.formatted(.currency(code: c.rawValue).notation(.compactName).precision(.fractionLength(0...2)))
    }
    static func date(_ d: Date?) -> String { d.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—" }
    static func dateSeconds(_ d: Date?) -> String { d.map { $0.formatted(date: .numeric, time: .standard) } ?? "—" }
    static func relative(_ d: Date?) -> String { d.map { $0.formatted(.relative(presentation: .named)) } ?? "—" }

    /// "0x1234…abcd" — for lists only. Review screens always show the full address.
    static func short(_ address: String?, head: Int = 8, tail: Int = 6) -> String {
        guard let a = address else { return "—" }
        return a.count <= head + tail + 1 ? a : "\(a.prefix(head))…\(a.suffix(tail))"
    }
    /// A full address in groups of four characters, for character-by-character verification.
    static func chunked(_ address: String) -> String {
        var out = ""; for (i, ch) in address.enumerated() { if i > 0, i % 4 == 0 { out.append(" ") }; out.append(ch) }
        return out
    }
}

extension JSONValue {
    /// A compact human rendering of unknown server data (policy values, audit details): shown verbatim, never interpreted.
    var displayText: String {
        switch self {
        case .string(let s): return s
        case .null: return "—"
        default:
            guard let d = try? APICoding.encoder().encode(self), let s = String(data: d, encoding: .utf8) else { return "?" }
            return s
        }
    }
    func str(_ k: String) -> String? { self[k]?.stringValue }
}
