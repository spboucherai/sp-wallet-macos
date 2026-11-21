// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Core/Persistence/SnapshotStore.swift
// Description      : Offline snapshots: the last answers of read-only
//                    endpoints, kept as files in the app's sandbox container so
//                    that balances, addresses, history and NFT lists can be
//                    consulted without a connection — always shown with their
//                    date. Nothing secret is stored (no session, no key); files
//                    are excluded from backups.
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

struct Snapshot<T: Sendable>: Sendable { let value: T; let savedAt: Date }

actor SnapshotStore {
    static let shared = SnapshotStore(directory: AppEnvironment.supportDirectory.appendingPathComponent("snapshots", isDirectory: true))
    private let directory: URL
    private struct Envelope<T: Codable>: Codable { let savedAt: Date; let value: T }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var d = directory; var v = URLResourceValues(); v.isExcludedFromBackup = true; try? d.setResourceValues(v)
    }

    private func url(_ key: String) -> URL { directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json") }

    func save<T: Codable & Sendable>(_ value: T, as key: String, at date: Date = Date()) {
        guard let data = try? APICoding.encoder().encode(Envelope(savedAt: date, value: value)) else { return }
        try? data.write(to: url(key), options: [.atomic, .completeFileProtection])
    }
    func load<T: Codable & Sendable>(_ key: String, as type: T.Type = T.self) -> Snapshot<T>? {
        guard let data = try? Data(contentsOf: url(key)), let e = try? APICoding.decoder().decode(Envelope<T>.self, from: data) else { return nil }
        return Snapshot(value: e.value, savedAt: e.savedAt)
    }
    /// Sign-out and "erase local data": everything this Mac remembered about the wallet goes.
    func eraseAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
