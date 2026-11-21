// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Components/AssetRow.swift
// Description      : One holding in a list: asset, network, exact balance as
//                    read on-chain, and the estimated fiat value with its
//                    provenance. A balance that could not be read is shown as
//                    unavailable, never as zero.
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

struct AssetRow: View {
    let balance: Balance
    let portfolio: Portfolio
    let currency: FiatCurrency
    var hide = false
    var cached = false

    var body: some View {
        let price = portfolio.prices?[balance.symbol]
        HStack(spacing: 12) {
            AssetBadge(symbol: balance.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(balance.name).fontWeight(.medium).lineLimit(1)
                Text("\(balance.symbol) · \(balance.networkName)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let price {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.price(price.value(in: currency), currency)).font(.callout).monospacedDigit()
                    HStack(spacing: 4) {
                        if price.stale { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Theme.warning).help("Prix périmé (\(Fmt.relative(price.priceAt)))") }
                        if price.divergent == true { Image(systemName: "arrow.left.and.right.circle").foregroundStyle(Theme.warning).help("Les deux sources de prix divergent") }
                        Text(Fmt.percent(price.change24h)).font(.caption).foregroundStyle(Theme.change(price.change24h)).monospacedDigit()
                    }
                }.frame(width: 104, alignment: .trailing)
            }
            VStack(alignment: .trailing, spacing: 1) {
                if balance.isAvailable {
                    Text(hide ? "••••" : "\(Fmt.amount(balance.display, maxFraction: 8)) \(balance.symbol)").monospacedDigit().fontWeight(.medium)
                    Text(hide ? "••••" : Fmt.fiat(portfolio.estimatedValue(of: balance, in: currency), currency)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Label("Indisponible", systemImage: "xmark.octagon").font(.callout).foregroundStyle(Theme.negative).help("La lecture de ce solde sur la chaîne a échoué. Ce n’est pas un solde nul.")
                }
            }.frame(width: 170, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .opacity(cached ? 0.85 : 1)
        .accessibilityElement(children: .combine)
    }
}
