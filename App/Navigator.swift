// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : App/Navigator.swift
// Description      : The sidebar's sections and the current selection. Sections
//                    are fixed by the product; what each one offers is decided
//                    by what the backend really supports (each screen says so
//                    itself).
// Module           : App
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

enum Section: String, CaseIterable, Identifiable, Hashable {
    case dashboard, portfolio, assets, send, receive, swap, bridge, nfts, defi, futures, agents, alerts, activity, research, security, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Tableau de bord"; case .portfolio: "Portefeuille"; case .assets: "Actifs"; case .send: "Envoyer"; case .receive: "Recevoir"
        case .swap: "Échanger"; case .bridge: "Pont inter-chaînes"; case .nfts: "NFT"; case .defi: "DeFi"; case .futures: "Contrats à terme"
        case .agents: "Agents de trading"; case .alerts: "Alertes"; case .activity: "Activité"; case .research: "Recherche"; case .security: "Sécurité"; case .settings: "Réglages"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"; case .portfolio: "chart.pie"; case .assets: "bitcoinsign.circle"; case .send: "arrow.up.right"; case .receive: "arrow.down.left"
        case .swap: "arrow.left.arrow.right"; case .bridge: "point.topleft.down.to.point.bottomright.curvepath"; case .nfts: "photo.on.rectangle.angled"; case .defi: "building.columns"
        case .futures: "chart.line.uptrend.xyaxis"; case .agents: "cpu"; case .alerts: "bell"; case .activity: "list.bullet.rectangle"; case .research: "magnifyingglass"
        case .security: "lock.shield"; case .settings: "gearshape"
        }
    }
    /// Sections that only read: available in offline consultation.
    var readOnly: Bool { [.dashboard, .portfolio, .assets, .receive, .nfts, .activity].contains(self) }
    static let groups: [(String, [Section])] = [
        ("Portefeuille", [.dashboard, .portfolio, .assets, .send, .receive]),
        ("Opérations", [.swap, .bridge, .nfts, .defi]),
        ("Trading", [.futures, .agents, .research]),
        ("Suivi", [.alerts, .activity, .security, .settings]),
    ]
}

@MainActor @Observable final class Navigator {
    var section: Section = .dashboard
    /// Deep links between screens: "open the asset page of ETH on Base", "send this asset".
    var assetFocus: String?
    var sendPreset: SendPreset?
    struct SendPreset: Equatable { var network: String; var asset: String }
    func open(asset id: String) { assetFocus = id; section = .assets }
    func send(network: String, asset: String) { sendPreset = SendPreset(network: network, asset: asset); section = .send }
}
