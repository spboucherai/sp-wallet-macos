// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : SP Wallet for macOS
// File             : App/SPWalletApp.swift
// Description      : Entry point of SP Wallet for macOS: one main window
//                    (NavigationSplitView), a Settings scene and the app's menu
//                    commands. Every screen is SwiftUI/AppKit; no web view
//                    exists in this app.
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

@main struct SPWalletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var nav = Navigator()

    var body: some Scene {
        Window(AppEnvironment.isDevelopment ? "SP Wallet Dev" : "SP Wallet", id: "main") {
            RootView(model: model, nav: nav)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    delegate.model = model; await model.start()
                    #if SPW_DEV
                    await DevHarness.run(model: model, nav: nav)
                    #endif
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Actualiser") { Task { await model.refreshAll() } }.keyboardShortcut("r").disabled(model.phase != .signedIn)
                Divider()
                ForEach(Array(Section.allCases.prefix(9).enumerated()), id: \.element) { i, s in
                    Button(s.title) { nav.section = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                }
            }
            CommandMenu("Portefeuille") {
                Button("Envoyer…") { nav.section = .send }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!model.canOperate)
                Button("Recevoir") { nav.section = .receive }.keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Verrouiller l’app") { model.lock.lockNow() }.keyboardShortcut("l", modifiers: [.command, .control]).disabled(!model.lock.enabled)
                Button("Se déconnecter") { Task { await model.signOut(eraseLocalData: false) } }.disabled(model.phase != .signedIn)
            }
        }
        Settings { SettingsView(model: model).frame(width: 560) }
    }
}
