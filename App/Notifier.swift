// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: App/Notifier.swift
// Description: macOS notifications for terminal outcomes only. A notification never announces a success before the chain finalized the transaction; 'diffusée' is never notified as done.
import Foundation
import UserNotifications
import SPWalletCore

@MainActor enum Notifier {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true }

    static func requestPermission() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false }

    static func post(title: String, body: String, id: String = UUID().uuidString) {
        guard enabled else { return }
        Task {
            let c = UNUserNotificationCenter.current()
            let s = await c.notificationSettings()
            if s.authorizationStatus == .notDetermined { _ = await requestPermission() }
            let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
            try? await c.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    /// Only for a terminal state, with the state's exact wording.
    static func proposal(_ p: Proposal) {
        guard p.state.isTerminal else { return }
        let what = "\(Fmt.amount(p.amountDisplay, maxFraction: 8)) \(p.symbol) · \(p.networkName ?? p.network)"
        if p.state.isSuccess { post(title: "Transaction finalisée", body: "\(what) — confirmée par la chaîne.", id: "p-\(p.id)") }
        else { post(title: "Transaction : \(ErrorText.state(p.state))", body: "\(what)\(p.error.map { " — \($0)" } ?? "")", id: "p-\(p.id)") }
    }
}
