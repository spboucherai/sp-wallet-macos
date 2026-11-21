// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Components/SecurityIndicator.swift
// Description      : A compact, always-truthful summary of whether signing is
//                    possible: signer reachable, halt state, session,
//                    connection.
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

struct SecurityIndicator: View {
    let model: AppModel
    var compact = false

    enum Level { case ok, degraded, blocked, unknown
        var color: Color { switch self { case .ok: Theme.positive; case .degraded: Theme.warning; case .blocked: Theme.negative; case .unknown: .secondary } }
        var symbol: String { switch self { case .ok: "checkmark.shield.fill"; case .degraded: "exclamationmark.shield.fill"; case .blocked: "xmark.shield.fill"; case .unknown: "shield" } }
    }
    static func assess(_ model: AppModel) -> (Level, String) {
        if model.phase == .offlineBrowse { return (.unknown, "Hors connexion — lecture seule") }
        if model.isOffline { return (.degraded, "Portefeuille injoignable") }
        guard let p = model.portfolio?.value else { return (.unknown, "État inconnu") }
        if p.halted == true { return (.blocked, "Arrêt d’urgence actif") }
        if p.signer?.reachable == false || p.halted == nil { return (.degraded, "Signataire injoignable") }
        return (.ok, "Signataire isolé joignable")
    }
    var body: some View {
        let (level, text) = Self.assess(model)
        HStack(spacing: 6) {
            Image(systemName: level.symbol).foregroundStyle(level.color)
            Text(text).font(compact ? .caption : .callout).lineLimit(1)
        }
        .help("Les clés privées ne quittent jamais la machine du signataire ; ce Mac n’en détient aucune.")
        .accessibilityElement(children: .combine)
    }
}
