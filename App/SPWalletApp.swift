// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: App/SPWalletApp.swift
// Description: Entry point of SP Wallet for macOS: one main window (NavigationSplitView), a Settings scene and the app's menu commands. Every screen is SwiftUI/AppKit; no web view exists in this app.
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
