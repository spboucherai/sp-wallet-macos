// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Components/BalanceCard.swift
// Description      : The portfolio's estimated total on the app's hero surface:
//                    an estimate by construction (on-chain balances × displayed
//                    prices), labelled as such, with its sources, its age and
//                    what is missing from it. Optional shortcut actions sit
//                    beside it.
// Module           : Components
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

struct BalanceCard: View {
    let model: AppModel
    var nav: Navigator?

    var body: some View {
        HeroCard {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("VALEUR TOTALE ESTIMÉE").font(.caption.weight(.semibold)).tracking(1.2).opacity(0.75)
                        tag
                    }
                    figure
                    footnote
                }
                Spacer(minLength: 12)
                if let nav {
                    HStack(spacing: 6) {
                        QuickAction(symbol: "arrow.up.right", title: "Envoyer", onDark: true) { nav.section = .send }.disabled(!model.canOperate).opacity(model.canOperate ? 1 : 0.45)
                        QuickAction(symbol: "arrow.down.left", title: "Recevoir", onDark: true) { nav.section = .receive }
                        QuickAction(symbol: "arrow.left.arrow.right", title: "Échanger", onDark: true) { nav.section = .swap }.disabled(!model.canOperate).opacity(model.canOperate ? 1 : 0.45)
                        QuickAction(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Pont", onDark: true) { nav.section = .bridge }.disabled(!model.canOperate).opacity(model.canOperate ? 1 : 0.45)
                    }.padding(.top, 6)
                }
            }
        }
    }

    private func chip(_ text: String, _ symbol: String, warn: Bool = false) -> some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background((warn ? Theme.warning : Color.white).opacity(warn ? 0.9 : 0.16), in: Capsule())
            .foregroundStyle(warn ? Color.black : Color.white)
    }

    @ViewBuilder private var tag: some View {
        if let src = model.portfolio {
            if src.fromCache { chip("Données du \(Fmt.date(src.fetchedAt))", "clock.badge.exclamationmark", warn: true) }
            else if !model.settings.prices || src.value.prices == nil { chip("Prix indisponibles", "xmark.octagon", warn: true) }
            else if src.value.pricesStale { chip("Certains prix périmés", "clock.badge.exclamationmark", warn: true) }
            else { chip("Estimation", "tilde") }
        }
    }

    @ViewBuilder private var figure: some View {
        if let p = model.portfolio?.value, p.prices != nil, model.settings.prices {
            let total = p.estimatedTotal(in: model.currency)
            Text(model.settings.hideBalances ? "••••••" : Fmt.fiat(total.value, model.currency)).font(Theme.figure(46)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .textSelection(.enabled)
        } else {
            Text("—").font(Theme.figure(46))
        }
    }

    @ViewBuilder private var footnote: some View {
        if let p = model.portfolio?.value {
            let total = p.estimatedTotal(in: model.currency), unread = p.balances.filter { !$0.isAvailable }.count
            let held = p.balances.filter(\.isNonZero)
            HStack(spacing: 14) {
                Label("\(held.count) actif\(held.count > 1 ? "s" : "") · \(Set(held.map(\.network)).count) réseau\(Set(held.map(\.network)).count > 1 ? "x" : "")", systemImage: "circle.hexagongrid")
                if let s = p.priceSource { Label("Prix \(s)\(p.pricesAsOf.map { " · \(Fmt.relative($0))" } ?? "")", systemImage: "chart.line.uptrend.xyaxis") }
                Label("Soldes lus \(Fmt.relative(p.asOf))", systemImage: "checkmark.seal")
            }.font(.caption).opacity(0.8).lineLimit(1)
            if !total.complete, p.prices != nil {
                Label(unread > 0 ? "Total incomplet : \(unread) solde(s) illisible(s) et/ou actifs sans prix non comptés." : "Total incomplet : certains actifs détenus n’ont pas de prix et ne sont pas comptés.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Color(red: 1, green: 0.82, blue: 0.4))
            }
        } else {
            Text("Aucune donnée synchronisée.").font(.caption).opacity(0.8)
        }
    }
}
