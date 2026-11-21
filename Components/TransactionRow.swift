// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Components/TransactionRow.swift
// Description      : One row of history. The status says exactly what the chain
//                    said: 'diffusée' is not 'confirmée', and only a finalized
//                    transaction is shown as a success.
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

struct StatusPill: View {
    let raw: String
    var body: some View {
        let s = ProposalState(rawValue: raw)
        let color: Color = raw == "finalized" ? Theme.positive : (s?.isFailure == true || s == .notBroadcast) ? Theme.negative : Theme.warning
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(ErrorText.activityState(raw)).font(.caption.weight(.medium)).foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule())
    }
}

struct TransactionRow: View {
    let item: ActivityItem
    static func kindTitle(_ k: String) -> String {
        switch k { case "send": "Envoi"; case "receive": "Réception"; case "swap": "Échange"; case "bridge": "Pont"; case "gmx": "Ordre GMX"; case "nft": "Transfert NFT"; default: k }
    }
    static func kindSymbol(_ k: String) -> String {
        switch k { case "send": "arrow.up.right"; case "receive": "arrow.down.left"; case "swap": "arrow.left.arrow.right"; case "bridge": "point.topleft.down.to.point.bottomright.curvepath"; default: "doc.text" }
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.kindSymbol(item.kind)).font(.system(size: 12, weight: .bold)).foregroundStyle(item.isIncoming ? Theme.positive : Theme.azure)
                .frame(width: 32, height: 32).background((item.isIncoming ? Theme.positive : Theme.azure).opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Self.kindTitle(item.kind)) · \(item.networkName ?? item.network)").fontWeight(.medium)
                Text(Fmt.date(item.at) + (item.isIncoming ? (item.from.map { " · de \(Fmt.short($0))" } ?? "") : (item.to.map { " · vers \(Fmt.short($0))" } ?? ""))).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(raw: item.state)
            Text("\(item.isIncoming ? "+" : "−")\(Fmt.amount(item.amountDisplay, maxFraction: 8)) \(item.symbol)").monospacedDigit().frame(minWidth: 150, alignment: .trailing)
        }
        .padding(.vertical, 3).accessibilityElement(children: .combine)
    }
}
