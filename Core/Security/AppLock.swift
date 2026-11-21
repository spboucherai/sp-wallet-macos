// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : Core/Security/AppLock.swift
// Description      : Optional local lock of the app's window (Touch ID or the
//                    Mac's password, LocalAuthentication). It hides the
//                    screens; it authorizes NOTHING on the server: every
//                    operation still needs a passkey assertion bound to its
//                    intent.
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
import LocalAuthentication

@MainActor @Observable final class AppLock {
    static let enabledKey = "appLockEnabled", delayKey = "appLockDelaySeconds"
    private(set) var locked: Bool
    private(set) var lastError: String?
    private var resignedAt: Date?

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var delay: TimeInterval { let v = UserDefaults.standard.double(forKey: Self.delayKey); return v > 0 ? v : 60 }

    init() { locked = UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// True when this Mac can verify its owner (Touch ID, Apple Watch or the account password).
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
    static var biometryName: String {
        let c = LAContext(); _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType { case .touchID: return "Touch ID"; case .faceID: return "Face ID"; case .opticID: return "Optic ID"; default: return "le mot de passe du Mac" }
    }

    func appDidResign() { resignedAt = Date() }
    func appDidBecomeActive() {
        guard enabled, !locked, let r = resignedAt else { return }
        if Date().timeIntervalSince(r) >= delay { locked = true }
    }
    func lockNow() { if enabled { locked = true } }

    /// Offline consultation without a session: the Mac's owner is verified first, whatever the lock setting.
    private(set) var browseDenied = false
    func unlockForBrowse() async {
        let c = LAContext()
        browseDenied = (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "consulter les dernières données de SP Wallet")) != true
    }

    func unlock() async {
        let c = LAContext(); c.localizedCancelTitle = "Annuler"
        do {
            if try await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "déverrouiller SP Wallet") { locked = false; lastError = nil; resignedAt = nil }
        } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel { lastError = nil }
        catch { lastError = error.localizedDescription }
    }

    /// Turning the lock on or off itself requires the owner of the Mac.
    func setEnabled(_ on: Bool) async -> Bool {
        let c = LAContext()
        guard (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: on ? "activer le verrouillage de SP Wallet" : "désactiver le verrouillage de SP Wallet")) == true else { return false }
        UserDefaults.standard.set(on, forKey: Self.enabledKey); return true
    }
}
