// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: App/DevHarness.swift
// Description: DEVELOPMENT VARIANT ONLY (not compiled in Release): launch arguments that drive the app against the local throwaway stack for visual checks and scripted end-to-end runs. -spwAutoSetup YES enrols or signs in the software passkey; -spwSection <name> opens a section; -spwSelfTest YES runs the scripted checks and writes their result in the app's container.
#if SPW_DEV
import Foundation
import SPWalletCore

@MainActor enum DevHarness {
    static func run(model: AppModel, nav: Navigator) async {
        let d = UserDefaults.standard
        if d.bool(forKey: "spwAutoSetup") {
            if model.phase == .setupRequired, let t = d.string(forKey: "spwDevSetupToken") { await model.devSetup(token: t) }
            else if model.phase == .signedOut { await model.signIn() }
        }
        if let s = d.string(forKey: "spwSection"), let sec = Section(rawValue: s) { nav.section = sec }
        if d.bool(forKey: "spwSelfTest") { await DevSelfTest.run(model: model) }
    }
}
#endif
