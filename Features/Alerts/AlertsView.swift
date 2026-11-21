// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Features/Alerts/AlertsView.swift
// Description      : Entry of the alerts and monitoring centre: the server's
//                    alerts (live), the alert settings, the read-only
//                    monitoring of capital / PnL / exposure / system health,
//                    and the unified timeline of operations. Read-only except
//                    for read marks and the owner's alert settings; nothing
//                    here moves funds.
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

import SwiftUI
import SPWalletCore

struct AlertsView: View {
    let model: AppModel
    enum Tab: String, CaseIterable, Identifiable {
        case alerts, settings, monitor, timeline
        var id: String { rawValue }
        var label: String { switch self { case .alerts: "Alertes"; case .settings: "Réglages"; case .monitor: "Supervision"; case .timeline: "Opérations" } }
    }
    @State private var tab: Tab = .alerts
    @State private var center: AlertsCenter?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Alertes et supervision").font(.largeTitle.weight(.semibold))
                if let c = center?.counters, c.unread > 0 {
                    Text(c.critical > 0 ? "\(c.unread) non lues · \(c.critical) critiques" : "\(c.unread) non lues").font(.callout.weight(.medium))
                        .foregroundStyle(c.critical > 0 ? Theme.negative : Theme.warning)
                        .padding(.horizontal, 8).padding(.vertical, 3).background((c.critical > 0 ? Theme.negative : Theme.warning).opacity(0.13), in: Capsule())
                }
                Spacer()
                Picker("Section", selection: $tab) { ForEach(Tab.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 440)
            }.padding([.horizontal, .top], 24).padding(.bottom, 10)
            if !model.canOperate { Banner(.warning, "Hors ligne ou session absente : les dernières données lues sont affichées avec leur date ; aucun réglage ne peut être modifié.").padding(.horizontal, 24).padding(.bottom, 8) }
            Divider()
            if let center {
                switch tab {
                case .alerts: AlertsListTab(model: model, center: center)
                case .settings: AlertsSettingsTab(model: model)
                case .monitor: OpsMonitorTab(model: model)
                case .timeline: OpsTimelineTab(model: model)
                }
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            let c = AlertsCenter.shared(model); center = c
            c.setVisible(true)
            await c.reload()
        }
        .onDisappear { center?.setVisible(false) }
    }
}

/// A section header with the date its figures were read at — every monitoring block carries its own.
struct OpsAsOf: View {
    let date: Date?
    var prefix = "Lu"
    var body: some View {
        if let date { Text("\(prefix) \(Fmt.relative(date)) · \(Fmt.dateSeconds(date))").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
    }
}

/// The honest empty state of a section whose source failed: unavailable, with the reason — never a zero.
struct OpsUnavailable: View {
    let what: String
    let reason: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProvenanceTag(p: .unavailable)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(what) : indisponible").fontWeight(.medium)
                Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Spacer()
            if let retry { Button("Réessayer", action: retry) }
        }
    }
}

/// Which money a figure is about. Real, test-network and simulated books never share a colour or a label.
enum OpsBookKind: Equatable {
    case real, testnet, paper, research, unknown(String)
    init(mode: String?) {
        switch mode?.lowercased() {
        case "live", "live-mainnet", "mainnet": self = .real
        case "live-testnet", "testnet": self = .testnet
        case "paper": self = .paper
        case "research": self = .research
        case let m?: self = .unknown(m)
        case nil: self = .unknown("")
        }
    }
    var label: String {
        switch self { case .real: "Réel"; case .testnet: "Testnet (fonds de test)"; case .paper: "Papier (simulé)"; case .research: "Recherche (backtest)"; case .unknown(let m): m.isEmpty ? "Mode non précisé" : m }
    }
    var color: Color { switch self { case .real: .orange; case .testnet: .purple; case .paper: .blue; case .research: .teal; case .unknown: .secondary } }
    var symbol: String { switch self { case .real: "banknote"; case .testnet: "hammer"; case .paper: "testtube.2"; case .research: "chart.xyaxis.line"; case .unknown: "questionmark.circle" } }
    var isSimulated: Bool { self == .paper || self == .research }
}

struct OpsBookTag: View {
    let kind: OpsBookKind
    var body: some View {
        Label(kind.label, systemImage: kind.symbol).font(.caption.weight(.medium)).foregroundStyle(kind.color)
            .padding(.horizontal, 7).padding(.vertical, 3).background(kind.color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(kind.color.opacity(kind.isSimulated ? 0.55 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}

enum OpsFmt {
    /// A USD figure the server computed (an estimate in the server's rounding). nil is "—", never zero.
    static func usd(_ v: Double?) -> String { v.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(2))) } ?? "—" }
    static func signedUsd(_ v: Double?) -> String {
        guard let v else { return "—" }
        return (v > 0 ? "+" : v < 0 ? "−" : "") + abs(v).formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
    static func number(_ v: Double?, digits: Int = 2) -> String { v.map { $0.formatted(.number.precision(.fractionLength(0...digits))) } ?? "—" }
    /// A fraction (0.0123) as a signed percentage.
    static func fraction(_ v: Double?, digits: Int = 2) -> String {
        guard let v else { return "—" }
        return (v > 0 ? "+" : v < 0 ? "−" : "") + abs(v * 100).formatted(.number.precision(.fractionLength(digits))) + " %"
    }
    static func age(seconds: Double?) -> String {
        guard let s = seconds else { return "—" }
        if s < 90 { return "\(Int(s)) s" }
        if s < 5400 { return "\(Int(s / 60)) min" }
        if s < 172_800 { return "\(Int(s / 3600)) h" }
        return "\(Int(s / 86_400)) j"
    }
    static func duration(ms: Double?) -> String { age(seconds: ms.map { $0 / 1000 }) }
}
