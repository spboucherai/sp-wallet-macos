// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: App/AppEnvironment.swift
// Description: Where this build of the app connects and under which identifiers it stores things. Release = production wallet only; the development variant (Debug) = a local throwaway stack, never production.
import Foundation
import SPWalletCore

enum AppEnvironment {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    static let userAgent = "SPWallet-macOS/\(version) (\(build))"

    #if SPW_DEV
    static let isDevelopment = true
    static let keychainService = "ai.spboucher.spwallet.dev"
    /// The local stack started by Scripts/backend-dev.sh (test mnemonic generated on the spot, SPW_BROADCAST=off).
    static var configuration: APIConfiguration {
        let port = UserDefaults.standard.integer(forKey: "spwDevPort")
        let origin = URL(string: "http://localhost:\(port == 0 ? 8760 : port)")!
        return APIConfiguration(origin: origin, rpId: "localhost", userAgent: userAgent)
    }
    #else
    static let isDevelopment = false
    static let keychainService = "ai.spboucher.spwallet"
    static var configuration: APIConfiguration { .production(userAgent: userAgent) }
    #endif

    /// Application Support inside the sandbox container: offline snapshots, exports in progress. Nothing secret is written there.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SPWallet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
